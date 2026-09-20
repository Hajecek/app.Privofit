import PassKit
import SwiftUI

@MainActor
final class ApplePayCheckout: NSObject, PKPaymentAuthorizationControllerDelegate {
    static let networks: [PKPaymentNetwork] = [.visa, .masterCard, .maestro, .amex]
    static var canMakePayments: Bool { PKPaymentAuthorizationController.canMakePayments() }
    static func demoToken() -> ApplePayToken {
        ApplePayToken(transactionIdentifier: "demo-\(UUID().uuidString)", paymentData: Data("demo".utf8), displayName: "Demo", network: "Visa")
    }
    static func paymentRequest(quote: BookingQuote, merchantID: String, merchantName: String) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantID
        request.supportedNetworks = networks
        request.merchantCapabilities = [.threeDSecure]
        request.countryCode = "CZ"
        request.currencyCode = quote.currencyCode
        request.supportedCountries = ["CZ"]
        let item = quote.slots.count == 1
            ? L10n.tr("reservations.applePay.itemOne")
            : "\(quote.slots.count) \(L10n.tr("reservations.applePay.itemMany"))"
        let amount = NSDecimalNumber(decimal: quote.total)
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: item, amount: amount),
            PKPaymentSummaryItem(label: merchantName, amount: amount, type: .final)
        ]
        return request
    }

    private var continuation: CheckedContinuation<BookingPayment, Error>?
    private var controller: PKPaymentAuthorizationController?
    private var charge: ((ApplePayToken) async throws -> BookingPayment)?

    func pay(
        quote: BookingQuote,
        merchantName: String = "Privofit",
        charge: @escaping (ApplePayToken) async throws -> BookingPayment
    ) async throws -> BookingPayment {
        guard continuation == nil else { throw AppFailure.unavailable }
        guard let merchantID = Configuration.applePayMerchantID else {
            throw AppFailure.notConfigured("Apple Pay merchant ID")
        }
        self.charge = charge
        let request = Self.paymentRequest(quote: quote, merchantID: merchantID, merchantName: merchantName)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            controller.delegate = self
            self.controller = controller
            controller.present { [weak self] presented in
                if !presented {
                    Task { @MainActor in self?.finish(throwing: AppFailure.unavailable) }
                }
            }
        }
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let token = ApplePayToken(
            transactionIdentifier: payment.token.transactionIdentifier,
            paymentData: payment.token.paymentData,
            displayName: payment.token.paymentMethod.displayName,
            network: payment.token.paymentMethod.network?.rawValue
        )
        Task { @MainActor in
            do {
                guard let charge else { throw AppFailure.unavailable }
                let payment = try await charge(token)
                let success = payment.status == .paid
                completion(PKPaymentAuthorizationResult(status: success ? .success : .failure, errors: nil))
                if success { finish(returning: payment) }
                else { finish(throwing: AppFailure.unavailable) }
            } catch {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                finish(throwing: error)
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            Task { @MainActor in
                self?.controller = nil
                self?.finish(throwing: AppFailure.cancelled)
            }
        }
    }

    private func finish(returning value: BookingPayment) {
        continuation?.resume(returning: value)
        clear()
    }
    private func finish(throwing error: Error) {
        continuation?.resume(throwing: error)
        clear()
    }
    private func clear() {
        continuation = nil
        charge = nil
    }
}

struct ApplePayButton: UIViewRepresentable {
    var enabled = true
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .automatic)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.cornerRadius = 20
        return button
    }
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
        uiView.isEnabled = enabled
        uiView.alpha = enabled ? 1 : 0.4
        uiView.isUserInteractionEnabled = enabled
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
