import SwiftData
import SwiftUI

/// The graph's settings, like Obsidian's gear panel. Saved on the device.
struct SpendingGraphSettings: Codable, Equatable {
    struct Group: Codable, Equatable, Identifiable {
        var id = UUID()
        var query = ""
        /// Index into `CardColor.allCases`.
        var color = 0
    }

    var filter = SpendingGraph.Filter()
    /// One group per category to start with, in the category's own colour.
    var groups: [Group] = SpendCategory.selectable.map { category in
        Group(query: "main:\(category.rawValue)", color: CardColor.allCases.firstIndex(of: category.cardColor) ?? 0)
    }
    var sizeByAmount = false
    // Display
    var arrows = false
    var textFade = 0.0
    var nodeSize = 1.0
    var linkThickness = 1.0
    // Forces
    var centerForce = 0.35
    var repelForce = 12.0
    var linkForce = 1.0
    var linkDistance = 70.0
    // Local graph
    var depth = 1
    var incoming = true
    var outgoing = true
    var neighbourLinks = false

    private static let key = "spendingGraphSettings.v1"

    static func load() -> SpendingGraphSettings {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SpendingGraphSettings.self, from: $0) } ?? SpendingGraphSettings()
    }

    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key) }

    /// The first group whose query matches the receipt, Obsidian's "first match wins".
    func groupColor(for receipt: GraphReceipt) -> Color? {
        groups.first { !$0.query.isEmpty && GraphQuery($0.query).matches(receipt) }
            .map { CardColor.allCases[$0.color % CardColor.allCases.count].bright }
    }
}

/// Snapceipt's Obsidian-style graph: every receipt is a dot linked to its shop, and with the filters on,
/// to its categories, items and photo. Dashed purple lines are links the on-device model suggests.
/// Global shows every receipt in the date range; Local shows the neighbourhood of one receipt, shop,
/// item or category, as many steps out as the depth says.
///
/// Names stay hidden until a dot is tapped: then its card shows its totals (and Open receipt); tap a dashed
/// line to see why it was suggested. Long-press or point at a dot to light up its neighbours.
/// Drag the background to pan, drag a dot to move it, pinch to zoom; + and − and the arrow keys
/// (Shift for faster) on a keyboard.
struct SpendingGraphView: View {
    /// Extra search words from the Receipts search box.
    var externalSearch = ""
    /// The node a Local graph is centred on; nil for the Global graph.
    @State var center: String?

    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    @Query private var decisions: [LinkDecision]
    @Environment(\.modelContext) private var context

    @State private var settings = SpendingGraphSettings.load()
    @State private var sim = GraphSimulation()
    @State private var base = SpendingGraph(receipts: [])
    @State private var shown = SpendingGraph(receipts: [])
    @State private var distance: [String: Int] = [:]
    @State private var receiptsByKey: [String: Receipt] = [:]
    @State private var suggestions: [LinkSuggester.Suggestion] = []
    @State private var computing = false

    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var zoom: Double = 1
    @State private var zoomStart: Double?
    @State private var draggedNode: Int?
    @State private var pressStart: Date?
    @State private var hovered: String?
    @State private var picked: String?
    @State private var pickedEdge: SpendingGraph.Edge?
    @State private var opened: Receipt?
    @State private var revealed: Int?
    @State private var showingSettings = LaunchOption.string("graphSettings") == "YES"
    @FocusState private var focused: Bool

    // Search and finding your way
    @State private var query = LaunchOption.string("graphSearch") ?? ""
    @State private var showingResults = !(LaunchOption.string("graphSearch") ?? "").isEmpty
    @State private var onlyMatches = false
    @State private var matchIndex = 0
    @State private var canvasSize: CGSize = .zero
    @State private var showingLinks = LaunchOption.string("graphLinks") == "YES"
    @State private var showingLegend = false
    @FocusState private var searching: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: String? { hovered ?? picked }
    // A dark canvas in both modes, like a TradingView chart, with thin grey links.
    private static let suggestedColor = Color(hex: 0x7E57C2)
    private static let canvas = Color(hex: 0x000000)
    private static let edgeColor = Color(hex: 0x4A4A4A)
    private static let labelColor = Color(hex: 0xEDEDE8)
    private static let dimLabel = Color(hex: 0x9598A1)
    private static let outline = Color(hex: 0x9598A1)
    private static let hubFill = Color(hex: 0x1A1A1A)

