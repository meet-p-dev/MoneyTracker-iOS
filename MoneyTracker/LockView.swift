import SwiftUI
import LocalAuthentication

struct LockView: View {
    @Binding var locked: Bool
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("MoneyTracker locked")
                    .font(.headline)
                if failed {
                    Button("Try again", action: authenticate)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        failed = false
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            locked = false   // no passcode set on device — don't lock the user out
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock MoneyTracker") { ok, _ in
            DispatchQueue.main.async {
                if ok { Haptic.success(); locked = false } else { failed = true }
            }
        }
    }
}
