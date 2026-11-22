import SwiftUI
import PhotosUI
import BAVtrixCore

struct ColorPreset {
    let name: String
    let fg: RGBA
    let fade: RGBA
}

let presets: [ColorPreset] = [
    ColorPreset(name: "Green", fg: RGBA(187, 255, 187), fade: RGBA(0, 128, 0)),
    ColorPreset(name: "Blue", fg: RGBA(190, 225, 255), fade: RGBA(0, 90, 170)),
    ColorPreset(name: "Red", fg: RGBA(255, 205, 205), fade: RGBA(170, 0, 0)),
    ColorPreset(name: "Amber", fg: RGBA(255, 240, 190), fade: RGBA(190, 120, 0)),
    ColorPreset(name: "Violet", fg: RGBA(230, 205, 255), fade: RGBA(110, 0, 170)),
    ColorPreset(name: "White", fg: RGBA(255, 255, 255), fade: RGBA(120, 120, 120)),
]

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showLicenses = false

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings").font(Brand.font(30, .bold)).foregroundColor(Brand.text)
                    Text("BAVtrix · digital rain").font(Brand.font(15)).foregroundColor(Brand.text2)

                    SectionTitle("Rain")
                    NeonCard {
                        slider("Density", value: floatBinding(\.spawnRate), range: 0.05...0.97, format: "%.0f%%", scale: 100)
                        slider("Speed variance", value: floatBinding(\.speedVariance), range: 1...20, format: "%.0f", scale: 1)
                        slider("Step time, ms", value: floatBinding(\.refreshMs), range: 10...300, format: "%.0f", scale: 1)
                        slider("Symbol size", value: floatBinding(\.glyphSize), range: 5...30, format: "%.0f pt", scale: 1)
                        slider("Special text", value: floatBinding(\.specialProbability), range: 0...1, format: "%.0f%%", scale: 100)
                    }

                    SectionTitle("Trail")
                    NeonCard {
                        stepper("Min. trail length", value: intBinding(\.trailMin), range: 2...200)
                        stepper("Max. length (0 = auto)", value: intBinding(\.trailMax), range: 0...300)
                    }

                    SectionTitle("Flicker")
                    NeonCard {
                        slider("Symbols in the trail", value: floatBinding(\.flicker), range: 0...1, format: "%.0f%%", scale: 100)
                        slider("Stream head", value: floatBinding(\.headFlicker), range: 0...1, format: "%.0f%%", scale: 100)
                        slider("Head brightness", value: floatBinding(\.headBrightness), range: 0.5...2, format: "%.0f%%", scale: 100)
                    }

                    SectionTitle("Picture through the symbols")
                    NeonCard {
                        note("The chosen picture shows through the rain symbols; black stays free of rain.")
                        Toggle(isOn: boolBinding(\.usePicture)) { label("Show the picture") }
                            .tint(Brand.green)
                        label("Blending")
                        HStack(spacing: 8) {
                            BrandChip(label: "Copy", selected: store.config.pictureBlend == 0) { store.config.pictureBlend = 0 }
                            BrandChip(label: "OR", selected: store.config.pictureBlend == 1) { store.config.pictureBlend = 1 }
                            BrandChip(label: "AND", selected: store.config.pictureBlend == 2) { store.config.pictureBlend = 2 }
                        }
                        .padding(.vertical, 6)
                        note("Copy: the symbols show the picture itself. OR: the trail colour is added to the picture. AND: the picture is tinted with the trail colour.")
                        Toggle(isOn: boolBinding(\.pictureCover)) { label("Fill the whole screen (crop)") }
                            .tint(Brand.green)
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text("Choose picture").glassPill()
                            }
                            Button("Remove") {
                                PictureStore.delete()
                                store.config.usePicture = false
                                store.config.pictureVersion += 1
                            }
                            .buttonStyle(PillButtonStyle(glow: .soft))
                        }
                        .padding(.vertical, 10)
                    }

                    SectionTitle("Colour")
                    NeonCard {
                        HStack(spacing: 8) { ForEach(0..<3, id: \.self) { presetChip($0) } }
                        HStack(spacing: 8) { ForEach(3..<6, id: \.self) { presetChip($0) } }
                        ColorPicker(selection: colorBinding(\.fade), supportsOpacity: false) { label("Custom trail colour") }
                        ColorPicker(selection: colorBinding(\.fg), supportsOpacity: false) { label("Custom head colour") }
                        ColorPicker(selection: colorBinding(\.bg), supportsOpacity: false) { label("Background") }
                    }

                    HStack(spacing: 14) {
                        Button("Reset") { store.reset() }
                            .buttonStyle(PillButtonStyle(color: Brand.red))
                        Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                            .buttonStyle(PillButtonStyle())
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 4)

                    Text("BAVtrix 1.0 · © 2026 MIV ekonomi d.o.o.")
                        .font(Brand.font(12)).foregroundColor(Brand.text2)
                        .padding(.top, 10)

                    Button("Licenses") { showLicenses = true }
                        .buttonStyle(PillButtonStyle(glow: .soft))
                        .padding(.top, 4)

                    // Opens the policy in the browser (no web view inside the app).
                    Link(destination: URL(string: "https://barkvestandevelopment.party/bavtrix/apple/privacy")!) {
                        Text("Privacy Policy")
                            .font(Brand.font(15))
                            .foregroundColor(Brand.green)
                            .underline()
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLicenses) { LicensesView() }
        .onChange(of: pickerItem) { item in
            guard let item = item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   PictureStore.save(image) {
                    store.config.usePicture = true
                    store.config.pictureVersion += 1
                }
                pickerItem = nil
            }
        }
    }

    // MARK: Presets

    private func presetChip(_ index: Int) -> some View {
        let p = presets[index]
        return BrandChip(label: p.name, selected: isSelected(p)) {
            store.config.fg = p.fg
            store.config.fade = p.fade
        }
    }

    private func isSelected(_ p: ColorPreset) -> Bool {
        let f = store.config.fade, g = store.config.fg
        return f.r == p.fade.r && f.g == p.fade.g && f.b == p.fade.b
            && g.r == p.fg.r && g.g == p.fg.g && g.b == p.fg.b
    }

    // MARK: Row builders

    private func label(_ text: String) -> some View {
        Text(text).font(Brand.font(16)).foregroundColor(Brand.text)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Brand.font(13)).foregroundColor(Brand.text2)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        format: String, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale))
                    .font(Brand.font(16)).foregroundColor(Brand.green)
            }
            Slider(value: value, in: range).tint(Brand.green)
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                label(title)
                Spacer()
                Text("\(value.wrappedValue)").font(Brand.font(16)).foregroundColor(Brand.green)
            }
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
            set: { newValue in
                store.config[keyPath: keyPath] = newValue
                // Switching the picture on or off makes renderers re-read it.
                if keyPath == \RainConfig.usePicture { store.config.pictureVersion += 1 }
            })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<RainConfig, RGBA>) -> Binding<Color> {
        Binding(
            get: { store.config[keyPath: keyPath].color },
            set: { store.config[keyPath: keyPath] = RGBA($0, keepingAlphaOf: store.config[keyPath: keyPath]) })
    }
}