    var body: some View {
        GeometryReader { geo in
            let middle = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let scale = zoom * sim.fitScale(in: geo.size)
            let toWorld = { (p: CGPoint) in
                CGPoint(x: (p.x - middle.x - offset.width) / scale, y: (p.y - middle.y - offset.height) / scale)
            }
            let _ = sim.tick

            Canvas { context, _ in draw(in: &context, middle: middle, scale: scale) }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, size in canvasSize = size }
                .contentShape(Rectangle())
                .gesture(dragGesture(toWorld: toWorld, scale: scale))
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if zoomStart == nil { zoomStart = zoom }
                            zoom = min(6, max(0.15, zoomStart! * value.magnification))
                        }
                        .onEnded { _ in zoomStart = nil }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hovered = node(at: toWorld(location), scale: scale)
                    case .ended: hovered = nil
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(center == nil ? "Graph of your receipts" : "Local graph")
                .accessibilityChildren { accessibilityNodes }
        }
        .background(Self.canvas)
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down, action: keyPress)
        .overlay(alignment: .bottomTrailing) {
            if pickedEdge == nil && picked == nil { zoomKeys }
        }
        .overlay(alignment: .bottom) { bottomCard }
        .overlay(alignment: .top) { controlPanel }
        .sheet(isPresented: $showingLinks) { linksSheet }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { recenter() } label: { Label("Fit graph", systemImage: "scope") }
                Button { showingSettings.toggle() } label: { Label("Graph settings", systemImage: "gearshape") }
            }
        }
        .inspector(isPresented: $showingSettings) {
            SpendingGraphSettingsPanel(settings: $settings, isLocal: center != nil, computing: computing,
                                       suggestionCount: shown.edges.filter { $0.kind == .suggested }.count,
                                       onAnimate: animate)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $opened) { ReceiptDetailView(receipt: $0) }
        .task(id: fingerprint) { await rebuild() }
        .onAppear { focused = true }
        .onChange(of: settings) { old, new in
            new.save()
            applyForces()
            if old.filter != new.filter || old.depth != new.depth || old.incoming != new.incoming
                || old.outgoing != new.outgoing || old.neighbourLinks != new.neighbourLinks {
                refilter()
            }
        }
        .onChange(of: externalSearch) { refilter() }
        .onChange(of: query) {
            matchIndex = 0
            showingResults = !query.isEmpty
            if onlyMatches { refilter() }
        }
        .onChange(of: onlyMatches) { refilter() }
        .onChange(of: decisions.map(\.pairKey) + decisions.map { $0.confirmed ? "1" : "0" }) { refilter() }
        .onChange(of: center) {
            picked = nil
            pickedEdge = nil
            refilter()
            recenter()
        }
        .task(id: sim.isMoving) {
            guard sim.isMoving else { return }
            if reduceMotion { sim.settle(); return }
            while sim.isMoving, !Task.isCancelled {
                sim.step()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: - Data

    /// Changes when receipts are added, removed or edited, so the graph and suggestions follow.
    private var fingerprint: Int {
        var hasher = Hasher()
        for receipt in receipts {
            hasher.combine(receipt.persistentModelID)
            hasher.combine(receipt.total)
            hasher.combine(receipt.date)
            hasher.combine(receipt.shopName)
            hasher.combine(receipt.items.count)
        }
        return hasher.finalize()
    }

    private func rebuild() async {
        var byKey: [String: Receipt] = [:]
        let graphReceipts = receipts.map { receipt in
            let key = receipt.graphKey
            byKey[key] = receipt
            return receipt.graphReceipt(key: key)
        }
        receiptsByKey = byKey
        base = SpendingGraph(receipts: graphReceipts)
        if center == nil, let start = LaunchOption.string("graphCenter") {
            center = start == "latest" ? receipts.last.map { SpendingGraph.receiptID($0.graphKey) } : start
        }
        refilter()
        computing = true
        let duplicates = base.duplicates
        suggestions = await LinkSuggestionEngine.shared.suggestions(for: graphReceipts, excluding: duplicates)
        computing = false
        refilter()
        if LaunchOption.string("graphPickSuggestion") == "YES" {
            pickedEdge = shown.edges.filter { $0.kind == .suggested }.max { $0.score < $1.score }
        }
    }

    private func refilter() {
        var filter = settings.filter
        filter.search = [settings.filter.search, externalSearch, onlyMatches ? query : ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        let local = center.map {
            SpendingGraph.Local(center: $0, depth: settings.depth, incoming: settings.incoming,
                                outgoing: settings.outgoing, neighbourLinks: settings.neighbourLinks)
        }
        let decided = Dictionary(decisions.map { ($0.pairKey, $0.confirmed) }, uniquingKeysWith: { _, last in last })
        let result = base.filtered(filter, local: local, suggestions: suggestions, decisions: decided)
        shown = result.graph
        distance = result.distance
        applyForces()
        let masses = Dictionary(uniqueKeysWithValues: shown.nodes.map { ($0.id, $0.kind == .receipt ? 1 : 1 + Double($0.count).squareRoot()) })
        sim.update(nodes: shown.nodes.map(\.id), edges: shown.edges.map { ($0.from, $0.to) }, masses: masses)
    }

    private func applyForces() {
        sim.center = settings.centerForce
        sim.repel = settings.repelForce
        sim.linkForce = settings.linkForce
        sim.linkDistance = settings.linkDistance
        sim.reheat(0.4)
    }

    /// Receipts still hidden by the Animate time-lapse, with the hubs only they link to.
    private var hiddenByAnimation: Set<String> {
        guard let revealed else { return [] }
        let order = shown.nodes.filter { $0.kind == .receipt }.sorted { ($0.firstDate ?? .distantPast) < ($1.firstDate ?? .distantPast) }
        let visible = Set(order.prefix(revealed).map(\.id))
        let hiddenReceipts = Set(order.map(\.id)).subtracting(visible)
        let hubs = shown.nodes.filter { $0.kind != .receipt }.map(\.id).filter { id in
            !shown.edges.contains { $0.to == id && visible.contains($0.from) }
        }
        return hiddenReceipts.union(hubs)
    }

    // MARK: - Drawing

    private func radius(of node: SpendingGraph.Node) -> Double {
        let size: Double
        switch node.kind {
        case .receipt: size = settings.sizeByAmount ? 3 + node.amount.squareRoot() / 7 : 5
        case .photo: size = 3.5
        default: size = settings.sizeByAmount ? 5 + node.amount.squareRoot() / 5 : 5 + 3.4 * Double(node.count).squareRoot()
        }
        return min(size, 60) * settings.nodeSize
    }

    private func fill(of node: SpendingGraph.Node) -> Color {
        switch node.kind {
        case .receipt:
            return node.receiptKey.flatMap { shown.receipts[$0] }.flatMap(settings.groupColor(for:))
                ?? node.category?.color ?? Theme.stone
        case .shop: return Self.hubFill
        case .category: return node.category?.color ?? Theme.stone
        case .item: return Theme.stone
        case .photo: return Theme.sky
        case .unknownShop: return Self.canvas
        }
    }

    private func draw(in context: inout GraphicsContext, middle: CGPoint, scale: Double) {
        func screen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: middle.x + offset.width + p.x * scale, y: middle.y + offset.height + p.y * scale)
        }
        let hidden = hiddenByAnimation
        let lit = highlighted.map { shown.neighbours(of: $0).union([$0]) }
        let width = max(0.4, settings.linkThickness * min(scale, 1.5))

        for edge in shown.edges where !hidden.contains(edge.from) && !hidden.contains(edge.to) {
            guard let a = sim.position(of: edge.from), let b = sim.position(of: edge.to) else { continue }
            let isLit = highlighted != nil && (edge.from == highlighted || edge.to == highlighted)
            let isPicked = pickedEdge.map { Set([$0.from, $0.to]) == Set([edge.from, edge.to]) } ?? false
            let pa = screen(a), pb = screen(b)
            var line = Path()
            line.move(to: pa)
            line.addLine(to: pb)
            let fade = lit == nil || isLit ? 1 : 0.25
            switch edge.kind {
            case .link:
                let colour = isLit ? Self.labelColor : Self.edgeColor.opacity(0.7 * fade)
                context.stroke(line, with: .color(colour), lineWidth: isLit ? width * 1.8 : width)
                if settings.arrows, let target = shown.node(edge.to) {
                    arrow(in: &context, from: pa, to: pb, inset: radius(of: target) * nodeScale(scale), size: 4 + width * 2, colour: colour)
                }
            case .suggested:
                context.stroke(line, with: .color(Self.suggestedColor.opacity(fade)),
                               style: StrokeStyle(lineWidth: (isPicked ? 3.5 : 1.6) * max(0.6, width), lineCap: .round, dash: [5, 4]))
            case .confirmed:
                context.stroke(line, with: .color(Self.suggestedColor.opacity(fade)), lineWidth: width * 2.2)
            }
        }

        let ns = nodeScale(scale)
        let found = matchSet
        let current = currentMatch
        // While searching, what matched (and what it's linked to) stays bright and the rest steps back.
        let near = found.isEmpty ? nil : found.reduce(into: Set<String>()) { $0.formUnion(shown.neighbours(of: $1)) }.union(found)

        var labels: [(priority: Double, node: SpendingGraph.Node, point: CGPoint, radius: Double, alpha: Double, hit: Bool, focus: Bool)] = []
        for node in shown.nodes where !hidden.contains(node.id) {
            guard let world = sim.position(of: node.id) else { continue }
            let p = screen(world)
            let isMatch = found.contains(node.id)
            let isFocus = node.id == highlighted || node.id == center || node.id == current
            let dimmed = (lit.map { !$0.contains(node.id) } ?? false) || (near.map { !$0.contains(node.id) } ?? false)
            let r = radius(of: node) * ns * (isFocus ? 1.3 : isMatch ? 1.15 : 1)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            let shape = node.kind == .category ? Path(roundedRect: rect, cornerRadius: r * 0.35) : Path(ellipseIn: rect)
            context.opacity = dimmed ? 0.18 : 1
            context.fill(shape, with: .color(fill(of: node)))
            let stroke: StrokeStyle = switch node.kind {
            case .shop: StrokeStyle(lineWidth: isFocus ? 2.5 : 1.5)
            case .unknownShop: StrokeStyle(lineWidth: 1, dash: [3, 2])
            default: StrokeStyle(lineWidth: isFocus ? 2 : 0.8)
            }
            context.stroke(shape, with: .color(isFocus ? Self.labelColor : Self.outline), style: stroke)
            if isMatch {
                // An orange ring around every search match, thicker on the one you're on.
                let ring = rect.insetBy(dx: -4, dy: -4)
                context.stroke(Path(ellipseIn: ring), with: .color(Theme.accent), lineWidth: node.id == current ? 3 : 1.6)
            }
            context.opacity = 1

            // Names stay hidden until a dot is tapped or pressed (or is the search match you're on),
            // which keeps the graph calm and quick to draw.
            guard isFocus else { continue }
            labels.append((1000, node, p, r, 1, isMatch, isFocus))
        }

        // Labels never sit on top of each other: the most important go first and the rest wait
        // until zooming in makes room.
        var taken: [CGRect] = []
        for label in labels.sorted(by: { $0.priority > $1.priority }) {
            let size = (label.node.kind == .shop ? 12.5 : 11) * min(max(scale, 0.9), 1.4)
            let width = Double(label.node.title.count) * size * 0.56 + 6
            let box = CGRect(x: label.point.x - width / 2, y: label.point.y + label.radius + 3, width: width, height: size * 1.35)
            if !label.focus, taken.contains(where: { $0.intersects(box) }) { continue }
            taken.append(box)
            let hit = label.hit || !SearchHighlight.ranges(of: searchWords, in: label.node.title).isEmpty
            let text = Text(label.node.title)
                .font(.system(size: size, weight: hit ? .heavy : label.node.kind == .shop || label.focus ? .semibold : .regular))
                .foregroundStyle(hit ? Theme.accent : label.node.kind == .unknownShop ? Self.dimLabel : Self.labelColor)
            context.opacity = hit ? 1 : label.alpha
            context.draw(text, at: CGPoint(x: label.point.x, y: box.minY), anchor: .top)
            context.opacity = 1
        }
    }

    /// The plain words of the graph search (not `shop:` style filters), for marking labels.
    private var searchWords: String {
        ([settings.filter.search, externalSearch, query].joined(separator: " "))
            .split(separator: " ").filter { !$0.contains(":") && !$0.hasPrefix("-") }.joined(separator: " ")
    }

    private func nodeScale(_ scale: Double) -> Double { min(max(scale, 0.35), 2.5) }

    private func arrow(in context: inout GraphicsContext, from a: CGPoint, to b: CGPoint, inset: Double, size: Double, colour: Color) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > inset + size else { return }
        let ux = dx / length, uy = dy / length
        let tip = CGPoint(x: b.x - ux * inset, y: b.y - uy * inset)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - ux * size - uy * size * 0.55, y: tip.y - uy * size + ux * size * 0.55))
        head.addLine(to: CGPoint(x: tip.x - ux * size + uy * size * 0.55, y: tip.y - uy * size - ux * size * 0.55))
        head.closeSubpath()
        context.fill(head, with: .color(colour))
    }

    // MARK: - Interaction

    private func node(at world: CGPoint, scale: Double) -> String? {
        let hidden = hiddenByAnimation
        let ns = nodeScale(scale)
        return shown.nodes.filter { !hidden.contains($0.id) }
            .compactMap { node -> (String, Double)? in
                guard let p = sim.position(of: node.id) else { return nil }
                let d = hypot(p.x - world.x, p.y - world.y)
                return d <= max(radius(of: node) * ns / scale * 1.3, 22 / scale) ? (node.id, d) : nil
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// The suggested or confirmed link closest to a point, if one is within reach.
    private func mlEdge(at world: CGPoint, scale: Double) -> SpendingGraph.Edge? {
        shown.edges.filter { $0.kind != .link }.compactMap { edge -> (SpendingGraph.Edge, Double)? in
            guard let a = sim.position(of: edge.from), let b = sim.position(of: edge.to) else { return nil }
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((world.x - a.x) * dx + (world.y - a.y) * dy) / max(dx * dx + dy * dy, 1)))
            let d = hypot(world.x - (a.x + t * dx), world.y - (a.y + t * dy))
            return d <= 14 / scale ? (edge, d) : nil
        }.min { $0.1 < $1.1 }?.0
    }

    private func dragGesture(toWorld: @escaping (CGPoint) -> CGPoint, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = .now
                    if let id = node(at: toWorld(value.startLocation), scale: scale) { draggedNode = sim.index(of: id) }
                    panStart = offset
                    let start = pressStart
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if pressStart == start, hypot(value.translation.width, value.translation.height) < 6,
                           let id = node(at: toWorld(value.startLocation), scale: scale) {
                            withAnimation(.snappy) { picked = id; pickedEdge = nil }
                        }
                    }
                }
                guard hypot(value.translation.width, value.translation.height) > 6 else { return }
                if let index = draggedNode {
                    sim.pinned = index
                    sim.move(index, to: toWorld(value.location))
                } else if let start = panStart {
                    offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                }
            }
            .onEnded { value in
                let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
                if hypot(value.translation.width, value.translation.height) <= 6, held < 0.45 {
                    let world = toWorld(value.location)
                    if let id = node(at: world, scale: scale) {
                        tap(id)
                    } else if let edge = mlEdge(at: world, scale: scale) {
                        withAnimation(.snappy) { pickedEdge = edge; picked = nil }
                    } else {
                        withAnimation(.snappy) { picked = nil; pickedEdge = nil }
                    }
                }
                sim.pinned = nil
                draggedNode = nil
                pressStart = nil
                panStart = nil
            }
    }

    private func keyPress(_ press: KeyPress) -> KeyPress.Result {
        let step = press.modifiers.contains(.shift) ? 160.0 : 40.0
        switch press.key {
        case "+", "=": zoom = min(6, zoom * 1.2)
        case "-", "_": zoom = max(0.15, zoom / 1.2)
        case .leftArrow: offset.width += step
        case .rightArrow: offset.width -= step
        case .upArrow: offset.height += step
        case .downArrow: offset.height -= step
        default: return .ignored
        }
        return .handled
    }

    private func recenter() {
        withAnimation(reduceMotion ? nil : .snappy) { offset = .zero; zoom = 1 }
    }

    /// Shows the dot's name and its card: a receipt's total with "Open receipt", or a shop's,
    /// item's or category's totals and receipts. Tapping it again closes the card.
    private func tap(_ id: String) {
        guard shown.node(id) != nil else { return }
        let closing = picked == id
        withAnimation(.snappy) {
            picked = closing ? nil : id
            pickedEdge = nil
        }
        // Slides the dot above its card, so its name shows.
        if !closing { flyTo(id) }
    }

    private func animate() {
        guard !reduceMotion else { return }
        showingSettings = false
        let total = shown.nodes.filter { $0.kind == .receipt }.count
        revealed = 0
        Task {
            for count in 1...max(1, total) {
                try? await Task.sleep(for: .milliseconds(max(20, 4000 / max(total, 1))))
                revealed = count
                sim.reheat(0.3)
            }
            try? await Task.sleep(for: .milliseconds(400))
            revealed = nil
        }
    }

    private func decide(_ edge: SpendingGraph.Edge, confirmed: Bool) {
        guard let a = shown.node(edge.from)?.receiptKey, let b = shown.node(edge.to)?.receiptKey else { return }
        LinkDecision.set(confirmed, for: LinkSuggester.pairKey(a, b), in: context)
        withAnimation(.snappy) { pickedEdge = nil }
    }

    // MARK: - Overlays

    // MARK: - Search

    /// What the search finds in the graph on show, best first.
    private var matches: [SpendingGraph.Node] { shown.search(query) }
    private var matchSet: Set<String> { Set(matches.map(\.id)) }
    private var currentMatch: String? {
        let list = matches
        return list.isEmpty || query.isEmpty ? nil : list[min(matchIndex, list.count - 1)].id
    }

    /// Moves the view so the node sits in the middle, zoomed in enough to read, and shows its card.
    private func select(_ id: String) {
        showingResults = false
        searching = false
        if let index = matches.firstIndex(where: { $0.id == id }) { matchIndex = index }
        flyTo(id)
        withAnimation(.snappy) { picked = id; pickedEdge = nil }
    }

    private func step(_ by: Int) {
        let list = matches
        guard !list.isEmpty else { return }
        matchIndex = (matchIndex + by + list.count) % list.count
        select(list[matchIndex].id)
    }

    private func flyTo(_ id: String) {
        guard let p = sim.position(of: id), canvasSize != .zero else { return }
        let target = max(zoom, 2.2)
        let s = target * sim.fitScale(in: canvasSize)
        // In the strip between the search bar and the card at the bottom, so neither covers it.
        let move = { zoom = target; offset = CGSize(width: -p.x * s, height: -p.y * s - canvasSize.height * 0.25) }
        if reduceMotion { move() } else { withAnimation(.snappy(duration: 0.45), move) }
    }

    private func symbol(of kind: SpendingGraph.Node.Kind) -> String {
        switch kind {
        case .receipt: "doc.text"
        case .shop: "storefront"
        case .category: "square.grid.2x2"
        case .item: "tag"
        case .photo: "photo"
        case .unknownShop: "questionmark.circle"
        }
    }

    private func kindName(_ kind: SpendingGraph.Node.Kind) -> String {
        switch kind {
        case .receipt: "Receipt"
        case .shop: "Shop"
        case .category: "Category"
        case .item: "Item"
        case .photo: "Photo"
        case .unknownShop: "Unknown shop"
        }
    }

    // MARK: - Overlays

    /// The search box, its results, and one row of quick switches. Always on top of the graph.
    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let center, let node = base.node(center) {
                HStack(spacing: 10) {
                    Button { self.center = nil } label: { Label("Whole graph", systemImage: "chevron.left") }
                        .accessibilityLabel("Back to the whole graph")
                    Text(node.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Stepper("Steps \(settings.depth)", value: $settings.depth, in: 1...5).fixedSize()
                }
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .block(radius: 12)
            }
            searchBox
            if showingResults { resultsList }
            chips
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: 560)
    }

    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search shops, items, categories, ฿ or dates", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .onSubmit { if !matches.isEmpty { select(matches[min(matchIndex, matches.count - 1)].id) } }
                .onChange(of: searching) { _, on in if on && !query.isEmpty { showingResults = true } }
                .accessibilityLabel("Search the graph")
            if !query.isEmpty {
                let count = matches.count
                Text(count == 0 ? "none" : "\(min(matchIndex, count - 1) + 1)/\(count)")
                    .font(Theme.figure(.footnote))
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel(count == 0 ? "No matches" : "Match \(min(matchIndex, count - 1) + 1) of \(count)")
                stepButton("chevron.up", label: "Previous match") { step(-1) }.disabled(count == 0)
                stepButton("chevron.down", label: "Next match") { step(1) }.disabled(count == 0)
                stepButton("xmark.circle.fill", label: "Clear search") {
                    query = ""
                    onlyMatches = false
                    withAnimation(.snappy) { picked = nil }
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.ink)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 44)
        .block(radius: 12)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
                .frame(width: 36, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var resultsList: some View {
        let list = Array(matches.prefix(40))
        return VStack(spacing: 0) {
            if list.isEmpty {
                Text("Nothing matches “\(query)”. Try a shop, an item, a category, an amount like 120, or a month like oct.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(list) { node in
                            Button { select(node.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(of: node.kind))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.onBright)
                                        .frame(width: 28, height: 28)
                                        .background(node.kind == .receipt || node.kind == .category ? (node.category?.color ?? Theme.stone) : Theme.stone,
                                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(node.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                        Text("\(kindName(node.kind)) · \(subtitle(of: node))")
                                            .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "scope").font(.caption).foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows it on the graph")
                            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 50)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .block(radius: 12)
    }

    /// Dates, what to show, only-matches, the ML links list and the legend, one tap each.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SpendingGraph.DateRange.allCases, id: \.self) { range in
                    chip(range == .month ? "This month" : range == .year ? "This year" : "All time",
                         symbol: nil, isOn: settings.filter.range == range) { settings.filter.range = range }
                }
                chip("Items", symbol: "tag", isOn: settings.filter.showItems) { settings.filter.showItems.toggle() }
                chip("Categories", symbol: "square.grid.2x2", isOn: settings.filter.showCategories) { settings.filter.showCategories.toggle() }
                if !query.isEmpty {
                    chip("Only matches", symbol: "line.3.horizontal.decrease", isOn: onlyMatches) { onlyMatches.toggle() }
                }
                let suggested = shown.edges.filter { $0.kind == .suggested }.count
                chip(suggested > 0 ? "Links to check · \(suggested)" : "ML links", symbol: "sparkles", isOn: false) { showingLinks = true }
                chip("Key", symbol: "info.circle", isOn: showingLegend) { showingLegend.toggle() }
                    .popover(isPresented: $showingLegend) { legend.presentationCompactAdaptation(.popover) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, symbol: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            KeyClick.play()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                Text(title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.line, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// What the dots, squares and lines mean.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to read the graph").font(.headline).foregroundStyle(Theme.ink)
            legendRow(Circle().fill(Theme.orange).frame(width: 10, height: 10), "A receipt, in its category’s colour")
            legendRow(Circle().fill(Self.hubFill).overlay(Circle().strokeBorder(Self.outline, lineWidth: 1.5)).frame(width: 16, height: 16),
                      "A shop: bigger when you go there more")
            legendRow(RoundedRectangle(cornerRadius: 3).fill(Theme.mint).frame(width: 14, height: 14), "A category (turn on Categories)")
            legendRow(Circle().fill(Theme.stone).frame(width: 12, height: 12), "An item (turn on Items)")
            legendRow(Capsule().fill(Self.edgeColor).frame(width: 22, height: 2), "Bought at / contains")
            legendRow(Capsule().stroke(Self.suggestedColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 22, height: 2),
                      "The on-device model thinks these belong together")
            legendRow(Capsule().fill(Self.suggestedColor).frame(width: 22, height: 3), "A link you confirmed")
            legendRow(Circle().stroke(Theme.accent, lineWidth: 2).frame(width: 14, height: 14), "Matches your search")
            Text("Tap a dot for its card · drag to move around · pinch or use + − to zoom · long-press to light up what’s linked.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func legendRow<Mark: View>(_ mark: Mark, _ text: String) -> some View {
        HStack(spacing: 10) {
            mark.frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// + − and fit, for zooming without a pinch.
    private var zoomKeys: some View {
        VStack(spacing: 8) {
            zoomKey("plus", label: "Zoom in") { zoom = min(6, zoom * 1.4) }
            zoomKey("minus", label: "Zoom out") { zoom = max(0.15, zoom / 1.4) }
            zoomKey("arrow.down.right.and.arrow.up.left", label: "Fit the whole graph") { recenter() }
        }
        .padding(14)
    }

    private func zoomKey(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion { action() } else { withAnimation(.snappy, action) }
        } label: {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - ML links list

    /// Every link the model suggests, strongest first, to confirm or dismiss in one place, then
    /// the ones already confirmed.
    private var linksSheet: some View {
        let suggested = shown.edges.filter { $0.kind == .suggested }.sorted { $0.score > $1.score }
        let confirmed = shown.edges.filter { $0.kind == .confirmed }
        return NavigationStack {
            CardPage {
                if suggested.isEmpty && confirmed.isEmpty {
                    Text(computing ? "Looking for links on this device…" : "No suggested links in this view. Try “All time”, or lower the match strength in the graph settings.")
                        .foregroundStyle(Theme.muted)
                }
                if !suggested.isEmpty {
                    CardSection(title: "To check · \(suggested.count)", note: "Receipts the on-device model thinks belong together, like the same trip or a repeat purchase. Confirming keeps the link; dismissing hides it for good.", color: .purple) {
                        ForEach(suggested, id: \.self) { edge in linkRow(edge) }
                    }
                }
                if !confirmed.isEmpty {
                    CardSection(title: "Confirmed · \(confirmed.count)", color: .lime) {
                        ForEach(confirmed, id: \.self) { edge in linkRow(edge) }
                    }
                }
            }
            .navigationTitle("ML links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLinks = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func linkRow(_ edge: SpendingGraph.Edge) -> some View {
        let a = shown.node(edge.from), b = shown.node(edge.to)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(a?.title ?? "") ↔ \(b?.title ?? "")").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("\(a.map(subtitle(of:)) ?? "")  ·  \(b.map(subtitle(of:)) ?? "")").font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
            Text(edge.reason).font(.subheadline).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                MeterBar(fraction: edge.score, fill: Theme.purple).frame(maxWidth: 120)
                Text(edge.score.percent).font(Theme.figure(.footnote)).foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Button {
                    showingLinks = false
                    flyTo(edge.from)
                    withAnimation(.snappy) { pickedEdge = edge; picked = nil }
                } label: { Image(systemName: "scope").frame(width: 40, height: 40) }
                .accessibilityLabel("Show on the graph")
                if edge.kind == .suggested {
                    Button { decide(edge, confirmed: false) } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                        .accessibilityLabel("Dismiss")
                    Button { decide(edge, confirmed: true) } label: {
                        Image(systemName: "checkmark").foregroundStyle(Theme.onAccent).frame(width: 40, height: 40)
                            .background(Theme.accent, in: Circle())
                    }
                    .accessibilityLabel("Confirm")
                } else {
                    Button { decide(edge, confirmed: false) } label: { Label("Remove", systemImage: "link.badge.plus") }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var bottomCard: some View {
        if let edge = pickedEdge {
            suggestionCard(edge)
        } else if let id = picked, let node = shown.node(id) ?? base.node(id) {
            hubCard(node)
        }
    }

    private func suggestionCard(_ edge: SpendingGraph.Edge) -> some View {
        let a = shown.node(edge.from), b = shown.node(edge.to)
        return Card(title: edge.kind == .confirmed ? "Confirmed link" : "Suggested link", color: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(a?.title ?? "") ↔ \(b?.title ?? "")").font(.system(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(edge.reason).foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Text("Match strength").foregroundStyle(Theme.muted)
                    MeterBar(fraction: edge.score, fill: Theme.purple).frame(maxWidth: 140)
                    Text(edge.score.percent).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                AdaptiveStack(spacing: 10) {
                    if edge.kind == .suggested {
                        Button { decide(edge, confirmed: true) } label: { Label("Confirm", systemImage: "checkmark") }
                            .buttonStyle(BlockButtonStyle(prominent: true))
                    }
                    Button { decide(edge, confirmed: false) } label: {
                        Label(edge.kind == .suggested ? "Dismiss" : "Remove link", systemImage: "xmark")
                    }
                    .buttonStyle(BlockButtonStyle())
                }
                Button { withAnimation(.snappy) { pickedEdge = nil } } label: {
                    Text("Close").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.pageAccent, Theme.purple)
        .frame(maxWidth: 520)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func hubCard(_ node: SpendingGraph.Node) -> some View {
        let linked = node.kind == .receipt ? [] : shown.backlinks(of: node.id)
        let colour: CardColor = switch node.kind {
        case .shop, .unknownShop: .yellow
        case .category: node.category?.cardColor ?? .peach
        case .item: .lime
        case .photo: .sky
        case .receipt: node.category?.cardColor ?? .pink
        }
        return Card(title: node.title, subtitle: subtitle(of: node), color: colour) {
            VStack(alignment: .leading, spacing: 8) {
                if node.kind != .receipt {
                    HeroFigure(text: node.amount.baht, highlighted: true)
                        .environment(\.pageAccent, colour.bright)
                }
                if !linked.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(linked, id: \.key) { item in
                                if let receipt = receiptsByKey[item.key] {
                                    Button { opened = receipt } label: { ReceiptRow(receipt: receipt).padding(.vertical, 4) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                AdaptiveStack(spacing: 10) {
                    if node.kind == .receipt, let key = node.receiptKey, let receipt = receiptsByKey[key] {
                        Button { opened = receipt } label: { Label("Open", systemImage: "doc.text") }
                            .buttonStyle(BlockButtonStyle(prominent: true))
                    }
                    if center != node.id {
                        Button { picked = nil; center = node.id } label: { Label("Local graph", systemImage: "scope") }
                            .buttonStyle(BlockButtonStyle())
                    }
                    Button { withAnimation(.snappy) { picked = nil } } label: { Label("Close", systemImage: "xmark") }
                        .buttonStyle(BlockButtonStyle())
                }
            }
        }
        .frame(maxWidth: 520)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func subtitle(of node: SpendingGraph.Node) -> String {
        let span: String = {
            guard let first = node.firstDate, let last = node.lastDate else { return "" }
            let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
            return first == last ? first.formatted(format) : "\(first.formatted(format)) – \(last.formatted(format))"
        }()
        switch node.kind {
        case .receipt:
            let links = shown.edges.filter { ($0.from == node.id || $0.to == node.id) && $0.kind != .link }.count
            return "\(node.amount.baht) · \(span)" + (links > 0 ? " · \(links) ML link\(links == 1 ? "" : "s")" : "")
        case .photo: return "Receipt photo"
        default: return "\(node.count) receipt\(node.count == 1 ? "" : "s") · \(span)"
        }
    }

    /// For VoiceOver: every dot with its links, biggest hubs first.
    @ViewBuilder
    private var accessibilityNodes: some View {
        ForEach(shown.nodes.sorted { $0.count > $1.count }) { node in
            let links = shown.neighbours(of: node.id).count
            Rectangle()
                .accessibilityElement()
                .accessibilityLabel(node.title)
                .accessibilityValue("\(subtitle(of: node)), \(links) link\(links == 1 ? "" : "s")")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { tap(node.id) }
                .accessibilityAction(named: "Show local graph") { center = node.id }
        }
    }
}

/// Obsidian's gear panel for the spending graph: Filters, Groups, Display and Forces.
struct SpendingGraphSettingsPanel: View {
    @Binding var settings: SpendingGraphSettings
    let isLocal: Bool
    let computing: Bool
    let suggestionCount: Int
    let onAnimate: () -> Void

    @State private var showFilters = true
    @State private var showGroups = false
    @State private var showDisplay = true
    @State private var showForces = true
    @State private var embedding = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            CardPage {
                if isLocal {
                    CardSection(title: "Local graph", color: .yellow) {
                        Stepper("Depth: \(settings.depth)", value: $settings.depth, in: 1...5)
                        Toggle("Incoming links", isOn: $settings.incoming)
                        Toggle("Outgoing links", isOn: $settings.outgoing)
                        Toggle("Neighbour links", isOn: $settings.neighbourLinks)
                    }
                }

                section("Filters", isOn: $showFilters, color: .pink) {
                    TextField("Search: shop, item, category, amount, date", text: $settings.filter.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SegmentedBar(title: "Dates", options: SpendingGraph.DateRange.allCases, selection: $settings.filter.range) { $0.rawValue }
                    LabeledContent("Category") {
                        Picker("Category", selection: $settings.filter.category) {
                            Text("All").tag(SpendCategory?.none)
                            ForEach(SpendCategory.selectable) { Label($0.name, systemImage: $0.symbol).tag(Optional($0)) }
                        }
                        .labelsHidden()
                    }
                    Toggle("Receipts", isOn: $settings.filter.showReceipts)
                    Toggle("Items", isOn: $settings.filter.showItems)
                    Toggle("Categories (tags)", isOn: $settings.filter.showCategories)
                    Toggle("Photos (attachments)", isOn: $settings.filter.showPhotos)
                    Toggle("Readable shops only", isOn: $settings.filter.existingOnly)
                    Toggle("Orphans", isOn: $settings.filter.showOrphans)
                    Toggle("Suggested links (ML)", isOn: $settings.filter.showSuggestions)
                    slider("Match strength", value: $settings.filter.minimumScore, in: 0.3...1, percent: true)
                    Text(computing ? "Finding suggestions on this device…" : "\(suggestionCount) suggested link\(suggestionCount == 1 ? "" : "s") shown. Matched on this device with \(embedding).")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    LabeledContent("Size by") {
                        Picker("Size by", selection: $settings.sizeByAmount) {
                            Text("Receipts").tag(false)
                            Text("Amount").tag(true)
                        }
                        .labelsHidden()
                    }
                }

                section("Groups", isOn: $showGroups, color: .lime) {
                    ForEach($settings.groups) { $group in
                        HStack {
                            Menu {
                                ForEach(CardColor.allCases.indices, id: \.self) { i in
                                    Button(String(describing: CardColor.allCases[i]).capitalized) { group.color = i }
                                }
                            } label: {
                                Circle().fill(CardColor.allCases[group.color % CardColor.allCases.count].bright)
                                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                                    .frame(width: 24, height: 24)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Colour")
                            TextField("Query, e.g. shop:starbucks", text: $group.query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button(role: .destructive) { settings.groups.removeAll { $0.id == group.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.up)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove group")
                        }
                    }
                    RowButton(title: "New group", symbol: "plus") {
                        settings.groups.append(.init(color: settings.groups.count % CardColor.allCases.count))
                    }
                }

                section("Display", isOn: $showDisplay, color: .sky) {
                    Toggle("Arrows", isOn: $settings.arrows)
                    slider("Node size", value: $settings.nodeSize, in: 0.3...3)
                    slider("Link thickness", value: $settings.linkThickness, in: 0.3...4)
                    RowButton(title: reduceMotion ? "Animate (off with Reduce Motion)" : "Animate: receipts in date order", symbol: "play.fill", action: onAnimate)
                        .disabled(reduceMotion)
                }

                section("Forces", isOn: $showForces, color: .orange) {
                    slider("Center force", value: $settings.centerForce, in: 0...1)
                    slider("Repel force", value: $settings.repelForce, in: 0...20)
                    slider("Link force", value: $settings.linkForce, in: 0...1)
                    slider("Link distance", value: $settings.linkDistance, in: 30...300)
                }

                CardSection(color: .coral) {
                    RowButton(title: "Reset graph settings", symbol: "arrow.counterclockwise", destructive: true) {
                        settings = SpendingGraphSettings()
                    }
                }
            }
            .navigationTitle("Graph settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { embedding = await LinkSuggestionEngine.shared.embeddingName }
        }
    }

    private func section<Content: View>(_ title: String, isOn: Binding<Bool>, color: CardColor, @ViewBuilder content: @escaping () -> Content) -> some View {
        CardSection(color: color) {
            DisclosureGroup(isExpanded: isOn) {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.vertical, 8)
            } label: {
                TitleChip(title, tint: color.bright)
            }
            .tint(Theme.ink)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, percent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                Text(percent ? value.wrappedValue.percent : value.wrappedValue.formatted(.number.precision(.fractionLength(range.upperBound > 20 ? 0 : 1))))
                    .font(Theme.figure(.subheadline)).foregroundStyle(Theme.muted)
            }
            Slider(value: value, in: range).tint(Theme.ink).accessibilityLabel(title)
        }
    }
}
