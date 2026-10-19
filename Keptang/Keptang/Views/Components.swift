import AudioToolbox
import SwiftUI

/// A flat panel: fill and a hairline border, like TradingView's widgets.
struct BlockShape: View {
    var fill: Color = Theme.surface
    var radius: CGFloat = Theme.radius
    /// Kept for callers; panels no longer cast shadows.
    var shadow: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(fill)
                .shadow(color: Theme.ink.opacity(Theme.shadow > 0 ? 0.08 : 0), radius: Theme.shadow, y: Theme.shadow / 3)
            if Theme.rule > 0 { shape.strokeBorder(Theme.line, lineWidth: Theme.rule) }
            if radius >= Theme.radius, Theme.hardware { Screws(inset: 6) }
        }
    }
}

/// Four tiny screw heads in the corners of a panel. Decorative.
struct Screws: View {
    var inset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            if w > 80, h > 60 {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Theme.paper)
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        .overlay(Rectangle().fill(Theme.quiet).frame(width: 3, height: 0.8).rotationEffect(.degrees(45)))
                        .frame(width: 5, height: 5)
                        .position(x: i % 2 == 0 ? inset : w - inset, y: i < 2 ? inset : h - inset)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A grid of fine dots, like the printed grid on a synth's faceplate. Decorative.
struct DotGrid: View {
    var spacing: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            guard Theme.hardware else { return }
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(Theme.line))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small round light: lit orange when on, a dark socket when off.
struct LED: View {
    var on: Bool
    var colour: Color = Theme.accent

    var body: some View {
        // Only the hardware style has lights; the others show selection by shape and fill.
        if Theme.hardware { light }
    }

    private var light: some View {
        Circle()
            .fill(on ? colour : Theme.line)
            .frame(width: 5, height: 5)
            .shadow(color: on ? colour.opacity(0.8) : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the view on a `BlockShape`.
    func block(_ fill: Color = Theme.surface, radius: CGFloat = Theme.radius, shadow: CGFloat = Theme.shadow) -> some View {
        background { BlockShape(fill: fill, radius: radius, shadow: shadow) }
    }
}

/// A panel or section title: a short colour bar and the title, like a TradingView widget header.
struct TitleChip: View {
    let text: String
    /// The bar's colour; the accent when nil.
    var tint: Color?
    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }
    @Environment(\.pageAccent) private var pageAccent

    var body: some View {
        HStack(spacing: 7) {
            marker.foregroundStyle(tint ?? pageAccent).accessibilityHidden(true)
            Text(Theme.cased(text))
                .font(Theme.label)
                .tracking(Theme.tracking)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension TitleChip {
    /// A square on console, a tall bar on classic, a block cursor on gruv, a heart on kawaii.
    @ViewBuilder fileprivate var marker: some View {
        switch Skin.current {
        case .console: RoundedRectangle(cornerRadius: 1).frame(width: 7, height: 7)
        case .classic: Rectangle().frame(width: 3, height: 12)
        case .gruv: Rectangle().frame(width: 8, height: 12)
        case .kawaii: Image(systemName: "heart.fill").font(.system(size: 9, weight: .bold))
        }
    }
}

/// A panel with a title.
struct Card<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    /// The card's colour: the title tag takes the bright fill and the body a soft tint.
    /// Without one, the tag uses the tab's colour on a plain card.
    var color: CardColor? = nil
    @ViewBuilder var content: Content

    var body: some View {
        switch Skin.current {
        case .console: consoleCard
        case .classic:
            // A TradingView widget: a header strip over a rule, then the body.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 10) { content }.padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
        case .gruv:
            TermBox(title: title, trailing: subtitle) { content }
                .padding(.top, 8)
        case .kawaii:
            KawaiiCard {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.caption).foregroundStyle(color?.bright ?? Theme.accent)
                    Text(title.lowercased()).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
                }
                .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle.lowercased()).font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.muted)
                }
                content
            }
        }
    }

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                TitleChip(title, tint: color?.bright)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .block(color?.tint ?? Theme.surface)
    }
}

