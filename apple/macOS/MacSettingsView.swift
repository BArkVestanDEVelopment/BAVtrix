import SwiftUI
import BAVtrixCore

struct MacSettingsView: View {
    @ObservedObject var store: MacSettings

    var body: some View {
        Form {
            Section("Desktop") {
                Toggle("Hide desktop icons", isOn: $store.coverIcons)
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }))
            }
            Section("Rain") {
                slider("Density", floatBinding(\.spawnRate), 0.05...0.97, "%.0f%%", 100)
                slider("Speed variance", floatBinding(\.speedVariance), 1...20, "%.0f", 1)
                slider("Step time, ms", floatBinding(\.refreshMs), 10...300, "%.0f", 1)
                slider("Symbol size", floatBinding(\.glyphSize), 5...30, "%.0f pt", 1)
                slider("Special text, %", floatBinding(\.specialProbability), 0...1, "%.0f%%", 100)
            }
            Section("Trail") {
                Stepper(value: intBinding(\.trailMin), in: 2...200) {
                    row("Min. trail length", "\(store.config.trailMin)")
                }
                Stepper(value: intBinding(\.trailMax), in: 0...300) {
                    row("Max. length (0 = auto)", "\(store.config.trailMax)")
                }
            }
            Section("Flicker") {
                slider("Symbols in the trail", floatBinding(\.flicker), 0...1, "%.0f%%", 100)
                slider("Stream head", floatBinding(\.headFlicker), 0...1, "%.0f%%", 100)
                slider("Head brightness", floatBinding(\.headBrightness), 0.5...2, "%.0f%%", 100)
            }
            Section("Wallpaper through the symbols") {
                Toggle("Show the desktop wallpaper through the symbols", isOn: boolBinding(\.usePicture))
                Picker("Blending", selection: intBinding(\.pictureBlend)) {
                    Text("Copy").tag(0)
                    Text("OR").tag(1)
                    Text("AND").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Fill the whole screen (crop the edges)", isOn: boolBinding(\.pictureCover))
            }
            Section("Colours") {
                ColorPicker("Trail", selection: colorBinding(\.fade), supportsOpacity: false)
                ColorPicker("Stream head", selection: colorBinding(\.fg), supportsOpacity: false)
                ColorPicker("Background", selection: colorBinding(\.bg), supportsOpacity: false)
            }
            Section {
                Button("Reset settings", role: .destructive) { store.reset() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 680)
    }

    // MARK: Rows

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ format: String, _ scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            row(title, String(format: format, value.wrappedValue * scale))
            Slider(value: value, in: range)
        }
    }

    // MARK: Bindings into the config

    private func floatBinding(_ keyPath: WritableKeyPath<RainConfig, Float>) -> Binding<Double> {
        Binding(
            get: { Double(store.config[keyPath: keyPath]) },
            set: { store.config[keyPath: keyPath] = Float($0) })
    }

    private func intBinding(_ keyPath: WritableKeyPath<RainConfig, Int>) -> Binding<Int> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { store.config[keyPath: keyPath] = $0 })
    }

    private func boolBinding(_ keyPath: WritableKeyPath<RainConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { store.config[keyPath: keyPath] = $0 })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<RainConfig, RGBA>) -> Binding<Color> {
        Binding(
            get: { store.config[keyPath: keyPath].color },
            set: { store.config[keyPath: keyPath] = RGBA($0, keepingAlphaOf: store.config[keyPath: keyPath]) })
    }
}
