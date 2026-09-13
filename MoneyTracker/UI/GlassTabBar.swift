import SwiftUI
import TipKit

// The tab bar, drawn by the app so the "+" can be the big centre button the web app has:
// a Liquid Glass capsule with the four places, and a raised, tinted glass "+" on top.
struct GlassTabBar: View {
    @Bindable var router: Router
    @Namespace private var ns
    private let addTip = AddTip()

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                item(.home, "Home", "house.fill")
                item(.activity, "Activity", "list.bullet")
                Color.clear.frame(width: 74, height: 1)
                item(.insights, "Insights", "chart.pie.fill")
                item(.wallet, "Wallet", "wallet.bifold.fill")
            }
            .padding(6)
            .glassEffect(.regular.interactive(), in: Capsule())

            Button { Haptic.tap(); router.showAdd = true } label: {
                Image(systemName: "plus").font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.mtAcc).interactive(), in: Circle())
            .shadow(color: Color.mtAcc.opacity(0.35), radius: 14, x: 0, y: 6)
            .offset(y: -12)
            .accessibilityLabel("Add transaction")
            .popoverTip(addTip, arrowEdge: .bottom)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private func item(_ tab: AppTab, _ title: String, _ icon: String) -> some View {
        let on = router.tab == tab
        return Button { Haptic.tap(); withAnimation(MT.spring) { router.tab = tab } } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .foregroundStyle(on ? Color.mtAcc : Color.primary)
            .background { if on { Capsule().fill(Color.mtAcc.opacity(0.13)).matchedGeometryEffect(id: "tab", in: ns) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension View {
    /// Each tab hides the system bar and keeps room at the bottom for the glass bar.
    func mtTabContent() -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 80) }
    }
}