/// An SF Symbol on a rounded, outlined tile, filled with its category's colour. Decorative, so VoiceOver skips it.
struct CategoryIcon: View {
    let symbol: String
    var size: CGFloat = 40
    /// A bright fill, or nil for a plain tile.
    var fill: Color? = nil
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.6)
        let shape = RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: side * 0.46, weight: .bold))
            .foregroundStyle(fill == nil ? Theme.ink : Theme.onBright)
            .frame(width: side, height: side)
            .background(fill ?? Theme.paper, in: shape)
            .accessibilityHidden(true)
    }
}

/// A small outlined pill, optionally on a bright fill.
struct Badge: View {
    let text: String
    var fill: Color? = nil

    var body: some View {
        Text(text)
            .font(Theme.smallLabel)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(fill == nil ? Theme.muted : Theme.onBright)
            .background(fill ?? Theme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: fill == nil ? 1 : 0))
    }
}

/// The main figure on a screen, optionally on a block in the tab's colour.
struct HeroFigure: View {
    let text: String
    /// Kept for callers; the figure is plain text now.
    var highlighted = false

    var body: some View {
        Text(text)
            .font(Theme.hero)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Theme.ink)
    }
}

/// A rounded bar on an outlined track. The ink edge where the fill stops shows the amount
/// even where the fill colour is pale.
struct MeterBar: View {
    let fraction: Double
    /// Defaults to the tab's colour.
    var fill: Color? = nil
    @Environment(\.pageAccent) private var accent

    var body: some View {
        let amount = min(max(fraction, 0), 1)
        GeometryReader { proxy in
            Rectangle()
                .fill(fill ?? accent)
                .frame(width: proxy.size.width * amount)
        }
        .frame(height: 6)
        .background(Theme.line)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A row that stacks vertically at accessibility text sizes, so nothing gets cut off.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing / 2))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// Outlined segments in one rounded block. The chosen one takes the tab's colour and a thick
/// navy underline, so it stands out by shape as well as colour. Each segment is at least 48pt tall.
struct SegmentedBar<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    /// Kept for callers. The chosen segment always takes the accent, like TradingView's timeframes.
    var tint: ((Value) -> Color)? = nil
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isOn = option == selection
                Button { selection = option } label: {
                    let segment = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    VStack(spacing: 3) {
                        LED(on: isOn)
                        Text(Theme.cased(label(option)))
                            .font(.system(.footnote, design: Skin.current.design, weight: isOn ? .bold : .semibold))
                            .tracking(Theme.tracking)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(SegmentLook.text(isOn))
                    .background(SegmentLook.fill(isOn), in: segment)
                    .overlay(segment.strokeBorder(SegmentLook.border(isOn), lineWidth: Skin.current == .gruv ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius + 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius + 3, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// How a chosen segment or key shows it's chosen, per style: an outline and an LED on console,
/// a blue tint on classic, reverse video on gruv, a filled pill on kawaii.
enum SegmentLook {
    static func fill(_ isOn: Bool) -> Color {
        switch Skin.current {
        case .console: Theme.surface
        case .classic: isOn ? Theme.accent.opacity(0.14) : Theme.surface
        case .gruv: isOn ? Theme.ink : Theme.surface
        case .kawaii: isOn ? Theme.accent : Theme.surface
        }
    }

    static func text(_ isOn: Bool) -> Color {
        switch Skin.current {
        case .console: isOn ? Theme.ink : Theme.muted
        case .classic: isOn ? Theme.accentText : Theme.muted
        case .gruv: isOn ? Theme.paper : Theme.muted
        case .kawaii: isOn ? Theme.onAccent : Theme.muted
        }
    }

    static func border(_ isOn: Bool) -> Color {
        switch Skin.current {
        case .console: isOn ? Theme.ink.opacity(0.5) : Theme.line
        case .classic: isOn ? Theme.accent : Theme.line
        case .gruv: isOn ? Theme.ink : Theme.line
        case .kawaii: .clear
        }
    }
}

/// A flat button: the accent filled for the main action, a hairline panel otherwise.
struct BlockButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(Theme.controlRadius + 2, 24), style: .continuous)
        configuration.label
            .font(.system(.subheadline, design: Skin.current.design, weight: .semibold))
            .textCase(Skin.current == .gruv ? .uppercase : Skin.current == .classic ? nil : .lowercase)
            .tracking(Theme.tracking)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
            .background(prominent ? Theme.accent : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(prominent || Theme.rule == 0 ? Color.clear : Theme.line, lineWidth: max(Theme.rule, 1)))
            .shadow(color: Theme.ink.opacity(Theme.shadow > 0 && !prominent ? 0.08 : 0), radius: Theme.shadow / 2, y: 2)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { KeyClick.play() } }
    }
}

