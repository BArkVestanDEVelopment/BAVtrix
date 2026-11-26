import SwiftUI
import BAVtrixCore

@main
struct BAVtrixApp: App {
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var showSettings = false
    // A tap on the rain hides or shows the Settings button; the hint is shown only once.
    @State private var buttonHidden = false
    @State private var showTapHint = false
    @AppStorage("didShowTapHint") private var didShowTapHint = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            RainView(config: store.config)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { toggleButton() }
            if showTapHint {
                Text("Tap to show Settings")
                    .font(Brand.font(14))
                    .foregroundColor(Brand.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Brand.glass.opacity(0.92)))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            Button {
                showSettings = true
            } label: {
                Text("Settings").glassPill()
            }
            .opacity(buttonHidden ? 0 : 0.85)
            .allowsHitTesting(!buttonHidden)
            .accessibilityHidden(buttonHidden)
            .padding(20)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .onAppear {
            // Screenshots in CI: launch with `-showSettings YES` to open the settings sheet.
            if UserDefaults.standard.bool(forKey: "showSettings") { showSettings = true }
        }
    }

    private func toggleButton() {
        withAnimation(.easeInOut(duration: 0.25)) {
            buttonHidden.toggle()
            if !buttonHidden { showTapHint = false }
        }
        guard buttonHidden, !didShowTapHint else { return }
        didShowTapHint = true
        withAnimation(.easeInOut(duration: 0.25)) { showTapHint = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.4)) { showTapHint = false }
        }
    }
}

struct RainView: UIViewRepresentable {
    var config: RainConfig

    func makeUIView(context: Context) -> RainUIView {
        let view = RainUIView()
        view.config = config
        return view
    }

    func updateUIView(_ view: RainUIView, context: Context) {
        view.config = config
    }
}
