import UIKit

/// The background of the multi-day timeline: hour rules across the full width, a separator
/// between each day, and a faint wash behind today's and the weekend's columns.
///
/// It is only as big as the viewport and draws relative to the scroll offset rather than
/// living inside the scroll view. A canvas spanning the whole date range would be tens of
/// thousands of points wide — far past the maximum texture a `CALayer` can be backed by, so
/// the rules would simply stop appearing once you scrolled far enough.
final class MultiDayGridView: UIView {

    var style = MultiDayStyle() {
        didSet { setNeedsDisplay() }
    }
    var timelineStyle = TimelineStyle() {
        didSet { setNeedsDisplay() }
    }

    /// Where the day columns begin, i.e. the width reserved for the floating hour gutter.
    var leadingInset: Double = 53 { didSet { setNeedsDisplay() } }
    var dayWidth: Double = 0 { didSet { setNeedsDisplay() } }
    var numberOfDays: Int = 0 { didSet { setNeedsDisplay() } }
    /// Index of today within the date range, or nil when today is outside it.
    var todayIndex: Int? { didSet { setNeedsDisplay() } }

    /// Answers whether the day at an index falls on a weekend. Asked only about the handful of
    /// columns actually on screen.
    var isWeekend: (Int) -> Bool = { _ in false }

    /// The scroll position the grid is drawing for.
    var contentOffset: CGPoint = .zero {
        didSet {
            guard contentOffset != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext(), dayWidth > 0, numberOfDays > 0 else { return }

        let offsetX = contentOffset.x
        let offsetY = contentOffset.y

        // Only the columns that can be seen are worth drawing, with one either side so a
        // separator is never missing at the edge mid-drag.
        let firstIndex = max(0, Int(floor(offsetX / dayWidth)) - 1)
        let lastIndex = min(numberOfDays - 1, Int(ceil((offsetX + bounds.width) / dayWidth)) + 1)
        guard firstIndex <= lastIndex else { return }

        func x(of index: Int) -> Double {
            leadingInset + Double(index) * dayWidth - offsetX
        }

        // Column washes first, so the rules and separators draw over them.
        for index in firstIndex...lastIndex {
            let color: UIColor?
            if index == todayIndex {
                color = style.todayColumnBackgroundColor
            } else if isWeekend(index) {
                color = style.weekendColumnBackgroundColor
            } else {
                color = nil
            }
            guard let color else { continue }
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x(of: index), y: 0, width: dayWidth, height: bounds.height))
        }

        let hairline = 1 / UIScreen.main.scale
        context.setLineWidth(hairline)

        context.setStrokeColor(timelineStyle.separatorColor.cgColor)
        for hour in 0...24 {
            let y = timelineStyle.verticalInset + Double(hour) * timelineStyle.verticalDiff - offsetY
            guard y >= -1, y <= bounds.height + 1 else { continue }
            context.beginPath()
            // Rules run the full width. The gutter floats over the leading edge with an opaque
            // background, so they read as starting where the columns do.
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            context.strokePath()
        }

        context.setStrokeColor(style.daySeparatorColor.cgColor)
        for index in firstIndex...(lastIndex + 1) {
            context.beginPath()
            context.move(to: CGPoint(x: x(of: index), y: 0))
            context.addLine(to: CGPoint(x: x(of: index), y: bounds.height))
            context.strokePath()
        }
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
