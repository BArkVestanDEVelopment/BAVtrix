import SwiftUI
import PhotosUI
import BAVtrixCore

private struct ColorPreset {
    let name: String
    let fg: RGBA
    let fade: RGBA
}

private let presets: [ColorPreset] = [
    ColorPreset(name: "Зелёный", fg: RGBA(187, 255, 187), fade: RGBA(0, 128, 0)),
    ColorPreset(name: "Синий", fg: RGBA(190, 225, 255), fade: RGBA(0, 90, 170)),
    ColorPreset(name: "Красный", fg: RGBA(255, 205, 205), fade: RGBA(170, 0, 0)),
    ColorPreset(name: "Янтарный", fg: RGBA(255, 240, 190), fade: RGBA(190, 120, 0)),
    ColorPreset(name: "Фиолетовый", fg: RGBA(230, 205, 255), fade: RGBA(110, 0, 170)),
    ColorPreset(name: "Белый", fg: RGBA(255, 255, 255), fade: RGBA(120, 120, 120)),
]

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Настройки").font(Brand.font(30, .bold)).foregroundColor(Brand.text)
                    Text("BAVtrix · матричный дождь").font(Brand.font(15)).foregroundColor(Brand.text2)

                    SectionTitle("Дождь")
                    NeonCard {
                        slider("Плотность", value: floatBinding(\.spawnRate), range: 0.05...0.97, format: "%.0f%%", scale: 100)
                        slider("Разброс скоростей", value: floatBinding(\.speedVariance), range: 1...20, format: "%.0f", scale: 1)
                        slider("Время шага, мс", value: floatBinding(\.refreshMs), range: 10...300, format: "%.0f", scale: 1)
                        slider("Размер символов", value: floatBinding(\.glyphSize), range: 5...30, format: "%.0f pt", scale: 1)
                        slider("Спецстрока", value: floatBinding(\.specialProbability), range: 0...1, format: "%.0f%%", scale: 100)
                    }

                    SectionTitle("Шлейф")
                    NeonCard {
                        stepper("Мин. длина шлейфа", value: intBinding(\.trailMin), range: 2...200)
                        stepper("Макс. длина (0 = авто)", value: intBinding(\.trailMax), range: 0...300)
                    }

                    SectionTitle("Мерцание")
                    NeonCard {
                        slider("Символы в шлейфе", value: floatBinding(\.flicker), range: 0...1, format: "%.0f%%", scale: 100)
                        slider("Голова потока", value: floatBinding(\.headFlicker), range: 0...1, format: "%.0f%%", scale: 100)
                        slider("Яркость головы", value: floatBinding(\.headBrightness), range: 0.5...2, format: "%.0f%%", scale: 100)
                    }

                    SectionTitle("Картинка сквозь символы")
                    NeonCard {
                        note("Выбранная картинка проступает через символы дождя, чёрное остаётся без дождя.")
                        Toggle(isOn: boolBinding(\.usePicture)) { label("Показывать картинку") }
                            .tint(Brand.green)
                        label("Смешивание")
                        HStack(spacing: 8) {
                            BrandChip(label: "Copy", selected: store.config.pictureBlend == 0) { store.config.pictureBlend = 0 }
                            BrandChip(label: "OR", selected: store.config.pictureBlend == 1) { store.config.pictureBlend = 1 }
                            BrandChip(label: "AND", selected: store.config.pictureBlend == 2) { store.config.pictureBlend = 2 }
                        }
                        .padding(.vertical, 6)
                        note("Copy: символы показывают саму картинку. OR: к картинке добавляется цвет шлейфа. AND: картинка окрашивается цветом шлейфа.")
                        Toggle(isOn: boolBinding(\.pictureCover)) { label("Заполнить весь экран (обрезать)") }
                            .tint(Brand.green)
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text("Выбрать картинку").glassPill()
                            }
                            Button("Убрать") {
                                PictureStore.delete()
                                store.config.usePicture = false
                                store.config.pictureVersion += 1
                            }
                            .buttonStyle(PillButtonStyle(glow: .soft))
                        }
                        .padding(.vertical, 10)
                    }

                    SectionTitle("Цвет")
                    NeonCard {
                        HStack(spacing: 8) { ForEach(0..<3, id: \.self) { presetChip($0) } }
                        HStack(spacing: 8) { ForEach(3..<6, id: \.self) { presetChip($0) } }
                        ColorPicker(selection: colorBinding(\.fade), supportsOpacity: false) { label("Свой цвет шлейфа") }
                        ColorPicker(selection: colorBinding(\.fg), supportsOpacity: false) { label("Свой цвет головы") }
                        ColorPicker(selection: colorBinding(\.bg), supportsOpacity: false) { label("Фон") }
                    }

                    HStack(spacing: 14) {
                        Button("Сбросить") { store.reset() }
                            .buttonStyle(PillButtonStyle(color: Brand.red))
                        Button { dismiss() } label: { Text("Готово").frame(maxWidth: .infinity) }
                            .buttonStyle(PillButtonStyle())
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 4)

                    Text("BAVtrix 1.0 · BArkVestan_Development · GPL-2.0")
                        .font(Brand.font(12)).foregroundColor(Brand.text2)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
        .preferredColorScheme(.dark)
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
