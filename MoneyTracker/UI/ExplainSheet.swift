import SwiftUI

// "How is this calculated?" — the key numbers explained with YOUR numbers, in plain words.
struct ExplainLine: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var tone: Color = .primary
    var sub: String? = nil
}

struct Explanation: Identifiable {
    let id = UUID()
    let title: String
    let intro: String
    let lines: [ExplainLine]
    let total: ExplainLine?
    let note: String?
}

struct ExplainSheet: View {
    @Environment(\.dismiss) private var dismiss
    let e: Explanation
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(e.intro).font(.system(size: 15)).foregroundStyle(Color.mtTxt2)
                    VStack(spacing: 0) {
                        ForEach(Array(e.lines.enumerated()), id: \.element.id) { i, l in
                            if i > 0 { Divider().overlay(Color.mtBorder) }
                            row(l, bold: false)
                        }
                        if let t = e.total {
                            Rectangle().fill(Color.primary.opacity(0.7)).frame(height: 1.5).padding(.vertical, 2)
                            row(t, bold: true)
                        }
                    }
                    .mtCard(padding: 14)
                    if let n = e.note {
                        Label(n, systemImage: "lightbulb").font(.system(size: 13)).foregroundStyle(Color.mtTxt2)
                    }
                }
                .padding(16)
            }
            .mtCanvas()
            .navigationTitle(e.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
    private func row(_ l: ExplainLine, bold: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l.label).font(.system(size: 15, weight: bold ? .bold : .regular))
                if let s = l.sub { Text(s).font(.system(size: 11.5)).foregroundStyle(Color.mtTxt3) }
            }
            Spacer()
            Text(l.value).money(15, bold ? .bold : .semibold).foregroundStyle(l.tone)
        }
        .padding(.vertical, 9)
    }
}

/// The small ⓘ that opens an explanation.
struct InfoButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.mtTxt3)
                .padding(4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How is this calculated?")
    }
}
