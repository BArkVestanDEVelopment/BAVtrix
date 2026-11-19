import SwiftUI
import CoreText

/// BAVSHIELD brand, taken from the website: Tektur font, dark glass plates with a hairline border,
/// the brand green #39FF88 and the outward `box-shadow` glow on pills.
enum Brand {
    static let green = Color(red: 0x39 / 255, green: 0xFF / 255, blue: 0x88 / 255)
    static let red = Color(red: 1, green: 0x39 / 255, blue: 0x39 / 255)
    static let bg = Color(red: 0x0A / 255, green: 0x0D / 255, blue: 0x0B / 255)
    static let glass = Color(red: 0x1F / 255, green: 0x22 / 255, blue: 0x27 / 255)
    static let glassBorder = Color.white.opacity(0.11)
    static let text = Color(red: 0xF5 / 255, green: 0xF6 / 255, blue: 0xF7 / 255)
    static let text2 = Color(red: 0xF5 / 255, green: 0xF6 / 255, blue: 0xF7 / 255).opacity(0.66)

    enum Weight: Hashable { case regular, medium, semibold, bold }

    /// PostScript names of the bundled Tektur files, read from the files themselves.
    private static let names: [Weight: String] = {
        var result: [Weight: String] = [:]
        let files: [(Weight, String)] = [(.regular, "tektur_regular"), (.medium, "tektur_medium"),
                                         (.semibold, "tektur_semibold"), (.bold, "tektur_bold")]
        for (weight, file) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
                result[weight] = name
            }
        }
        return result
    }()

    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        if let name = names[weight] { return .custom(name, size: size) }
        return .system(size: size)
    }
}

/// CSS-like glow layers: blur radius in px and opacity (`0 0 8px .9, 0 0 20px .5, 0 0 40px .2`).
struct GlowLayers {
    let layers: [(CGFloat, Double)]
    static let strong = GlowLayers(layers: [(8, 0.9), (20, 0.5), (40, 0.2)])
    static let soft = GlowLayers(layers: [(4, 0.5), (10, 0.25), (18, 0.1)])
    static let none = GlowLayers(layers: [])
}

extension View {
    /// `box-shadow: 0 0 Bpx color` layers (CSS blur B is a Gaussian of sigma B/2).
    func siteGlow(_ color: Color = Brand.green, _ glow: GlowLayers = .strong) -> some View {
        var view = AnyView(self)
        for (blur, alpha) in glow.layers {
            view = AnyView(view.shadow(color: color.opacity(alpha), radius: blur / 2, x: 0, y: 0))
        }
        return view
    }
}

/// A "plate": neutral dark glass with a hairline border (no glow, like the website cards).
struct NeonCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.glass.opacity(0.86), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.glassBorder, lineWidth: 1))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Brand.font(12, .semibold))
            .tracking(2)
            .foregroundColor(Brand.green)
            .padding(.leading, 4)
            .padding(.top, 14)
    }
}

/// `glass-pill` look for any label: opaque glass, hairline border, outward glow.
extension View {
    func glassPill(_ color: Color = Brand.green, glow: GlowLayers = .strong) -> some View {
        self
            .font(Brand.font(16, .medium))
            .foregroundColor(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(Brand.glass))
            .overlay(Capsule().stroke(Brand.glassBorder, lineWidth: 1))
            .siteGlow(color, glow)
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = Brand.green
    var glow: GlowLayers = .strong
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassPill(color, glow: glow)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Selectable chip; the selected one is green with a soft glow.
struct BrandChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Brand.font(15, .medium))
                .foregroundColor(selected ? Brand.green : Brand.text2)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Brand.glass))
                .overlay(Capsule().stroke(selected ? Brand.green.opacity(0.7) : Brand.glassBorder, lineWidth: 1))
                .siteGlow(Brand.green, selected ? .soft : .none)
        }
        .buttonStyle(.plain)
    }
}
