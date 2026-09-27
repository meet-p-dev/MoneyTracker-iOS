import AppIntents
import SwiftData

// The action a Shortcuts "Wallet" automation runs after each Apple Pay tap. It works in the
// background (MoneyTrack doesn't open) and asks nothing. Map the automation's fields straight
// into it: Merchant, Amount, Card or Pass, and Name. Passing the whole transaction through
// another shortcut loses these fields.
struct LogWalletPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Apple Pay payment"
    static let description = IntentDescription("Adds an Apple Pay payment to MoneyTrack. Use it in a Wallet automation.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Amount") var amount: IntentCurrencyAmount?
    @Parameter(title: "Amount as text") var amountText: String?
    @Parameter(title: "Card") var card: String?
    @Parameter(title: "Name") var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
            \.$name
            \.$amountText
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        TapSettle.intake(ctx: AppData.container.mainContext, merchant: merchant, name: name, card: card,
                         amount: amount?.amount, code: amount?.currencyCode, text: amountText)
        return .result()
    }
}
