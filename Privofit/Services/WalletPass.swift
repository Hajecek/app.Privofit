import CryptoKit
import PassKit
import SwiftUI
import UIKit

// Apple Wallet accepts only a pass signed with a Pass Type ID certificate.
// The demo builds the same card locally. The live API returns the signed .pkpass.
enum WalletZip {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 1 ? 0xEDB8_8320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func archive(_ files: [String: Data]) -> Data {
        var local = Data()
        var central = Data()
        for (name, content) in files.sorted(by: { $0.key < $1.key }) {
            let nameData = Data(name.utf8)
            let crc = checksum(content)
            let offset = UInt32(local.count)
            var header = Data()
            header.append(le(UInt32(0x0403_4B50)))
            header.append(le(UInt16(20)))
            header.append(le(UInt16(0)))
            header.append(le(UInt16(0)))
            header.append(le(UInt16(0)))
            header.append(le(UInt16(0)))
            header.append(le(crc))
            header.append(le(UInt32(content.count)))
            header.append(le(UInt32(content.count)))
            header.append(le(UInt16(nameData.count)))
            header.append(le(UInt16(0)))
            header.append(nameData)
            header.append(content)
            local.append(header)

            var directory = Data()
            directory.append(le(UInt32(0x0201_4B50)))
            directory.append(le(UInt16(20)))
            directory.append(le(UInt16(20)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(crc))
            directory.append(le(UInt32(content.count)))
            directory.append(le(UInt32(content.count)))
            directory.append(le(UInt16(nameData.count)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt16(0)))
            directory.append(le(UInt32(0)))
            directory.append(le(offset))
            directory.append(nameData)
            central.append(directory)
        }
        let centralOffset = UInt32(local.count)
        var end = Data()
        end.append(le(UInt32(0x0605_4B50)))
        end.append(le(UInt16(0)))
        end.append(le(UInt16(0)))
        end.append(le(UInt16(files.count)))
        end.append(le(UInt16(files.count)))
        end.append(le(UInt32(central.count)))
        end.append(le(centralOffset))
        end.append(le(UInt16(0)))
        local.append(central)
        local.append(end)
        return local
    }

    static func entries(_ archive: Data) -> [String: Data] {
        let bytes = [UInt8](archive)
        var result: [String: Data] = [:]
        var offset = 0
        func u16(_ index: Int) -> Int { Int(bytes[index]) | (Int(bytes[index + 1]) << 8) }
        func u32(_ index: Int) -> UInt32 {
            UInt32(bytes[index])
                | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16)
                | (UInt32(bytes[index + 3]) << 24)
        }
        while offset + 30 <= bytes.count {
            let signature = u32(offset)
            if signature == 0x0201_4B50 || signature == 0x0605_4B50 { break }
            guard signature == 0x0403_4B50 else { break }
            let method = u16(offset + 8)
            let crc = u32(offset + 14)
            let size = Int(u32(offset + 18))
            let nameLength = u16(offset + 26)
            let extraLength = u16(offset + 28)
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + size
            guard method == 0, nameStart + nameLength <= bytes.count, dataEnd <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let payload = Data(bytes[dataStart..<dataEnd])
            if checksum(payload) == crc { result[name] = payload }
            offset = dataEnd
        }
        return result
    }

