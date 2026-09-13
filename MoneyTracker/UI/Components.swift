import SwiftUI
import SwiftData
import Charts

// ── Merchant monogram (web components/Monogram.jsx) ──
// A colored tile from the merchant name — the same djb2 hash and palette as the web app,
// so a shop has the same color on both — with the category symbol as a corner badge.
enum MonogramPalette {
    static let colors = ["#e11d48", "#d97706", "#ca8a04", "#16a34a", "#0d9488", "#0284c7",
                         "#4f46e5", "#7c3aed", "#c026d3", "#db2777", "#dc2626", "#2563eb"]
    static func color(_ name: String) -> String {
        var h: UInt32 = 5381
        for u in name.lowercased().trimmed.utf16 { h = (h &<< 5) &+ h &+ UInt32(u) }
        return colors[Int(h % UInt32(colors.count))]
    }
}

func catSymbol(_ cat: TxCategory?) -> String? {
    let key = (cat?.sym.isEmpty ?? true) ? BackupService.builtInSym(cat?.id ?? "") : (cat?.sym ?? "")
    return Symbols.name(key)
}

struct Monogram: View {
    let name: String
    let cat: TxCategory?
    var size: CGFloat = 44
    var body: some View {
        let n = name.trimmed
        let catColor = Color(hex: cat?.colorHex ?? "#9ca3af")
        if n.isEmpty {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(catColor.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(CatGlyph(cat: cat, size: size * 0.4))
        } else {
            let col = Color(hex: MonogramPalette.color(n))
            let badge = (size * 0.42).rounded()
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [col.opacity(0.9), col], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(Text(String(n.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white))
                .overlay(alignment: .bottomTrailing) {
                    if cat != nil {
                        Circle().fill(catColor).frame(width: badge, height: badge)
                            .overlay {
                                if let s = catSymbol(cat) { Image(systemName: s).font(.system(size: badge * 0.5, weight: .bold)).foregroundStyle(.white) }
                                else { Text(cat?.icon ?? "").font(.system(size: badge * 0.55)) }
                            }
                            .overlay(Circle().stroke(Color.mtCard, lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
                }
        }
    }
}

/// A category symbol on its tinted tile (Insights, Categories, budgets).
struct CatTile: View {
    let cat: TxCategory?
    var size: CGFloat = 44
    var body: some View {
        RoundedRectangle(cornerRadius: MT.inner, style: .continuous)
            .fill(Color(hex: cat?.colorHex ?? "#9ca3af").opacity(0.15))
            .frame(width: size, height: size)
            .overlay(CatGlyph(cat: cat, size: size * 0.42))
    }
}

// ── Transaction row (web Home/Activity rows) ──
struct TxRowView: View {
    let r: Row
    let cats: [TxCategory]
    let accounts: [Account]
    var detailed = false

    var body: some View {
        let cat = cats.first { $0.id == r.categoryId }
        HStack(spacing: 12) {
            Monogram(name: r.merchant, cat: cat, size: detailed ? 44 : 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(r.merchant.isEmpty ? "Unknown" : r.merchant).font(.system(size: detailed ? 15 : 14, weight: .semibold)).lineLimit(1)
                    if r.needsReview {
                        Text("review").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.mtAcc.opacity(0.14), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(Color.mtAcc)
                    }
                }
                Text(subtitle(cat)).font(.system(size: detailed ? 12 : 11)).foregroundStyle(Color.mtTxt2).lineLimit(1)
                if detailed && !r.notes.isEmpty {
                    Text(r.notes).font(.system(size: 12)).italic().foregroundStyle(Color.mtTxt3).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(prefix + Fmt.money(r.personal)).money(detailed ? 16 : 14).foregroundStyle(color)
                if r.type == "expense", let s = r.share, s != r.amount {
                    Text("your share · of \(Fmt.money(r.amount))").font(.system(size: 10)).foregroundStyle(Color.mtTxt3)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func name(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "?" }
    private func subtitle(_ cat: TxCategory?) -> String {
        let day = Fmt.prettyDay(r.date)
        if r.cardPay { return "Card bill → \(name(r.toAccountId)) · \(day)" }
        if r.type == "transfer" { return "\(name(r.accountId)) → \(name(r.toAccountId)) · \(day)" }
        return detailed ? "\(day) · \(name(r.accountId)) · \(cat?.label ?? "Other")" : "\(name(r.accountId)) · \(day)"
    }
    private var prefix: String { r.isIn ? "+" : r.isOut ? "−" : "⇄ " }
    private var color: Color {
        switch r.type { case "income": .mtGreen; case "expense": .mtRed; case "credit", "debit": .mtRecv; default: .mtTxt2 }
    }
}

// ── Attention card (web HomeTab AlertRow) ──
struct Attention: Identifiable {
    let id: String
    let tone: Color
    let icon: String
    let title: String
    let sub: String
    let cta: String
    let action: () -> Void
}

struct AttentionRow: View {
    let a: Attention
    var big = false
    var body: some View {
        Button(action: { Haptic.tap(); a.action() }) {
            HStack(spacing: 11) {
                Circle().fill(a.tone.opacity(0.18)).frame(width: big ? 36 : 30, height: big ? 36 : 30)
                    .overlay(Image(systemName: a.icon).font(.system(size: big ? 16 : 13, weight: .semibold)).foregroundStyle(a.tone))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.title).font(.system(size: big ? 14.5 : 13.5, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(a.sub).font(.system(size: big ? 12 : 11.5)).foregroundStyle(Color.mtTxt2).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(a.cta) →").font(.system(size: big ? 13.5 : 12.5, weight: .semibold)).foregroundStyle(a.tone)
            }
            .padding(.horizontal, big ? 16 : 14).padding(.vertical, big ? 13 : 10)
            .background(a.tone.opacity(0.1), in: RoundedRectangle(cornerRadius: big ? MT.card : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: big ? MT.card : 14, style: .continuous).stroke(a.tone.opacity(0.26), lineWidth: 1))
        }
        .buttonStyle(.press)
    }
}

// ── Small building blocks ──
struct ProgressBar: View {
    let value: Double
    var color: Color = .mtAcc
    var height: CGFloat = 6
    var track: Color = .mtBorder
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(g.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(MT.spring, value: value)
    }
}

struct RingView<Content: View>: View {
    let value: Double
    var size: CGFloat = 78
    var stroke: CGFloat = 8
    var color: Color = .mtAcc
    var track: Color = .mtBorder
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(MT.spring, value: value)
            VStack(spacing: 0, content: content)
        }
        .frame(width: size, height: size)
    }
}

struct ChipButton: View {
    let title: String
    var systemImage: String? = nil
    var dot: Color? = nil
    let on: Bool
    var tint: Color = .mtAcc
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(on ? .white : dot).frame(width: 8, height: 8) }
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(on ? tint : Color.mtCard, in: Capsule())
            .overlay(Capsule().stroke(on ? tint : Color.mtBorder, lineWidth: 1.2))
            .foregroundStyle(on ? Color.white : Color.mtTxt2)
        }
        .buttonStyle(.press)
    }
}

/// An empty screen that says what it's for and offers the one thing to do next.
struct EmptyCard: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34, weight: .regular)).foregroundStyle(Color.mtTxt3).padding(.bottom, 4)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(message).font(.system(size: 13.5)).foregroundStyle(Color.mtTxt2).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 20)
        .mtCard(padding: 0)
    }
}

