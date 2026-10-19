import SwiftUI

/// The app's colours, chosen apart from its style. Stored under "colour" (`-colour gruv`).
/// Every palette has a light and a dark version.
enum Paint: String, CaseIterable, Identifiable {
    /// True black, warm grey and signal orange.
    case console
    /// TradingView's white, navy and blue.
    case classic
    /// Gruvbox's warm browns, creams and orange.
    case gruv
    /// Blush pink, plum and pastels.
    case kawaii

    var id: String { rawValue }

    static var current: Paint {
        UserDefaults.standard.string(forKey: "colour").flatMap(Paint.init(rawValue:)) ?? .console
    }

    var name: String { rawValue }

    var blurb: String {
        switch self {
        case .console: "True black, warm grey, signal orange"
        case .classic: "White and navy with a blue accent"
        case .gruv: "Warm browns, creams and orange"
        case .kawaii: "Blush pink, plum and pastels"
        }
    }

    var palette: Palette {
        switch self {
        case .console: .console
        case .classic: .classic
        case .gruv: .gruv
        case .kawaii: .kawaii
        }
    }

    /// Paper, surface, accent and ink, for the picker.
    var swatch: [Color] { [palette.paper, palette.surface, palette.accent, palette.ink] }
}

/// The app's style: type, spacing, corners, borders, how labels are written and how a chosen
/// control shows it's chosen. Independent of the colours. Stored under "skin" (`-skin kawaii`).
enum Skin: String, CaseIterable, Identifiable {
    /// Teenage Engineering hardware: mono lower-case labels, LEDs, screws, dot grid, dot-matrix readout.
    case console
    /// TradingView: plain sans-serif in Title Case, tight spacing, sharp corners, filled selections.
    case classic
    /// A Gruvbox terminal: mono UPPER CASE, square corners, thick borders, reverse-video selections.
    case gruv
    /// Soft and bubbly: rounded type, pill buttons, big round panels with no borders, airy spacing.
    case kawaii

    var id: String { rawValue }

    static var current: Skin {
        UserDefaults.standard.string(forKey: "skin").flatMap(Skin.init(rawValue:)) ?? .console
    }

    var name: String { rawValue }

    var symbol: String {
        switch self {
        case .console: "dial.medium"
        case .classic: "chart.xyaxis.line"
        case .gruv: "terminal"
        case .kawaii: "heart"
        }
    }

    var blurb: String {
        switch self {
        case .console: "Hardware synth: mono labels, LEDs, screws, dot-matrix screen"
        case .classic: "Trading terminal: plain type, tight and sharp"
        case .gruv: "Text terminal: UPPER CASE mono, square boxes, thick lines"
        case .kawaii: "Soft and bubbly: round type, pills, airy spacing"
        }
    }

    /// The Overview title.
    var appTitle: String {
        switch self {
        case .console, .classic: "Snapceipt"
        case .gruv: "~/snapceipt"
        case .kawaii: "snapceipt ♡"
        }
    }

    /// Labels and body text.
    var design: Font.Design {
        switch self {
        case .console, .gruv: .monospaced
        case .classic: .default
        case .kawaii: .rounded
        }
    }

    /// Money and figures; digits are always even-width.
    var figureDesign: Font.Design { design }

    /// Panels.
    var radius: CGFloat {
        switch self {
        case .console: 10
        case .classic: 4
        case .gruv: 0
        case .kawaii: 22
        }
    }

    /// Keys, segments and buttons.
    var controlRadius: CGFloat {
        switch self {
        case .console: 6
        case .classic: 3
        case .gruv: 0
        case .kawaii: 999
        }
    }

    /// Border width of panels and controls. Kawaii has none and floats on a soft shadow instead.
    var rule: CGFloat {
        switch self {
        case .console, .classic: 1
        case .gruv: 2
        case .kawaii: 0
        }
    }

    var shadowRadius: CGFloat { self == .kawaii ? 10 : 0 }

    /// Space between the blocks of a page.
    var pageSpacing: CGFloat {
        switch self {
        case .console: 14
        case .classic: 10
        case .gruv: 12
        case .kawaii: 20
        }
    }

    /// Padding inside a panel.
    var panelPadding: CGFloat {
        switch self {
        case .console: 14
        case .classic: 12
        case .gruv: 12
        case .kawaii: 20
        }
    }

    /// Letter spacing of labels.
    var tracking: CGFloat {
        switch self {
        case .console: 0.8
        case .classic: 0
        case .gruv: 1.6
        case .kawaii: 0.3
        }
    }

