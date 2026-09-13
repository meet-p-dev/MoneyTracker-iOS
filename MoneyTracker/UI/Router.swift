import SwiftUI
import Observation

// Web V11 navigation: Home · Activity · [+] · Insights · Wallet. Every number that leads
// somewhere goes through here (Income → Activity filtered to income, a top category →
// its merchants in Insights, a card → its screen in Wallet…).
enum AppTab: Hashable { case home, activity, insights, wallet }

@Observable
final class Router {
    var tab: AppTab = .home
    var showAdd = false
    var showTour = false
    var showProfile = false
    // Activity filters
    var activityType = ""
    var activitySearch = ""
    var activityCat = ""
    var activityAcc = ""
    // Insights
    var insightsView = "spend"
    var spendMonth = "all"
    var drillCat: String? = nil
    // Wallet
    var walletSection = "accounts"
    var openCardId: String? = nil

    func goActivity(type: String = "", search: String = "", cat: String = "", acc: String = "") {
        activityType = type; activitySearch = search; activityCat = cat; activityAcc = acc
        withAnimation(MT.spring) { tab = .activity }
    }
    func goInsights(_ view: String, drill: String? = nil) {
        insightsView = view; drillCat = drill
        withAnimation(MT.spring) { tab = .insights }
    }
    func goWallet(_ section: String, card: String? = nil) {
        walletSection = section; openCardId = card
        withAnimation(MT.spring) { tab = .wallet }
    }
}
