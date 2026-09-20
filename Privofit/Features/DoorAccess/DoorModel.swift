import Foundation
import Observation
import UIKit

enum DoorState: Equatable {
    case idle, checking, authenticating, sending, confirmed, cooldown, accepted, uncertain, denied(String), failed(String)
    var isFailure: Bool { switch self { case .denied, .failed: return true; default: return false } }
    var busy: Bool { self == .checking || self == .authenticating || self == .sending }
    var canSend: Bool { switch self { case .idle, .failed, .denied: return true; default: return false } }
}
@MainActor @Observable final class DoorModel {
    private(set) var state: DoorState = .idle
    private(set) var prepared = false
    private(set) var isPreview = false
    private(set) var doorName: String?
    private(set) var confirmedAt: Date?
    private(set) var entryUntil: Date?
    private let isActive: @MainActor () -> Bool
    private var pending: PendingDoorCommand?
    let app: AppModel
    init(app: AppModel, isActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) { self.app = app; self.isActive = isActive }
    #if DEBUG
    func previewState(_ value: DoorState) { state = value; prepared = true; isPreview = true }
    #endif
    func restorePending() async {
        guard app.phase == .authenticated, let memberID = app.member?.id else { return }
        if app.cooldownUntil > Date() { state = .cooldown }
        if app.isDemo {
            if let command = app.unconfirmedDoorCommands[memberID] { pending = command; state = .uncertain }
            prepared = true; return
        }
        do {
            if let command = try await app.vault.pendingDoor(for: memberID), command.memberID == memberID {
                pending = command; state = .uncertain
            }
            prepared = true
        } catch { state = .uncertain; prepared = false }
    }
    func open() async {
        guard !app.doorRequestInFlight, prepared, app.cooldownUntil <= Date(), state.canSend, app.phase == .authenticated, !app.locked, let userID = app.member?.id else { return }
        app.doorRequestInFlight = true
        defer { app.doorRequestInFlight = false }
        state = .checking
        let eligibility: DoorEligibility
        do {
            let stored: PendingDoorCommand?
            if app.isDemo { stored = app.unconfirmedDoorCommands[userID] }
            else { stored = try await app.vault.pendingDoor(for: userID) }
            if let stored { pending = stored; state = .uncertain; return }
            eligibility = try await app.service.eligibility()
            doorName = eligibility.doorName ?? L10n.tr("door.entrance")
            guard eligibility.allowed else { state = .denied(eligibility.reason ?? L10n.tr("door.denied")); return }
            if app.biometrics.available {
                state = .authenticating
                try await app.biometrics.authenticate(reason: L10n.tr("biometry.reason"))
            } else if app.preferences.biometrics {
                throw AppFailure.biometricsUnavailable
            }
            try Task.checkCancellation()
            guard app.phase == .authenticated, app.member?.id == userID, !app.locked,
                  isActive() else { throw AppFailure.sessionChanged }
            guard eligibility.expiresAt > Date() else { throw AppFailure.unavailable }
            let command = PendingDoorCommand(memberID: userID, requestID: UUID(), operationID: nil, createdAt: Date())
            if !app.isDemo { try await app.vault.saveDoor(command) }
            pending = command
            app.unconfirmedDoorCommands[userID] = command
        } catch let failure as AppFailure where failure == .cancelled || failure == .biometricsUnavailable {
            state = .failed(L10n.tr("door.biometry.failed"))
            app.handle(failure, surface: false)
            return
        } catch { state = .failed(FriendlyError.message(error)); app.handle(error, surface: false); return }
        guard let pending else { state = .failed(L10n.tr("door.failed")); return }
        guard app.phase == .authenticated, app.member?.id == userID, !app.locked, isActive() else {
            // Persistence suspended; the app may have gone to the background.
            // No HTTP command has been dispatched, so this intent can be removed.
            if !app.isDemo { try? await app.vault.clearDoor(for: pending.memberID) }
            app.unconfirmedDoorCommands[pending.memberID] = nil
            self.pending = nil; state = .failed(L10n.tr("error.cancelled")); return
        }
        state = .sending
        do {
            // Never retry a physical command automatically, including on 401/timeout.
            let receipt = try await app.service.openDoor(doorID: eligibility.doorID, requestID: pending.requestID)
            guard app.member?.id == userID, app.phase == .authenticated else { state = .uncertain; return }
            try await apply(receipt, pending: pending)
        } catch { state = .uncertain; app.handle(error, surface: false) }
    }
    func reconcile() async {
        guard !state.busy, let pending, app.member?.id == pending.memberID,
              app.phase == .authenticated, !app.locked else { return }
        state = .checking
        do { let receipt = try await app.service.doorStatus(requestID: pending.requestID, operationID: pending.operationID)
            guard app.member?.id == pending.memberID else { state = .uncertain; return }
            try await apply(receipt, pending: pending)
        } catch { state = .uncertain; app.handle(error, surface: false) }
    }
    func advanceCooldown() {
        if state == .confirmed { state = .cooldown }
        if state == .cooldown && app.cooldownUntil <= Date() { state = .idle }
    }
    private func apply(_ receipt: DoorReceipt, pending: PendingDoorCommand) async throws {
        switch receipt.outcome {
        case .confirmedOpen:
            if !app.isDemo { try await app.vault.clearDoor(for: pending.memberID) }
            app.unconfirmedDoorCommands[pending.memberID] = nil
            self.pending = nil; entryUntil = receipt.entryUntil; confirmedAt = Date(); app.cooldownUntil = Date().addingTimeInterval(8); state = .confirmed
        case .denied:
            if !app.isDemo { try await app.vault.clearDoor(for: pending.memberID) }
            app.unconfirmedDoorCommands[pending.memberID] = nil
            self.pending = nil; state = .denied(receipt.message ?? L10n.tr("door.denied"))
        case .accepted:
            let command = PendingDoorCommand(memberID: pending.memberID, requestID: pending.requestID, operationID: receipt.operationID, createdAt: pending.createdAt)
            if !app.isDemo { try await app.vault.saveDoor(command) }
            app.unconfirmedDoorCommands[pending.memberID] = command
            self.pending = command; state = .accepted
        }
    }
}