    /// Screws, dot grid, LEDs and the dot-matrix readout.
    var hardware: Bool { self == .console }

    /// A label as this style writes it: "range", "Range", "RANGE".
    func cased(_ text: String) -> String {
        switch self {
        case .console, .kawaii: text.lowercased()
        case .classic: text.prefix(1).uppercased() + text.dropFirst()
        case .gruv: text.uppercased()
        }
    }
}

/// One theme's colours. Brights are, in order: yellow, orange, pink, lime, sky, purple, mint,
/// coral, stone, cyan, peach. They're category fills and only ever carry `onBright`.
struct Palette {
    let paper, surface, line, ink, muted, quiet: Color
    let accent, accentText, onAccent, onBright, indicator: Color
    let keyBlue, keyGreen, keyGrey: Color
    let up, down, candleUp, candleDown, chartBlue, chartOrange: Color
    let brights: [Color]

    static let console = Palette(
        paper: Color(light: 0xEAEAE6, dark: 0x000000),
        surface: Color(light: 0xF7F7F5, dark: 0x0E0E0E),
        line: Color(light: 0xD4D4CF, dark: 0x2A2A2A, lightHighContrast: 0x8A8A84, darkHighContrast: 0x5C5C5C),
        ink: Color(light: 0x111111, dark: 0xF2F2F2, lightHighContrast: 0x000000, darkHighContrast: 0xFFFFFF),
        muted: Color(light: 0x5A5A55, dark: 0x8C8C8C, lightHighContrast: 0x2B2B28, darkHighContrast: 0xCFCFCA),
        quiet: Color(light: 0xB3B3AD, dark: 0x4A4A4A, lightHighContrast: 0x7A7A75, darkHighContrast: 0x7A7A75),
        accent: Color(hex: 0xFF5A00),
        accentText: Color(light: 0xB33F00, dark: 0xFF7A33),
        onAccent: Color(hex: 0x000000),
        onBright: Color(hex: 0x111111),
        indicator: Color(light: 0x1F5FD6, dark: 0x5B8BFF),
        keyBlue: Color(hex: 0x2F6BFF), keyGreen: Color(hex: 0x00A86B), keyGrey: Color(hex: 0xB5B5B5),
        up: Color(light: 0xD32F2F, dark: 0xF7525F),
        down: Color(light: 0x00796B, dark: 0x22AB94),
        candleUp: Color(hex: 0xF23645), candleDown: Color(hex: 0x089981),
        chartBlue: Color(light: 0x1A56C4, dark: 0x82AAFF),
        chartOrange: Color(light: 0x9E4200, dark: 0xFF9A4D),
        brights: [0xFFD23F, 0xFF8A4C, 0xFF9EC7, 0xB6F03C, 0x7DB2FF, 0xB9A2FF, 0x5FE3BF, 0xFF6B6B, 0xD9D6CE, 0x4FD8F0, 0xFFC29A].map(Color.init(hex:))
    )

    /// TradingView's own colours: #131722 night, #2962FF blue, its red and green.
    static let classic = Palette(
        paper: Color(light: 0xF0F3FA, dark: 0x0F121A),
        surface: Color(light: 0xFFFFFF, dark: 0x1E222D),
        line: Color(light: 0xE0E3EB, dark: 0x2A2E39, lightHighContrast: 0x8A8E99, darkHighContrast: 0x5D606B),
        ink: Color(light: 0x131722, dark: 0xD1D4DC, lightHighContrast: 0x000000, darkHighContrast: 0xFFFFFF),
        muted: Color(light: 0x5D606B, dark: 0x9598A1, lightHighContrast: 0x2A2E39, darkHighContrast: 0xC8CBD4),
        quiet: Color(light: 0xB2B5BE, dark: 0x434651),
        accent: Color(hex: 0x2962FF),
        accentText: Color(light: 0x1E53E5, dark: 0x6C93FF),
        onAccent: Color(hex: 0xFFFFFF),
        onBright: Color(hex: 0x131722),
        indicator: Color(light: 0xE65100, dark: 0xFF9800),
        keyBlue: Color(hex: 0x5B8CFF), keyGreen: Color(hex: 0x26A69A), keyGrey: Color(hex: 0xB2B5BE),
        up: Color(light: 0xD32F2F, dark: 0xF7525F),
        down: Color(light: 0x00796B, dark: 0x22AB94),
        candleUp: Color(hex: 0xF23645), candleDown: Color(hex: 0x089981),
        chartBlue: Color(light: 0x1E53E5, dark: 0x82AAFF),
        chartOrange: Color(light: 0xB34700, dark: 0xFFA040),
        brights: [0xFFD54F, 0xFFA726, 0xF48FB1, 0xAED581, 0x90CAF9, 0xB39DDB, 0x80CBC4, 0xEF9A9A, 0xD1D4DC, 0x80DEEA, 0xFFCC80].map(Color.init(hex:))
    )

