import SwiftUI
import BAVtrixCore

final class SaverConfigModel: ObservableObject {
    @Published var config: RainConfig

    init() {
        config = SaverSettings.load(isPreview: false)
    }
}

/// The small settings sheet shown by "Screen Saver Options…" in System Settings.
struct SaverConfigView: View {
    @ObservedObject var model: SaverConfigModel
    var onClose: (_ save: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BAVtrix").font(.headline)

            slider("Плотность", floatBinding(\.spawnRate), 0.05...0.97, "%.0f%%", 100)
            slider("Разброс скоростей", floatBinding(\.speedVariance), 1...20, "%.0f", 1)
            slider("Размер символов", floatBinding(\.glyphSize), 5...30, "%.0f pt", 1)
            slider("Мерцание символов", floatBinding(\.flicker), 0...1, "%.0f%%", 100)

            Toggle("Обои рабочего стола сквозь символы", isOn: Binding(
                get: { model.config.usePicture },
                set: { model.config.usePicture = $0 }))
            Picker("Смешивание", selection: Binding(
                get: { model.config.pictureBlend },
                set: { model.config.pictureBlend = $0 })) {
                Text("Copy").tag(0)
                Text("OR").tag(1)
                Text("AND").tag(2)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Сбросить") {
                    var fresh = RainConfig()
                    fresh.usePicture = true
                    model.config = fresh
                }
                Spacer()
                Button("Отмена") { onClose(false) }
                Button("OK") { onClose(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ format: String, _ scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func floatBinding(_ keyPath: WritableKeyPath<RainConfig, Float>) -> Binding<Double> {
        Binding(
            get: { Double(model.config[keyPath: keyPath]) },
            set: { model.config[keyPath: keyPath] = Float($0) })
    }
}
