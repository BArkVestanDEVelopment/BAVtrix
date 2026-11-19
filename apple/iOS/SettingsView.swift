import SwiftUI
import BAVtrixCore

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Дождь")) {
                    slider("Плотность", value: floatBinding(\.spawnRate), range: 0.05...0.97, format: "%.0f%%", scale: 100)
                    slider("Разброс скоростей", value: floatBinding(\.speedVariance), range: 1...20, format: "%.0f", scale: 1)
                    slider("Время шага, мс", value: floatBinding(\.refreshMs), range: 10...300, format: "%.0f", scale: 1)
                    slider("Размер символов", value: floatBinding(\.glyphSize), range: 8...30, format: "%.0f pt", scale: 1)
                    slider("Спецстрока, %", value: floatBinding(\.specialProbability), range: 0...1, format: "%.0f%%", scale: 100)
                }
                Section(header: Text("Шлейф")) {
                    stepper("Мин. длина шлейфа", value: intBinding(\.trailMin), range: 2...200)
                    stepper("Макс. длина (0 = авто)", value: intBinding(\.trailMax), range: 0...300)
                }
                Section(header: Text("Мерцание")) {
                    slider("Символы в шлейфе", value: floatBinding(\.flicker), range: 0...1, format: "%.0f%%", scale: 100)
                    slider("Голова потока", value: floatBinding(\.headFlicker), range: 0...1, format: "%.0f%%", scale: 100)
                    slider("Яркость головы", value: floatBinding(\.headBrightness), range: 0.5...2, format: "%.0f%%", scale: 100)
                }
                Section(header: Text("Цвета")) {
                    ColorPicker("Шлейф", selection: colorBinding(\.fade), supportsOpacity: false)
                    ColorPicker("Голова потока", selection: colorBinding(\.fg), supportsOpacity: false)
                    ColorPicker("Фон", selection: colorBinding(\.bg), supportsOpacity: false)
                }
                Section {
                    Button("Сбросить настройки", role: .destructive) { store.reset() }
                }
                Section(footer: Text("BAVtrix 1.0 · BArkVestan_Development · GPL-2.0")) { EmptyView() }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Row builders

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        format: String, scale: Double) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)").foregroundColor(.secondary)
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

    private func colorBinding(_ keyPath: WritableKeyPath<RainConfig, RGBA>) -> Binding<Color> {
        Binding(
            get: { store.config[keyPath: keyPath].color },
            set: { store.config[keyPath: keyPath] = RGBA($0, keepingAlphaOf: store.config[keyPath: keyPath]) })
    }
}