    /// Gruvbox: bg #282828, fg #EBDBB2, orange #FE8019, and its faded light variant.
    static let gruv = Palette(
        paper: Color(light: 0xF2E5BC, dark: 0x1D2021),
        surface: Color(light: 0xFBF1C7, dark: 0x282828),
        line: Color(light: 0xD5C4A1, dark: 0x3C3836, lightHighContrast: 0x928374, darkHighContrast: 0x665C54),
        ink: Color(light: 0x3C3836, dark: 0xEBDBB2, lightHighContrast: 0x1D2021, darkHighContrast: 0xFBF1C7),
        muted: Color(light: 0x665C54, dark: 0xA89984, lightHighContrast: 0x3C3836, darkHighContrast: 0xD5C4A1),
        quiet: Color(light: 0xBDAE93, dark: 0x504945),
        accent: Color(light: 0xD65D0E, dark: 0xFE8019),
        accentText: Color(light: 0xAF3A03, dark: 0xFE8019),
        onAccent: Color(hex: 0x1D2021),
        onBright: Color(hex: 0x282828),
        indicator: Color(light: 0x076678, dark: 0x83A598),
        keyBlue: Color(hex: 0x83A598), keyGreen: Color(hex: 0xB8BB26), keyGrey: Color(hex: 0xA89984),
        up: Color(light: 0x9D0006, dark: 0xFB4934),
        down: Color(light: 0x79740E, dark: 0xB8BB26),
        candleUp: Color(light: 0xCC241D, dark: 0xFB4934), candleDown: Color(light: 0x98971A, dark: 0xB8BB26),
        chartBlue: Color(light: 0x076678, dark: 0x83A598),
        chartOrange: Color(light: 0xAF3A03, dark: 0xFE8019),
        brights: [0xFABD2F, 0xFE8019, 0xE8A0B4, 0xB8BB26, 0x83A598, 0xD3869B, 0x8EC07C, 0xFB4934, 0xBDAE93, 0x83C0B0, 0xFFB878].map(Color.init(hex:))
    )

    /// Candy pink on blush, plum text, and pastel fills.
    static let kawaii = Palette(
        paper: Color(light: 0xFFEAF3, dark: 0x1C0F17),
        surface: Color(light: 0xFFFFFF, dark: 0x2B1823),
        line: Color(light: 0xF6C6DB, dark: 0x4A2A3B, lightHighContrast: 0xC2185B, darkHighContrast: 0x9C5A7A),
        ink: Color(light: 0x3B1E2E, dark: 0xFFE6F1, lightHighContrast: 0x1F0A15, darkHighContrast: 0xFFFFFF),
        muted: Color(light: 0x85485F, dark: 0xD9A3BE, lightHighContrast: 0x5A2A3E, darkHighContrast: 0xF2CFE0),
        quiet: Color(light: 0xF0A8C8, dark: 0x6A3A52),
        accent: Color(light: 0xFF4FA3, dark: 0xFF6EB4),
        accentText: Color(light: 0xC2185B, dark: 0xFF8CC6),
        onAccent: Color(hex: 0x2A0F1D),
        onBright: Color(hex: 0x3B1E2E),
        indicator: Color(light: 0x6A4BD8, dark: 0xB59CFF),
        keyBlue: Color(hex: 0xA9CCFF), keyGreen: Color(hex: 0xA6EBCB), keyGrey: Color(hex: 0xF5C6DA),
        up: Color(light: 0xC2185B, dark: 0xFF6F9C),
        down: Color(light: 0x1B7F70, dark: 0x5FD6BC),
        candleUp: Color(light: 0xE91E63, dark: 0xFF5C8A), candleDown: Color(light: 0x26A69A, dark: 0x5FD6BC),
        chartBlue: Color(light: 0x5A3FC0, dark: 0xB59CFF),
        chartOrange: Color(light: 0xB0306A, dark: 0xFF9ECB),
        brights: [0xFFE7A0, 0xFFC4A3, 0xFFB3D1, 0xD4F5B0, 0xB8D8FF, 0xD9C8FF, 0xB5F0DC, 0xFFB0B8, 0xEADDE3, 0xB0EEF5, 0xFFD9C2].map(Color.init(hex:))
    )
}