/// Toolbar menu for light, dark or match device.
struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
            }
        } label: {
            Label("Appearance", systemImage: appearance.symbol)
        }
        .accessibilityValue(appearance.name)
    }
}

extension View {
    /// Paper background behind a List.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.paper)
    }
}

/// A scrolling page of `CardSection`s on paper: the card version of a grouped list.
struct CardPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Skin.current.pageSpacing + 8) { content }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .labeledContentStyle(RowLabeledContentStyle())
        .background(Theme.paper)
    }
}

/// Rows on one white block, split by thin rules, under an optional title tag and over optional small print.
struct CardSection<Content: View>: View {
    var title: String? = nil
    var note: String? = nil
    /// The section's colour, as for `Card`.
    var color: CardColor? = nil
    @ViewBuilder var content: Content

    var body: some View {
        switch Skin.current {
        case .gruv:
            // A terminal pane with the rows inside and the note printed as a comment underneath.
            VStack(alignment: .leading, spacing: 6) {
                TermBox(title: title ?? "") { rowsStack(padding: 4) }
                if let note {
                    Text("# \(note)").font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
            }
            .padding(.top, title == nil ? 0 : 8)
        case .kawaii:
            VStack(alignment: .leading, spacing: 10) {
                if let title {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.caption).foregroundStyle(color?.bright ?? Theme.accent)
                        Text(title.lowercased()).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
                }
                rowsStack(padding: 18)
                    .padding(.vertical, 6)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.07), radius: 12, y: 5)
                if let note { SectionNote(note).padding(.horizontal, 10) }
            }
        case .classic:
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).frame(minHeight: 38).accessibilityAddTraits(.isHeader)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                rowsStack(padding: 12)
                if let note {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text(note).font(.caption).foregroundStyle(Theme.muted).padding(12)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
        case .console:
            consoleSection
        }
    }

    private func rowsStack(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Theme.line.opacity(Skin.current == .kawaii ? 0.6 : 1)).frame(height: 1)
                    }
                    row
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, padding)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { TitleChip(title, tint: color?.bright) }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle().fill(Theme.line).frame(height: Skin.current == .gruv ? 2 : 1)
                        }
                        row
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
            .block(color?.tint ?? Theme.surface)
            if let note { SectionNote(note).padding(.horizontal, 4) }
        }
    }
}

/// Label on the left, value on the right; stacked at accessibility text sizes.
struct RowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveStack(spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            configuration.content
        }
        .foregroundStyle(Theme.ink)
    }
}

/// A full-width tappable row inside a `CardSection`.
struct RowButton: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(destructive ? Theme.up : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A money input in an outlined box, with the baht sign right against the number.
/// Tapping anywhere on the box starts typing.
struct BahtField: View {
    let title: String
    @Binding var value: Double
    var fractionDigits = 2
    var style: Font.TextStyle = .body
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 0) {
            Text("฿").accessibilityHidden(true)
            // Leading-aligned so the number starts right after ฿; any spare width
            // the text field keeps for itself ends up on the right, inside the box.
            TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.leading)
                .fixedSize()
                .focused($focused)
                .accessibilityLabel(title)
        }
        .font(Theme.figure(style))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .frame(minWidth: 76, minHeight: 44, alignment: .trailing)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: focused ? 2 : 1))
        .contentShape(shape)
        .onTapGesture { focused = true }
    }
}

