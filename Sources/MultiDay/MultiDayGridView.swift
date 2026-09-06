import UIKit

/// The background of the multi-day timeline: hour rules across the full width, a separator
/// between each day, and a faint wash behind today's and the weekend's columns.
///
/// It is only as big as the viewport and draws relative to the scroll offset rather than
/// living inside the scroll view. A canvas spanning the whole date range would be tens of
/// thousands of points wide — far past the maximum texture a `CALayer` can be backed by, so
/// the rules would simply stop appearing once you scrolled far enough.
///
/// Everything here is a solid-colour `CALayer` that gets *moved*, never a `draw(_:)` that gets
/// re-run. The drawn version re-rasterised a viewport-sized bitmap — roughly 1200×2400 pixels
/// of hour rules, separators and column washes — on the CPU for every frame of every scroll,
/// which is the single most expensive thing the view used to do. Solid-colour layers with no
/// contents carry no backing store at all: a frame of scrolling is now a handful of origin
/// changes.
final class MultiDayGridView: UIView {

    var style = MultiDayStyle() {
        didSet { applyColors() }
    }
    var timelineStyle = TimelineStyle() {
        didSet { rebuildHourRules() }
    }

    /// Where the day columns begin, i.e. the width reserved for the floating hour gutter.
    var leadingInset: Double = 53 { didSet { setNeedsLayout() } }
    var dayWidth: Double = 0 { didSet { setNeedsLayout() } }
    var numberOfDays: Int = 0 { didSet { setNeedsLayout() } }
    /// Index of today within the date range, or nil when today is outside it.
    var todayIndex: Int? {
        didSet {
            guard todayIndex != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Answers whether the day at an index falls on a weekend. Asked only about the handful of
    /// columns actually on screen.
    var isWeekend: (Int) -> Bool = { _ in false }

    /// The scroll position the grid is drawing for.
    var contentOffset: CGPoint = .zero {
        didSet {
            guard contentOffset != oldValue else { return }
            reposition()
        }
    }

    /// The 25 hour rules, held in one container that is simply slid up and down. They never
    /// change with horizontal scrolling, so a vertical drag costs one origin change.
    private let hourRules = CALayer()
    private var hourRuleLayers = [CALayer]()

    /// Day separators and column washes, recycled the way the day columns themselves are.
    /// Only the handful on screen exist.
    private let columnDecoration = CALayer()
    private var separators = [CALayer]()
    private var washes = [CALayer]()

    /// What `layoutDecoration` last built, so a frame of scrolling that stays inside the same
    /// window of days only moves layers instead of recolouring them.
    private var decoratedRange: ClosedRange<Int>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.masksToBounds = true
        layer.addSublayer(columnDecoration)
        layer.addSublayer(hourRules)
        rebuildHourRules()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Colours

    /// Layers do not resolve a dynamic `UIColor` the way a `draw(_:)` does, so every colour is
    /// pinned against the current trait collection and re-pinned when the interface style flips.
    private func applyColors() {
        withoutAnimations {
            let separator = timelineStyle.separatorColor.resolved(for: traitCollection).cgColor
            hourRuleLayers.forEach { $0.backgroundColor = separator }
            let daySeparator = style.daySeparatorColor.resolved(for: traitCollection).cgColor
            separators.forEach { $0.backgroundColor = daySeparator }
        }
        // The washes are per-column, so which colour each one wants is decided by the layout.
        decoratedRange = nil
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.userInterfaceStyle != previous?.userInterfaceStyle else { return }
        applyColors()
    }

    // MARK: - Hour rules

    private var hourRulesHeight: Double {
        timelineStyle.verticalInset * 2 + 24 * timelineStyle.verticalDiff
    }

    private func rebuildHourRules() {
        withoutAnimations {
            hourRuleLayers.forEach { $0.removeFromSuperlayer() }
            hourRuleLayers = (0...24).map { _ in
                let rule = CALayer()
                hourRules.addSublayer(rule)
                return rule
            }
        }
        applyColors()
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutAnimations {
            layoutHourRules()
            layoutDecoration()
            reposition()
        }
    }

    private func layoutHourRules() {
        let hairline = 1 / (window?.screen.scale ?? UIScreen.main.scale)
        hourRules.frame = CGRect(x: 0, y: 0, width: bounds.width, height: hourRulesHeight)
        for (hour, rule) in hourRuleLayers.enumerated() {
            rule.frame = CGRect(x: 0,
                                y: timelineStyle.verticalInset + Double(hour) * timelineStyle.verticalDiff,
                                width: bounds.width,
                                height: hairline)
        }
    }

    /// Makes sure a separator and a wash exist for every column that can be seen, with one
    /// either side so nothing is missing at the edge mid-drag.
    private func layoutDecoration() {
        guard dayWidth > 0, numberOfDays > 0, bounds.width > 0 else {
            decoratedRange = nil
            separators.forEach { $0.isHidden = true }
            washes.forEach { $0.isHidden = true }
            return
        }

        let range = visibleRange
        guard decoratedRange != range else { return }
        decoratedRange = range

        let count = range.count + 1  // one more separator than columns: both edges get a line
        while separators.count < count {
            let layer = CALayer()
            columnDecoration.addSublayer(layer)
            separators.append(layer)
        }
        while washes.count < range.count {
            let layer = CALayer()
            // Behind the separators, so a rule is never washed over.
            columnDecoration.insertSublayer(layer, at: 0)
            washes.append(layer)
        }

        let daySeparator = style.daySeparatorColor.resolved(for: traitCollection).cgColor
        for (slot, layer) in separators.enumerated() {
            layer.isHidden = slot >= count
            layer.backgroundColor = daySeparator
        }
        for (slot, layer) in washes.enumerated() {
            guard slot < range.count else {
                layer.isHidden = true
                continue
            }
            let index = range.lowerBound + slot
            let color: UIColor? = index == todayIndex
                ? style.todayColumnBackgroundColor
                : (isWeekend(index) ? style.weekendColumnBackgroundColor : nil)
            layer.isHidden = color == nil
            layer.backgroundColor = color?.resolved(for: traitCollection).cgColor
        }
    }

    /// The columns at least partly on screen, plus one either side.
    private var visibleRange: ClosedRange<Int> {
        let first = max(0, Int(floor(contentOffset.x / dayWidth)) - 1)
        let last = min(numberOfDays - 1, Int(ceil((contentOffset.x + bounds.width) / dayWidth)) + 1)
        return first...max(first, last)
    }

    /// The whole cost of a scrolled frame: slide the rules vertically and the decoration
    /// horizontally, and rebuild the decoration only when the window of days actually changes.
    private func reposition() {
        guard bounds.width > 0 else { return }
        withoutAnimations {
            hourRules.frame.origin.y = -contentOffset.y

            guard dayWidth > 0, numberOfDays > 0 else { return }
            layoutDecoration()
            guard let range = decoratedRange else { return }

            let hairline = 1 / (window?.screen.scale ?? UIScreen.main.scale)
            func x(of index: Int) -> Double {
                leadingInset + Double(index) * dayWidth - contentOffset.x
            }

            for (slot, layer) in separators.enumerated() where !layer.isHidden {
                layer.frame = CGRect(x: x(of: range.lowerBound + slot),
                                     y: 0,
                                     width: hairline,
                                     height: bounds.height)
            }
            for (slot, layer) in washes.enumerated() where !layer.isHidden {
                layer.frame = CGRect(x: x(of: range.lowerBound + slot),
                                     y: 0,
                                     width: dayWidth,
                                     height: bounds.height)
            }
        }
    }

    /// Layer geometry changes carry an implicit quarter-second animation by default, which on a
    /// scroll shows up as the grid lagging behind the columns it is meant to be under.
    private func withoutAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

private extension UIColor {
    /// A dynamic colour pinned against a trait collection. `CALayer` holds a `CGColor`, which
    /// carries no notion of light or dark, so the resolution has to happen here and be redone
    /// whenever the interface style changes.
    func resolved(for traitCollection: UITraitCollection) -> UIColor {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return resolvedColor(with: traitCollection)
        }
        return self
    }
}

/// The hour labels down the leading edge.
///
/// Held outside the scroll view and shifted vertically to match `contentOffset.y`, so it
/// stays pinned while the days slide underneath it. Touches pass straight through to the
/// scroll view behind.
final class MultiDayGutterView: UIView {

    var timelineStyle = TimelineStyle() {
        didSet {
            backgroundColor = timelineStyle.backgroundColor
            setNeedsDisplay()
        }
    }
    var calendar = Calendar.autoupdatingCurrent {
        didSet { regenerateTimeStrings(); setNeedsDisplay() }
    }
    var is24hClock = true { didSet { setNeedsDisplay() } }

    private lazy var _12hTimes: [String] = TimeStringsFactory(calendar).make12hStrings()
    private lazy var _24hTimes: [String] = TimeStringsFactory(calendar).make24hStrings()
    private var times: [String] { is24hClock ? _24hTimes : _12hTimes }

    private func regenerateTimeStrings() {
        let factory = TimeStringsFactory(calendar)
        _12hTimes = factory.make12hStrings()
        _24hTimes = factory.make24hStrings()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .foregroundColor: timelineStyle.timeColor,
            .font: timelineStyle.font,
        ]

        let fontSize = timelineStyle.font.pointSize
        for (hour, time) in times.enumerated() {
            let y = Double(hour) * timelineStyle.verticalDiff + timelineStyle.verticalInset - 7
            let rect = CGRect(x: 2, y: y, width: bounds.width - 8, height: fontSize + 2)
            NSString(string: time).draw(in: rect, withAttributes: attributes)
        }
    }
}

/// The red line across today's column, plus its dot.
///
/// `CurrentTimeIndicator` cannot be reused here: it hard-codes a 53pt leading inset for the
/// time label it draws inside the gutter, and in a multi-day view that label belongs to the
/// shared gutter rather than to any one column.
final class NowLineView: UIView {
    private let line = UIView()
    private let dot = UIView()
    private weak var timer: Timer?

    /// Called each minute so the owner can move the line down the timeline.
    var onTick: (() -> Void)?

    var color: UIColor = SystemColors.systemRed {
        didSet {
            line.backgroundColor = color
            dot.backgroundColor = color
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        line.backgroundColor = color
        dot.backgroundColor = color
        addSubview(line)
        addSubview(dot)
    }

    deinit {
        timer?.invalidate()
    }

    /// The line only ticks while it is on screen, so a calendar left in a background tab is
    /// not holding a timer open.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        timer?.invalidate()
        guard newWindow != nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.onTick?()
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        line.frame = CGRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        dot.frame = CGRect(x: 0, y: bounds.midY - 3, width: 6, height: 6)
        dot.layer.cornerRadius = 3
    }
}
