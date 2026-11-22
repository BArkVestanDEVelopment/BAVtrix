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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            RainView(config: store.config)
                .ignoresSafeArea()
            Button {
                showSettings = true
            } label: {
                Text("Settings").glassPill()
            }
            .opacity(0.85)
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
