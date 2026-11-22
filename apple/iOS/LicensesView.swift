import SwiftUI

/// The "Licenses" screen: licence texts of the third-party components, bundled with the app as
/// THIRD_PARTY_NOTICES.txt (the same file as in the repository's legal folder).
struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private let text: String = {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return "THIRD_PARTY_NOTICES.txt is missing from the app bundle."
    }()

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
