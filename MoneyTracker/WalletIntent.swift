import AppIntents
import SwiftData

// The action a Shortcuts "Wallet" automation runs after each Apple Pay tap. It works in the
// background (MoneyTrack doesn't open) and asks nothing. Map the automation's fields straight
// into it: Merchant, Amount, Card or Pass, and Name. Passing the whole transaction through
// another shortcut loses these fields.
struct LogWalletPaymentIntent: AppIntent {
    // App Store Connect rejects intent titles and descriptions that contain "Apple" (error 90626).
    static let title: LocalizedStringResource = "Log a Wallet payment"
    static let description = IntentDescription("Adds a Wallet payment to MoneyTrack. Use it in a Wallet automation.")
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

// The action an iOS 27 Shortcuts "Notification" automation runs when a banking app (Sparkasse,
// Revolut, Wallet…) shows a notification. It reads the payment out of the text, in the
// background. Map the automation's App, Title, Subtitle and Body into it.
struct LogBankNotificationIntent: AppIntent {
    // App Store Connect rejects intent titles and descriptions that contain "Apple" (error 90626).
    static let title: LocalizedStringResource = "Log a bank notification"
    static let description = IntentDescription("Adds the payment from a banking app's notification to MoneyTrack. Use it in a Notification automation.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App") var app: String?
    @Parameter(title: "Title") var title: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "Body") var body: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log the payment in \(\.$body)") {
            \.$app
            \.$title
            \.$subtitle
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        TapSettle.intakeNote(ctx: AppData.container.mainContext, app: app, title: title, subtitle: subtitle, body: body)
        return .result()
    }
}