/// A date shown in an outlined box; tapping it opens a full calendar.
struct DateField: View {
    let title: String
    @Binding var date: Date
    var components: DatePickerComponents = [.date, .hourAndMinute]
    @State private var editing = false

    private var showsTime: Bool { components.contains(.hourAndMinute) }

    private var displayFormat: Date.FormatStyle {
        showsTime
            ? .dateTime.day().month(.abbreviated).year().hour().minute()
            : .dateTime.day().month(.abbreviated).year()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        LabeledContent {
            Button { editing = true } label: {
                Label {
                    Text(date, format: displayFormat)
                } icon: {
                    Image(systemName: "calendar")
                }
                .labelStyle(.titleAndIcon)
                .font(Theme.figure(.subheadline))
                .foregroundStyle(Theme.ink)
                // One line, shrinking a little for long Buddhist-era dates ("31 Dec 2569 BE").
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Theme.paper, in: shape)
                .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            // The date gets its width before the label beside it.
            .layoutPriority(1)
            .accessibilityLabel(title)
            .accessibilityValue(date.formatted(date: .long, time: showsTime ? .shortened : .omitted))
            .accessibilityHint("Opens a calendar")
        } label: {
            Text(title).foregroundStyle(Theme.ink)
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ScrollView {
                    DatePicker(title, selection: $date, displayedComponents: components)
                        .datePickerStyle(.graphical)
                        .padding()
                }
                .background(Theme.paper)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// A big rounded checkbox instead of a switch: green with a tick when on, empty when off.
/// The tick, not the colour, says which it is.
struct CheckboxToggleStyle: ToggleStyle {
    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                shape
                    .fill(configuration.isOn ? Theme.accent : Theme.surface)
                    .frame(width: 26, height: 26)
                    .overlay(shape.strokeBorder(configuration.isOn ? Color.clear : Theme.muted, lineWidth: 1.5))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                        }
                    }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Small print under a card section.
struct SectionNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Theme.muted).textCase(nil)
    }
}

/// A label with a money or other figure on the right. Emphasized figures sit on the tab's colour.
struct AmountRow: View {
    let label: String
    let value: String
    var emphasized = false
    @Environment(\.pageAccent) private var accent

