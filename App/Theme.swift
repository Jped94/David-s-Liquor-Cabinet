import CoreText
import SwiftUI

/// The "paper menu" look: cream paper, ink, oxblood accents,
/// Playfair Display for titles and EB Garamond for everything else.
enum Theme {
    static let paper = Color(hex: 0xF4EDE1)
    static let card = Color(hex: 0xFBF7F0)
    static let ink = Color(hex: 0x1D1A16)
    static let muted = Color(hex: 0x6B6256)
    static let accent = Color(hex: 0x7A2E2A)
    static let rule = Color(hex: 0xCFC4B2)
    static let leader = Color(hex: 0x9C9182)

    enum Weight { case regular, medium, semibold }

    /// Playfair Display, for page titles and headings.
    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "PlayfairDisplayRoman-Bold" : "PlayfairDisplayRoman-SemiBold", size: size)
    }

    /// EB Garamond, for entries and body text.
    static func body(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .regular: .custom("EBGaramond-Regular", size: size)
        case .medium: .custom("EBGaramond-Medium", size: size)
        case .semibold: .custom("EBGaramond-SemiBold", size: size)
        }
    }

    static func italic(_ size: CGFloat) -> Font {
        .custom("EBGaramondItalic-Italic", size: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Registers the fonts bundled in App/Fonts (SIL Open Font License; the
/// licence texts ship alongside them).
enum FontRegistrar {
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
              !urls.isEmpty
        else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

// MARK: - Shared pieces

/// Small capitals label, e.g. "OPEN & READY".
struct CapsLabel: View {
    let text: String
    var color: Color = Theme.accent
    var size: CGFloat = 13

    init(_ text: String, color: Color = Theme.accent, size: CGFloat = 13) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(size, .semibold))
            .tracking(size * 0.22)
            .foregroundStyle(color)
    }
}

/// The dotted line between a name and its value on a menu.
struct DottedLeader: View {
    var body: some View {
        HorizontalLine()
            .stroke(Theme.leader, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .frame(height: 1)
            .frame(minWidth: 12)
            .offset(y: -5)
    }
}

struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Two thin rules, like the top and bottom of a printed masthead.
struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(Theme.ink)
    }
}

/// "ISLAY ───────────" section heading.
struct SectionHeading: View {
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            CapsLabel(title, size: 14)
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Number formatting for ABV and ages.
enum Format {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func abv(_ value: Double) -> String { number(value) + "%" }

    static func age(_ years: Double) -> String { number(years) + (years == 1 ? " year" : " years") }
}