// ── Balance · 60 days (web BalanceChart) — green when the window trends up, red when down ──
struct BalanceChartView: View {
    let series: [(date: String, value: Double)]
    var body: some View {
        let up = (series.last?.value ?? 0) >= (series.first?.value ?? 0)
        let col: Color = up ? .mtGreen : .mtRed
        let pts = Array(series.enumerated())
        let lo = series.map(\.value).min() ?? 0, hi = series.map(\.value).max() ?? 1
        let pad = max((hi - lo) * 0.12, 1)
        VStack(spacing: 4) {
            Chart {
                ForEach(pts, id: \.offset) { i, p in
                    AreaMark(x: .value("Day", i), yStart: .value("Base", lo - pad), yEnd: .value("Balance", p.value))
                        .foregroundStyle(LinearGradient(colors: [col.opacity(0.18), col.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", i), y: .value("Balance", p.value))
                        .foregroundStyle(col).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if lo < 0 && hi > 0 { RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.mtBorder).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])) }
                if let last = pts.last {
                    PointMark(x: .value("Day", last.offset), y: .value("Balance", last.element.value)).foregroundStyle(col).symbolSize(40)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .frame(height: 96)
            HStack {
                Text(series.first.map { let p = CardMath.parts($0.date); return "\(p.d).\(p.m)." } ?? "")
                Spacer()
                Text("today")
            }
            .font(.system(size: 9)).foregroundStyle(Color.mtTxt3)
        }
    }
}

/// Income vs spending, month by month (web MiniChart).
struct IncomeSpendChart: View {
    let data: [(key: String, income: Double, spent: Double)]
    var height: CGFloat = 150
    var selection: Binding<String?>? = nil
    var body: some View {
        let chart = Chart {
            if let sel = selection?.wrappedValue {
                RuleMark(x: .value("Month", sel)).foregroundStyle(Color.mtAcc.opacity(0.12)).lineStyle(StrokeStyle(lineWidth: 34))
            }
            ForEach(data, id: \.key) { m in
                BarMark(x: .value("Month", Self.label(m.key)), y: .value("Amount", m.income), width: 10)
                    .position(by: .value("Kind", "Income")).foregroundStyle(Color.mtGreen).cornerRadius(3)
                BarMark(x: .value("Month", Self.label(m.key)), y: .value("Amount", m.spent), width: 10)
                    .position(by: .value("Kind", "Spent")).foregroundStyle(Color.mtRed.opacity(0.85)).cornerRadius(3)
            }
        }
        .chartXScale(domain: data.map { Self.label($0.key) })   // keep month order when one is highlighted
        .chartForegroundStyleScale(["Income": Color.mtGreen, "Spent": Color.mtRed.opacity(0.85)])
        .chartLegend(position: .top, alignment: .trailing)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.mtBorder) } }
        .frame(height: height)
        if let selection {
            // A plain tap picks a month (tap it again to let go) — the built-in selection needs a drag.
            chart.chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            guard let plot = proxy.plotFrame else { return }
                            let x = loc.x - geo[plot].origin.x
                            if let v: String = proxy.value(atX: x) {
                                Haptic.tap()
                                withAnimation(MT.spring) { selection.wrappedValue = selection.wrappedValue == v ? nil : v }
                            }
                        }
                }
            }
        } else { chart }
    }
    static func label(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return key }
        let f = DateFormatter(); f.dateFormat = "MMM"
        return f.string(from: Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: 1)) ?? Date())
    }
}