    init(_ label: String, _ value: String, emphasized: Bool = false) {
        self.label = label
        self.value = value
        self.emphasized = emphasized
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .font(Theme.figure(emphasized ? .title3 : .body))
                .fontWeight(emphasized ? .semibold : .medium)
                .foregroundStyle(Theme.ink)
        } label: {
            Text(label).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Receipt {
    /// Bills show their own symbol; purchases show where most of the money went.
    var iconSymbol: String { isIncome ? incomeSource.symbol : kind.isBill ? kind.symbol : mainCategory.symbol }
    var iconColor: Color { isIncome ? Theme.mint : kind.isBill ? kind.fill : mainCategory.color }
    /// "+฿30,000.00" for money in, "฿60.00" for money out.
    var signedAmount: String { isIncome ? "+\(total.baht)" : total.baht }
    var amountColour: Color { isIncome ? Theme.down : Theme.ink }
}

struct ReceiptRow: View {
    let receipt: Receipt
    /// Adds the main category's name under the date.
    var showsCategory = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.searchHighlight) private var searchHighlight

    var body: some View {
        switch Skin.current {
        case .console: consoleRow
        case .classic: classicRow
        case .gruv: terminalRow
        case .kawaii: kawaiiRow
        }
    }

    /// A table row: date, a small icon, the shop, the amount.
    private var classicRow: some View {
        AdaptiveStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(receipt.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 48, alignment: .leading)
                Circle().fill(receipt.iconColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SearchHighlight.attributed(receipt.shopName, query: searchHighlight))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    if showsCategory || receipt.isFullTaxInvoice {
                        Text([showsCategory ? (receipt.kind.isBill ? receipt.kind.name : receipt.mainCategory.name) : nil,
                              receipt.isFullTaxInvoice ? "Tax invoice" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(receipt.signedAmount).font(.subheadline.monospacedDigit()).foregroundStyle(receipt.amountColour)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A log line: timestamp, shop, amount.
    private var terminalRow: some View {
        AdaptiveStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(receipt.date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .foregroundStyle(Theme.muted)
                Rectangle().fill(receipt.iconColor).frame(width: 6, height: 12)
                Text(SearchHighlight.attributed(receipt.shopName, query: searchHighlight))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if receipt.isFullTaxInvoice { Text("[TAX]").foregroundStyle(Theme.down) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 6) }
            Text(receipt.signedAmount).foregroundStyle(receipt.amountColour).fontWeight(.bold)
        }
        .font(.system(.footnote, design: .monospaced))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A sticker icon in a circle, round bold type.
    private var kawaiiRow: some View {
        AdaptiveStack(spacing: 12) {
            Image(systemName: receipt.iconSymbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.onBright)
                .frame(width: 44, height: 44)
                .background(receipt.iconColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchHighlight.attributed(receipt.shopName, query: searchHighlight))
                    .font(.system(.body, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: 6) {
                    Text(receipt.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    if receipt.isFullTaxInvoice { Text("· tax invoice ✿") }
                }
                .font(.system(.caption, design: .rounded)).foregroundStyle(Theme.muted)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(receipt.signedAmount).font(.system(.headline, design: .rounded).monospacedDigit()).foregroundStyle(receipt.amountColour)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var consoleRow: some View {
        AdaptiveStack {
            CategoryIcon(symbol: receipt.iconSymbol, fill: receipt.iconColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(SearchHighlight.attributed(receipt.shopName, query: searchHighlight))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                AdaptiveStack(spacing: 6) {
                    Text(receipt.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    if receipt.isFullTaxInvoice { Badge(text: "Tax invoice", fill: Theme.lime) }
                }
                if showsCategory {
                    Text(receipt.isIncome ? receipt.incomeSource.name : receipt.kind.isBill ? receipt.kind.name : receipt.mainCategory.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(receipt.signedAmount)
                .font(Theme.figure())
                .foregroundStyle(receipt.amountColour)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Theme {
    /// The bright fills in a pleasing order, for things that just need to be different from each other.
    static var rainbow: [Color] { [yellow, pink, sky, lime, orange, purple, mint, coral, cyan, peach] }
}

/// Playful shapes in the app's bright colours, like stickers on the page. Decorative only.
struct Doodles: View {
    /// Retired with the TradingView look: the chart is the decoration now.
    var body: some View { EmptyView() }
}

/// Where the money went as one strip of category colours, widest first.
struct CategoryStrip: View {
    let categories: [CategoryAmount]

    var body: some View {
        let positive = categories.filter { $0.amount > 0 }
        let total = positive.reduce(0) { $0 + $1.amount }
        if total > 0 {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(positive.enumerated()), id: \.element.id) { index, item in
                        Rectangle()
                            .fill(item.category.color)
                            .frame(width: max(0, proxy.size.width * item.amount / total))
                            .overlay(alignment: .trailing) {
                                if index < positive.count - 1 { Rectangle().fill(Theme.surface).frame(width: 1.5) }
                            }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spending by category")
            .accessibilityValue(positive.prefix(3).map { "\($0.category.name) \(($0.amount / total).percent)" }.joined(separator: ", "))
        }
    }
}

// MARK: - Hardware touches


/// The optional key click (Settings → Key clicks), off by default.
enum KeyClick {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "keyClicks") }

    static func play() {
        guard isOn else { return }
        AudioServicesPlaySystemSound(1104)
    }
}

/// Numbers and money drawn as a 5×7 dot-matrix display, unlit dots faintly showing, like the screen
/// on a pocket synth. The dots scale with Dynamic Type and VoiceOver reads the plain text.
struct DotMatrixText: View {
    let text: String
    /// Dot pitch at the default text size.
    var pitch: CGFloat = 4.2
    var colour: Color = Theme.ink
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let step = pitch * min(scale, 2.2)
        let glyphs = text.map { DotFont.glyph(for: $0) }
        let columns = glyphs.reduce(0) { $0 + $1.width + 1 } - 1
        Canvas { context, _ in
            var lit = Path()
            var unlit = Path()
            var x = 0
            for glyph in glyphs {
                for row in 0..<7 {
                    for col in 0..<glyph.width {
                        let rect = CGRect(x: CGFloat(x + col) * step, y: CGFloat(row) * step, width: step * 0.78, height: step * 0.78)
                        if glyph.isOn(row: row, col: col) { lit.addEllipse(in: rect) } else { unlit.addEllipse(in: rect) }
                    }
                }
                x += glyph.width + 1
            }
            context.fill(unlit, with: .color(colour.opacity(0.07)))
            context.fill(lit, with: .color(colour))
        }
        .frame(width: CGFloat(max(columns, 1)) * step, height: 7 * step)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// The 5×7 font: digits, baht, separators, signs and the K and M of compact amounts.
enum DotFont {
    struct Glyph {
        let rows: [String]
        var width: Int { rows.first?.count ?? 0 }
        func isOn(row: Int, col: Int) -> Bool {
            let line = Array(rows[row])
            return col < line.count && line[col] == "#"
        }
    }

    static func glyph(for character: Character) -> Glyph {
        Glyph(rows: table[character] ?? table[" "]!)
    }

    private static let table: [Character: [String]] = [
        "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
        "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
        "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
        "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
        "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
        "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
        "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
        "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
        "฿": [" #   ", "#### ", "##  #", "#### ", "##  #", "#### ", " #   "],
        ",": ["  ", "  ", "  ", "  ", "  ", " #", "# "],
        ".": [" ", " ", " ", " ", " ", " ", "#"],
        "-": ["   ", "   ", "   ", "###", "   ", "   ", "   "],
        "−": ["   ", "   ", "   ", "###", "   ", "   ", "   "],
        "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
        "%": ["##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##"],
        "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
        "M": ["#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #"],
        " ": ["  ", "  ", "  ", "  ", "  ", "  ", "  "],
    ]
}

/// A small square key in an encoder colour, with a label under it. It sinks when pressed,
/// clicks if key clicks are on, and lights its LED when selected.
struct HardwareKey: View {
    let symbol: String
    let title: String
    let colour: Color
    var isOn = false
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            KeyClick.play()
            action()
        } label: {
            VStack(spacing: 3) {
                LED(on: isOn)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onBright)
                    .frame(width: 34, height: 30)
                    .background(colour, in: RoundedRectangle(cornerRadius: min(Theme.controlRadius, 15), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: min(Theme.controlRadius, 15), style: .continuous)
                        .strokeBorder(keyBorder, lineWidth: Skin.current == .console ? 1 : 2))
                    .offset(y: isOn && Theme.hardware ? 1.5 : 0)
                Text(Theme.cased(title))
                    .font(.system(size: 9, weight: isOn ? .bold : .medium, design: Skin.current.design))
                    .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension HardwareKey {
    /// Console presses the key in; the other styles ring the chosen one.
    fileprivate var keyBorder: Color {
        Skin.current == .console ? Color.black.opacity(isOn ? 0.45 : 0.15) : (isOn ? Theme.ink : .clear)
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1.5 : 0)
    }
}

/// A rotary encoder: drag around it to turn, clicking into each option with a haptic tick.
/// VoiceOver adjusts it with swipe up and down.
struct Knob<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var size: CGFloat = 52
    /// Points of vertical drag per detent.
    var step: CGFloat = 32
    @State private var dragStart: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Detents spread over 270°, from bottom-left round to bottom-right.
    private func angle(of index: Int) -> Double {
        guard options.count > 1 else { return 0 }
        return -135 + 270 * Double(index) / Double(options.count - 1)
    }

    private var index: Int { options.firstIndex(of: selection) ?? 0 }

    var body: some View {
        HStack(spacing: 2) {
            guide
            dial
        }
        // Up and down, not round: every `step` points of travel moves one detent, on the guide or the dial.
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStart ?? index
                    if dragStart == nil { dragStart = start }
                    let steps = Int((-value.translation.height / step).rounded(.towardZero))
                    move(to: start + steps)
                }
                .onEnded { _ in dragStart = nil }
        )
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if index < options.count - 1 { selection = options[index + 1] }
            case .decrement: if index > 0 { selection = options[index - 1] }
            @unknown default: break
            }
        }
    }

    private func move(to target: Int) {
        let clamped = min(max(target, 0), options.count - 1)
        guard options[clamped] != selection else { return }
        selection = options[clamped]
        KeyClick.play()
    }

    /// ▲ | ▼ beside the dial: shows it turns by swiping up and down, and each end steps one detent.
    private var guide: some View {
        VStack(spacing: 0) {
            guideKey("chevron.up", enabled: index < options.count - 1) { move(to: index + 1) }
            Rectangle().fill(Theme.muted.opacity(0.6)).frame(width: size > 50 ? 1.5 : 1).frame(maxHeight: .infinity)
            guideKey("chevron.down", enabled: index > 0) { move(to: index - 1) }
        }
        .frame(width: guideWidth, height: size + 14)
    }

    private var guideWidth: CGFloat { max(14, size * 0.3) }

    private func guideKey(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: max(9, size * 0.2), weight: .bold))
                .foregroundStyle(enabled ? Theme.muted : Theme.quiet.opacity(0.6))
                .frame(width: guideWidth, height: max(12, size * 0.28))
                // The drawing is small; the finger target isn't.
                .contentShape(Rectangle().inset(by: -15))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dial: some View {
        ZStack {
            ForEach(options.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? Theme.accent : Theme.quiet)
                    .frame(width: 3, height: 3)
                    .offset(y: -size / 2 - 5)
                    .rotationEffect(.degrees(angle(of: i)))
            }
            Circle()
                .fill(Theme.surface)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .overlay(Circle().inset(by: 5).fill(Theme.paper))
                .overlay(
                    Capsule().fill(Theme.accent).frame(width: 3, height: size * 0.28)
                        .offset(y: -size * 0.26)
                        .rotationEffect(.degrees(angle(of: index)))
                )
                .frame(width: size, height: size)
                .animation(reduceMotion ? nil : .spring(duration: 0.18), value: index)
        }
        .frame(width: size + 14, height: size + 14)
        .contentShape(Rectangle())
    }
}

/// "01 range": the numbered parameter labels printed above controls.
struct ParameterLabel: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            switch Skin.current {
            case .console: Text(String(format: "%02d", number)).foregroundStyle(Theme.accentText)
            case .classic: EmptyView()
            case .gruv: Text(String(format: "[%02d]", number)).foregroundStyle(Theme.accentText)
            case .kawaii: Text("✿").foregroundStyle(Theme.accentText)
            }
            Text(Theme.cased(text)).foregroundStyle(Theme.muted)
        }
        .font(.system(size: Skin.current == .classic ? 11 : 10, weight: Skin.current == .classic ? .semibold : .medium, design: Skin.current.design))
        .tracking(Theme.tracking)
        .accessibilityHidden(true)
    }
}

/// A sub-second start-up screen: the model number and a line of pixels drawing across.
/// Skipped with Reduce Motion, and by a tap.
struct BootScreen: View {
    @Binding var isShowing: Bool
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("sc-01").font(.system(.title2, design: Skin.current.design, weight: .bold)).foregroundStyle(Theme.ink)
                Text("snapceipt · receipt synthesiser").font(.system(.footnote, design: Skin.current.design)).foregroundStyle(Theme.muted)
                GeometryReader { proxy in
                    let count = Int(proxy.size.width / 8)
                    HStack(spacing: 3) {
                        ForEach(0..<max(count, 1), id: \.self) { i in
                            Rectangle()
                                .fill(Double(i) / Double(max(count, 1)) < progress ? Theme.accent : Theme.line)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: 260)
        }
        .contentShape(Rectangle())
        .onTapGesture { isShowing = false }
        .task {
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(30))
                progress = Double(step) / 20
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.2)) { isShowing = false }
        }
        .accessibilityHidden(true)
    }
}
