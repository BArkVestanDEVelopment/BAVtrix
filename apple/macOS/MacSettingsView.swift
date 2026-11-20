import SwiftUI
import BAVtrixCore

struct MacSettingsView: View {
    @ObservedObject var store: MacSettings

    var body: some View {
        Form {
            Section("Рабочий стол") {
                Toggle("Скрывать значки рабочего стола", isOn: $store.coverIcons)
                Toggle("Запускать при входе", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }))
            }
            Section("Дождь") {
                slider("Плотность", floatBinding(\.spawnRate), 0.05...0.97, "%.0f%%", 100)
                slider("Разброс скоростей", floatBinding(\.speedVariance), 1...20, "%.0f", 1)
                slider("Время шага, мс", floatBinding(\.refreshMs), 10...300, "%.0f", 1)
                slider("Размер символов", floatBinding(\.glyphSize), 5...30, "%.0f pt", 1)
                slider("Спецстрока, %", floatBinding(\.specialProbability), 0...1, "%.0f%%", 100)
            }
            Section("Шлейф") {
                Stepper(value: intBinding(\.trailMin), in: 2...200) {
                    row("Мин. длина шлейфа", "\(store.config.trailMin)")
                }
                Stepper(value: intBinding(\.trailMax), in: 0...300) {
                    row("Макс. длина (0 = авто)", "\(store.config.trailMax)")
                }
            }
            Section("Мерцание") {
                slider("Символы в шлейфе", floatBinding(\.flicker), 0...1, "%.0f%%", 100)
                slider("Голова потока", floatBinding(\.headFlicker), 0...1, "%.0f%%", 100)
                slider("Яркость головы", floatBinding(\.headBrightness), 0.5...2, "%.0f%%", 100)
            }
            Section("Обои сквозь символы") {
                Toggle("Показывать обои рабочего стола сквозь символы", isOn: boolBinding(\.usePicture))
                Picker("Смешивание", selection: intBinding(\.pictureBlend)) {
                    Text("Copy").tag(0)
                    Text("OR").tag(1)
                    Text("AND").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Растянуть на весь экран (обрезать края)", isOn: boolBinding(\.pictureCover))
            }
            Section("Цвета") {
                ColorPicker("Шлейф", selection: colorBinding(\.fade), supportsOpacity: false)
                ColorPicker("Голова потока", selection: colorBinding(\.fg), supportsOpacity: false)
                ColorPicker("Фон", selection: colorBinding(\.bg), supportsOpacity: false)
            }
            Section {
                Button("Сбросить настройки", role: .destructive) { store.reset() }
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