    private static func le(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func le(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}

@MainActor
enum WalletPassArchive {
    static let passTypeIdentifier = "pass.cz.privofit.cz"
    private static let ink = UIColor(red: 16 / 255, green: 23 / 255, blue: 20 / 255, alpha: 1)
    private static let moss = UIColor(red: 46 / 255, green: 63 / 255, blue: 50 / 255, alpha: 1)
    private static let lime = UIColor(red: 198 / 255, green: 242 / 255, blue: 26 / 255, alpha: 1)

    static func make(member: Member, membership: Membership) throws -> Data {
        var files: [String: Data] = [
            "pass.json": try passJSON(member: member, membership: membership, includesLogo: brandLogo() != nil),
            "icon.png": icon(pixels: 29),
            "icon@2x.png": icon(pixels: 58),
            "icon@3x.png": icon(pixels: 87),
            "strip.png": strip(pixels: CGSize(width: 375, height: 144)),
            "strip@2x.png": strip(pixels: CGSize(width: 750, height: 288)),
            "strip@3x.png": strip(pixels: CGSize(width: 1125, height: 432))
        ]
        if brandLogo() != nil {
            files["logo.png"] = logo(pixels: CGSize(width: 160, height: 50))
            files["logo@2x.png"] = logo(pixels: CGSize(width: 320, height: 100))
            files["logo@3x.png"] = logo(pixels: CGSize(width: 480, height: 150))
        }
        let hashes = files.mapValues { data in
            Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        files["manifest.json"] = try JSONSerialization.data(withJSONObject: hashes, options: [.sortedKeys])
        return WalletZip.archive(files)
    }

    private static func passJSON(member: Member, membership: Membership, includesLogo: Bool) throws -> Data {
        let name = member.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        var auxiliary: [[String: String]] = [dateField("until", L10n.tr("membership.until"), membership.validUntil)]
        if let entries = membership.remainingEntries {
            auxiliary.append(["key": "entries", "label": L10n.tr("membership.entries"), "value": entries.formatted()])
        }
        var back: [[String: String]] = [
            ["key": "status", "label": L10n.tr("wallet.field.status"), "value": L10n.tr("membership.status.\(membership.status.rawValue)")],
            ["key": "username", "label": L10n.tr("profile.username"), "value": member.username]
        ]
        if let from = membership.validFrom {
            back.append(dateField("from", L10n.tr("membership.from"), from))
        }
        var object: [String: Any] = [
            "formatVersion": 1,
            "passTypeIdentifier": passTypeIdentifier,
            "serialNumber": member.id,
            "teamIdentifier": "W6R3HZD7R4",
            "organizationName": "PRIVOFIT",
            "description": L10n.tr("wallet.description"),
            "foregroundColor": "rgb(232, 240, 228)",
            "backgroundColor": "rgb(16, 23, 20)",
            "labelColor": "rgb(198, 242, 26)",
            "expirationDate": iso(membership.validUntil),
            "sharingProhibited": true,
            "voided": !membership.isActive,
            "storeCard": [
                "primaryFields": [[
                    "key": "name",
                    "label": L10n.tr("redesign.digitalPass"),
                    "value": name.isEmpty ? "PRIVOFIT" : name
                ]],
                "secondaryFields": [["key": "title", "label": "PRIVOFIT", "value": membership.title]],
                "auxiliaryFields": auxiliary,
                "backFields": back
            ]
        ]
        if !includesLogo { object["logoText"] = "PRIVOFIT" }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func dateField(_ key: String, _ label: String, _ date: Date) -> [String: String] {
        ["key": key, "label": label, "value": iso(date), "dateStyle": "PKDateStyleMedium"]
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func brandLogo() -> UIImage? {
        UIImage(named: "BrandLogo", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .dark))
    }

    private static func icon(pixels: CGFloat) -> Data {
        png(CGSize(width: pixels, height: pixels), opaque: true) { _, size in
            lime.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let inset = size.width * 0.06
            UIImage(named: "BrandIcon")?.draw(in: CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2))
        }
    }

    private static func logo(pixels: CGSize) -> Data {
        png(pixels, opaque: false) { _, size in
            guard let image = brandLogo() else { return }
            let aspect = image.size.width / max(image.size.height, 1)
            var height = size.height * 0.78
            var width = height * aspect
            if width > size.width {
                width = size.width
                height = width / max(aspect, 0.01)
            }
            image.draw(in: CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height))
        }
    }

    private static func strip(pixels: CGSize) -> Data {
        png(pixels, opaque: true) { context, size in
            let colors = [moss.cgColor, ink.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            context.setStrokeColor(lime.cgColor)
            context.setLineWidth(max(10, size.width * 0.018))
            let diameter = size.height * 1.2
            context.strokeEllipse(in: CGRect(x: size.width - diameter * 0.42, y: -diameter * 0.55, width: diameter, height: diameter))
        }
    }

    private static func png(_ size: CGSize, opaque: Bool, draw: (CGContext, CGSize) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).pngData { renderer in
            draw(renderer.cgContext, size)
        }
    }
}

@MainActor
final class WalletPassCoordinator: NSObject, @MainActor PKAddPassesViewControllerDelegate {
    static let shared = WalletPassCoordinator()
    private var onFinish: (@MainActor () -> Void)?
    private var isPresenting = false

    func present(_ pass: PKPass, onFinish: @escaping @MainActor () -> Void) {
        guard !isPresenting else { return }
        guard PKAddPassesViewController.canAddPasses(), let host = Self.host else {
            onFinish()
            return
        }
        guard let controller = PKAddPassesViewController(pass: pass) else {
            onFinish()
            return
        }
        isPresenting = true
        self.onFinish = onFinish
        controller.delegate = self
        host.present(controller, animated: true)
    }

    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        let finish = onFinish
        onFinish = nil
        isPresenting = false
        controller.dismiss(animated: true) {
            Task { @MainActor in finish?() }
        }
    }

    private static var host: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

struct MembershipWalletButton: View {
    @Environment(AppModel.self) private var app
    @State private var stored: PKPass?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MemberPass(
                name: app.member?.firstName ?? "Privofit",
                hint: stored == nil ? L10n.tr("wallet.tap") : L10n.tr("wallet.open"),
                action: canAdd ? { Task { await activate() } } : nil
            )
            .overlay { if busy { ProgressView().tint(Brand.lime) } }
            .opacity(busy ? 0.72 : 1)
            .allowsHitTesting(!busy)
            if stored != nil {
                Label(L10n.tr("wallet.inWallet"), systemImage: "wallet.pass").font(.subheadline.weight(.semibold))
            } else if canAdd {
                Text(L10n.tr("wallet.tap")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("wallet.unavailable")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.subheadline).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("membership.wallet")
        .task(id: refreshKey) { await refresh() }
    }

    private var canAdd: Bool { PKAddPassesViewController.canAddPasses() }

    private func activate() async {
        if stored != nil { open(); return }
        await add()
    }

    private var refreshKey: String {
        guard let membership = app.membership, let member = app.member else { return "" }
        return "\(member.id)|\(membership.status.rawValue)|\(membership.validUntil.timeIntervalSince1970)|\(membership.remainingEntries ?? -1)"
    }

    private func refresh() async {
        guard let pass = try? await load() else { return }
        stored = PKPassLibrary().containsPass(pass) ? pass : nil
    }

    private func add() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let pass = try await load()
            if PKPassLibrary().containsPass(pass) {
                stored = pass
                return
            }
            WalletPassCoordinator.shared.present(pass) {
                Task { @MainActor in await refresh() }
            }
        } catch is CancellationError {
        } catch let failure as AppFailure {
            self.error = FriendlyError.message(failure)
        } catch {
            self.error = L10n.tr(app.isDemo ? "wallet.demo" : "wallet.invalid")
        }
    }

    private func open() {
        guard let url = stored?.passURL else {
            error = L10n.tr("wallet.invalid")
            return
        }
        UIApplication.shared.open(url)
    }

    private func load() async throws -> PKPass {
        if !app.isDemo, let remote = try? await app.service.membershipPass(), let pass = try? PKPass(data: remote) {
            return pass
        }
        guard let member = app.member, let membership = app.membership else { throw AppFailure.unavailable }
        return try PKPass(data: try WalletPassArchive.make(member: member, membership: membership))
    }
}

