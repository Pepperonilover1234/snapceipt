import SwiftUI
import UIKit

/// Snapceipt's look: a TradingView-style chart layout dressed like Teenage Engineering hardware.
/// True black in dark mode, warm device grey in light, one signal orange, monospaced uppercase
/// labels, key-like buttons with an LED dot, a dot grid behind the chart and screws in the corners.
/// Red and green only ever mean spending going up and down.
///
/// Every text colour reaches at least 4.5:1 on paper and surface in light and dark (WCAG AA), chart
/// marks at least 3:1. The bright category fills only ever carry `onBright` (navy) text.
/// Increase Contrast swaps in stronger greys.
enum Theme {
    /// The chosen theme's colours. Read fresh each time, so a new theme shows as soon as the views redraw.
    static var palette: Palette { Paint.current.palette }

    /// Page background.
    static var paper: Color { palette.paper }
    /// Panels, cards and rows.
    static var surface: Color { palette.surface }
    /// Hairlines: card borders, separators, grid lines.
    static var line: Color { palette.line }
    /// Text and chart marks.
    static var ink: Color { palette.ink }
    /// Secondary text.
    static var muted: Color { palette.muted }
    /// Secondary chart marks (volume, previous period). Not for text.
    static var quiet: Color { palette.quiet }
    /// The one accent: selections, links, the main buttons.
    static var accent: Color { palette.accent }
    /// Accent for text and thin marks (4.5:1 on both backgrounds).
    static var accentText: Color { palette.accentText }
    /// Text and symbols on the accent.
    static var onAccent: Color { palette.onAccent }
    /// Text and symbols on a bright category fill.
    static var onBright: Color { palette.onBright }
    /// The moving-average line, apart from the accent.
    static var indicator: Color { palette.indicator }

    // Key colours, for the chart-type keys. They carry dark labels.
    static var keyBlue: Color { palette.keyBlue }
    static var keyGreen: Color { palette.keyGreen }
    static var keyGrey: Color { palette.keyGrey }
    static var keyOrange: Color { accent }

    // Category fills: bright, the same in light and dark, never used for text.
    static var yellow: Color { palette.brights[0] }
    static var orange: Color { palette.brights[1] }
    static var pink: Color { palette.brights[2] }
    static var lime: Color { palette.brights[3] }
    static var sky: Color { palette.brights[4] }
    static var purple: Color { palette.brights[5] }
    static var mint: Color { palette.brights[6] }
    static var coral: Color { palette.brights[7] }
    static var stone: Color { palette.brights[8] }
    static var cyan: Color { palette.brights[9] }
    static var peach: Color { palette.brights[10] }

    /// Spending went up, darkened where it's small text in light mode.
    static var up: Color { palette.up }
    /// Spending went down, or money saved.
    static var down: Color { palette.down }
    /// Candles and bars, at full chart strength.
    static var candleUp: Color { palette.candleUp }
    static var candleDown: Color { palette.candleDown }
    /// Extra chart colours, dark enough in light mode to read against white.
    static var chartBlue: Color { palette.chartBlue }
    static var chartOrange: Color { palette.chartOrange }

    /// Screws, dot grids and LEDs: the hardware details only some themes wear.
    static var hardware: Bool { Skin.current.hardware }

    /// Border width.
    static var rule: CGFloat { Skin.current.rule }
    /// Corner radius of keys, segments and buttons.
    static var controlRadius: CGFloat { Skin.current.controlRadius }
    /// Corner radius of panels.
    static var radius: CGFloat { Skin.current.radius }
    /// Panels sit flat, except in styles that float them.
    static var shadow: CGFloat { Skin.current.shadowRadius }
    /// A label as the current style writes it.
    static func cased(_ text: String) -> String { Skin.current.cased(text) }
    static var tracking: CGFloat { Skin.current.tracking }

    /// Panel and section titles: small monospaced lower case, like labels printed on a device.
    static var label: Font { .system(.caption, design: Skin.current.design, weight: .semibold) }
    /// Badges and chart axes.
    static var smallLabel: Font { .system(.caption2, design: Skin.current.design, weight: .medium) }
    /// The big number on a screen.
    static var hero: Font { .system(.largeTitle, design: Skin.current.figureDesign, weight: .medium).monospacedDigit() }
    /// Money and other figures, in the device's monospaced type.
    static func figure(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: Skin.current.figureDesign, weight: .medium).monospacedDigit()
    }

    /// Plain, firm navigation titles. Set once at launch.
    static func styleNavigationBars() {
        func font(_ size: CGFloat, _ weight: UIFont.Weight, scaledAs style: UIFont.TextStyle) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight))
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: font(32, .bold, scaledAs: .largeTitle)]
        UINavigationBar.appearance().titleTextAttributes = [.font: font(17, .semibold, scaledAs: .headline)]
    }
}

extension EnvironmentValues {
    /// The current tab's bright colour: card titles, the chosen segment, main buttons, highlighted totals.
    @Entry var pageAccent: Color = Theme.accent
}

extension Color {
    /// A colour that follows light and dark mode, with optional stronger values for Increase Contrast.
    init(light: UInt32, dark: UInt32, lightHighContrast: UInt32? = nil, darkHighContrast: UInt32? = nil) {
        self.init(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark
                ? (high ? darkHighContrast ?? dark : dark)
                : (high ? lightHighContrast ?? light : light)
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    /// The same colour in light and dark mode.
    init(hex: UInt32) {
        self.init(light: hex, dark: hex)
    }
}

/// Light, dark, or whatever the device is set to. Stored under "appearance",
/// so `-appearance dark` works as a launch argument too.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Match device"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    private var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Set on the windows themselves so sheets follow, and so "Match device" really goes back
    /// to the device setting (SwiftUI's preferredColorScheme doesn't always undo itself).
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

/// A card's colour: a bright fill for its title tag and a soft tint of it for the body.
/// Every text and chart colour in `Theme` passes on every tint, in light and dark.
enum CardColor: CaseIterable {
    case yellow, orange, pink, lime, sky, purple, mint, coral, cyan, peach

    var bright: Color {
        switch self {
        case .yellow: Theme.yellow
        case .orange: Theme.orange
        case .pink: Theme.pink
        case .lime: Theme.lime
        case .sky: Theme.sky
        case .purple: Theme.purple
        case .mint: Theme.mint
        case .coral: Theme.coral
        case .cyan: Theme.cyan
        case .peach: Theme.peach
        }
    }

    /// Panels stay flat; the bright colour marks the title instead.
    var tint: Color { Theme.surface }

    var softTint: Color {
        switch self {
        case .yellow: Color(light: 0xFFF1BF, dark: 0x3A3214)
        case .orange: Color(light: 0xFFE2D1, dark: 0x3D2417)
        case .pink: Color(light: 0xFFE3F0, dark: 0x3A1F2F)
        case .lime: Color(light: 0xEDFBCB, dark: 0x26351A)
        case .sky: Color(light: 0xDFEBFF, dark: 0x1A2A46)
        case .purple: Color(light: 0xECE5FF, dark: 0x2A2349)
        case .mint: Color(light: 0xD5F7EC, dark: 0x163A33)
        case .coral: Color(light: 0xFFE1E1, dark: 0x3D1E23)
        case .cyan: Color(light: 0xD7F6FC, dark: 0x143A42)
        case .peach: Color(light: 0xFFEBDD, dark: 0x3D2A1C)
        }
    }
}
