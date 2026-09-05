import UIKit

public protocol MultiDayTimelineViewDelegate: AnyObject {
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didTapAt date: Date)
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didLongPressAt date: Date)
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didTap eventView: EventView)
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didLongPress eventView: EventView)
    /// Fires as the days slide past, with the leftmost day currently on screen.
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didScrollTo date: Date)
    /// Fires once the scroll settles on a day boundary.
    func multiDayTimeline(_ timeline: MultiDayTimelineView, didSettleOn date: Date)
}

/// A timeline showing several days side by side that scrolls a day at a time.
///
/// The scrolling is the point of this view. `TimelinePagerView` shows one day per
/// `UIPageViewController` page, so widening it to three days would move three days per swipe —
/// Monday–Wednesday, then Thursday–Saturday, and a Wednesday–Friday view would be unreachable.
/// Here the days live on one canvas inside a single scroll view: a drag moves by any number of
/// days and settles on a day boundary, so every window of three consecutive days can be
/// reached, and a flick carries across a week the way Google Calendar does.
///
/// Only the columns near the viewport exist; the rest are recycled through a pool, so the
/// range can be a couple of years wide without paying for it.
///
/// Day columns are laid out left to right. Right-to-left locales get the same order rather
/// than a mirrored one.
public final class MultiDayTimelineView: UIView, UIScrollViewDelegate {

    public weak var dataSource: EventDataSource?
    public weak var delegate: MultiDayTimelineViewDelegate?

    /// How many days are on screen at once.
    public var numberOfVisibleDays: Int = 3 {
        willSet {
            // Read the leading day while the old column width is still in force. By `didSet`
            // the width has changed and the same offset points at a different date.
            pendingScrollDate = firstVisibleDate
        }
        didSet {
            guard numberOfVisibleDays != oldValue else { return }
            if numberOfVisibleDays < 1 {
                numberOfVisibleDays = 1
            }
            rebuildColumns()
            setNeedsLayout()
        }
    }

    /// The scrollable span, in days either side of `anchorDate`. Wide enough that a school
    /// year is reachable by dragging; the columns themselves are recycled, so the cost is a
    /// wider `contentSize` and nothing else.
    public var daysBefore = 400 { didSet { rebuildColumns() } }
    public var daysAfter = 400 { didSet { rebuildColumns() } }

    public private(set) var calendar: Calendar = .autoupdatingCurrent

    /// Day zero of the scrollable range's midpoint. Changing it re-anchors the range.
    public private(set) var anchorDate: Date

    public private(set) var style = TimelineStyle()
    public private(set) var multiDayStyle = MultiDayStyle()

    private let scrollView = UIScrollView()
    private let canvas = UIView()
    private let grid = MultiDayGridView()
    private let gutter = MultiDayGutterView()
    private let nowLine = NowLineView()

    /// Live columns by day index. Everything else is in `pool`.
    private var columns = [Int: DayColumnView]()
    private var pool = [DayColumnView]()

    /// Days in the scrollable range.
    public var numberOfDays: Int { daysBefore + daysAfter + 1 }

    private var totalDays: Int { numberOfDays }

    private var dayWidth: Double {
        let available = bounds.width - style.leadingInset
        guard available > 0 else { return 0 }
        return available / Double(numberOfVisibleDays)
    }

    private var geometry: TimelineGeometry {
        TimelineGeometry(date: anchorDate, calendar: calendar, style: style)
    }

    public var fullHeight: Double { geometry.fullHeight }

    /// The leftmost day currently on screen.
    public var firstVisibleDate: Date {
        date(at: index(forOffset: scrollView.contentOffset.x))
    }

    /// Every day at least partly on screen.
    public var visibleDates: [Date] {
        let first = index(forOffset: scrollView.contentOffset.x)
        return (0..<numberOfVisibleDays).map { date(at: first + $0) }
    }

    public var contentOffset: CGPoint {
        get { scrollView.contentOffset }
        set { scrollView.contentOffset = newValue }
    }

    /// Called whenever the horizontal offset changes, so the header can be kept in step.
    var onHorizontalScroll: ((Double) -> Void)?

    // MARK: - Initialisation

    public init(calendar: Calendar = .autoupdatingCurrent, date: Date = Date()) {
        self.calendar = calendar
        self.anchorDate = date.dateOnly(calendar: calendar)
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        clipsToBounds = true
        backgroundColor = style.backgroundColor

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        // Days always read left to right, so the scroll view must not mirror itself in a
        // right-to-left locale.
        scrollView.semanticContentAttribute = .forceLeftToRight
        addSubview(scrollView)

        // The grid is a sibling behind the scroll view rather than part of its content, so it
        // stays viewport-sized however wide the date range is.
        addSubview(grid)

        scrollView.backgroundColor = .clear
        nowLine.onTick = { [weak self] in
            self?.updateNowLine()
            self?.grid.setNeedsDisplay()
        }
        canvas.addSubview(nowLine)
        scrollView.addSubview(canvas)

        // The gutter sits outside the scroll view and is nudged vertically to follow it, so it
        // stays pinned horizontally while the days slide underneath.
        addSubview(gutter)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        canvas.addGestureRecognizer(tap)
        canvas.addGestureRecognizer(longPress)
    }

    // MARK: - Style

    public func updateStyle(_ newStyle: TimelineStyle, multiDay: MultiDayStyle) {
        style = newStyle
        multiDayStyle = multiDay
        backgroundColor = style.backgroundColor
        scrollView.backgroundColor = style.backgroundColor
        grid.timelineStyle = style
        grid.style = multiDay
        gutter.timelineStyle = style
        gutter.calendar = calendar
        grid.isWeekend = { [weak self] index in
            guard let self else { return false }
            return self.calendar.isDateInWeekend(self.date(at: index))
        }
        nowLine.color = style.timeIndicator.color

        switch style.dateStyle {
        case .twelveHour: gutter.is24hClock = false
        case .twentyFourHour: gutter.is24hClock = true
        case .system: gutter.is24hClock = calendar.locale?.uses24hClock ?? Locale.autoupdatingCurrent.uses24hClock
        }

        columns.values.forEach { $0.style = style }
        setNeedsLayout()
    }

    public func updateCalendar(_ calendar: Calendar) {
        self.calendar = calendar
        gutter.calendar = calendar
        anchorDate = anchorDate.dateOnly(calendar: calendar)
        columns.values.forEach { $0.calendar = calendar }
        rebuildColumns()
    }

    // MARK: - Data

    public func reloadData() {
        for (index, column) in columns {
            column.events = events(for: date(at: index))
        }
        updateNowLine()
        setNeedsLayout()
    }

    private func rebuildColumns() {
        for (_, column) in columns {
            column.removeFromSuperview()
        }
        columns.removeAll()
        pool.removeAll()
        setNeedsLayout()
    }

    private func events(for date: Date) -> [EventDescriptor] {
        guard let dataSource else { return [] }
        let end = calendar.date(byAdding: .day, value: 1, to: date)!
        let day = DateInterval(start: date, end: end)
        return dataSource.eventsForDate(date).filter { $0.dateInterval.intersects(day) }
    }

    // MARK: - Index ⇄ date

    public func date(at index: Int) -> Date {
        calendar.date(byAdding: .day, value: index - daysBefore, to: anchorDate)!
    }

    public func index(of date: Date) -> Int {
        // `startOfDay` rather than `dateOnly`: in a zone where the clocks go forward at
        // midnight there is no 00:00 on that date, and counting from a synthesised one drifts
        // by a day. `startOfDay` gives the first instant that does exist.
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: anchorDate),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days + daysBefore
    }

    /// The leftmost fully-or-partly visible column for a horizontal offset.
    private func index(forOffset x: Double) -> Int {
        guard dayWidth > 0 else { return daysBefore }
        return Int((x / dayWidth).rounded()).clamped(to: 0...(max(0, totalDays - 1)))
    }

    private func offset(forIndex index: Int) -> Double {
        let maximum = max(0, Double(totalDays - numberOfVisibleDays)) * dayWidth
        return (Double(index) * dayWidth).clamped(to: 0...maximum)
    }

    // MARK: - Scrolling

    /// Brings `date` to the leading edge. Any day is reachable, not just every third one.
    public func scroll(to date: Date, animated: Bool) {
        guard dayWidth > 0 else {
            pendingScrollDate = date
            return
        }
        let x = offset(forIndex: index(of: date))
        scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: animated)
        if !animated {
            updateVisibleColumns()
            onHorizontalScroll?(x)
        }
    }

    private var pendingScrollDate: Date?
    private var lastLaidOutDayWidth: Double?

    public func scroll(toHour24 hour: Float, animated: Bool = true) {
        let y = (Double(hour) / 24 * geometry.dayHeight + style.verticalInset - 8)
            .clamped(to: 0...max(0, fullHeight - bounds.height))
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
    }

    /// Snaps to a whole day so columns never come to rest half off screen. The snap is to the
    /// nearest single day, not to a block of `numberOfVisibleDays`, which is what lets a drag
    /// land on any three consecutive days.
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard dayWidth > 0 else { return }
        let target = targetContentOffset.pointee.x
        targetContentOffset.pointee.x = offset(forIndex: Int((target / dayWidth).rounded()))
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        gutter.frame.origin.y = -scrollView.contentOffset.y
        grid.contentOffset = scrollView.contentOffset
        updateVisibleColumns()
        onHorizontalScroll?(scrollView.contentOffset.x)

        let leading = firstVisibleDate
        if lastReportedDate.map({ !calendar.isDate($0, inSameDayAs: leading) }) ?? true {
            lastReportedDate = leading
            delegate?.multiDayTimeline(self, didScrollTo: leading)
        }
    }

    private var lastReportedDate: Date?

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        delegate?.multiDayTimeline(self, didSettleOn: firstVisibleDate)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            delegate?.multiDayTimeline(self, didSettleOn: firstVisibleDate)
        }
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        delegate?.multiDayTimeline(self, didSettleOn: firstVisibleDate)
    }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.userInterfaceStyle != previous?.userInterfaceStyle else { return }
        // `MultiDayGridView` and the gutter resolve their dynamic colours inside `draw(_:)`,
        // so nothing repaints them when the interface style flips.
        grid.setNeedsDisplay()
        gutter.setNeedsDisplay()
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        // A rotation changes `dayWidth`, so the same `contentOffset.x` lands on a different
        // day. `bounds` has already changed by the time this runs, so the day being looked at
        // has to be recovered using the width the offset was actually measured against.
        let previousDayWidth = lastLaidOutDayWidth
        let leadingIndexBeforeLayout: Int? = {
            guard let previousDayWidth, previousDayWidth > 0, previousDayWidth != dayWidth else { return nil }
            return Int((scrollView.contentOffset.x / previousDayWidth).rounded())
                .clamped(to: 0...max(0, totalDays - 1))
        }()
        lastLaidOutDayWidth = dayWidth

        scrollView.frame = bounds

        let bottomInset = Double(window?.safeAreaInsets.bottom ?? safeAreaInsets.bottom)
        if scrollView.contentInset.bottom != bottomInset {
            scrollView.contentInset.bottom = bottomInset
            scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }

        let contentWidth = style.leadingInset + Double(totalDays) * dayWidth
        let contentSize = CGSize(width: contentWidth, height: fullHeight)
        if scrollView.contentSize != contentSize {
            scrollView.contentSize = contentSize
        }
        canvas.frame = CGRect(origin: .zero, size: contentSize)

        if grid.frame != bounds {
            grid.frame = bounds
        }
        grid.leadingInset = style.leadingInset
        grid.dayWidth = dayWidth
        grid.numberOfDays = totalDays
        updateGridHighlights()

        gutter.frame = CGRect(x: 0,
                              y: -scrollView.contentOffset.y,
                              width: style.leadingInset,
                              height: fullHeight)

        if let pendingScrollDate {
            self.pendingScrollDate = nil
            scroll(to: pendingScrollDate, animated: false)
        } else if let leadingIndexBeforeLayout {
            scrollView.contentOffset.x = offset(forIndex: leadingIndexBeforeLayout)
        }

        updateVisibleColumns()
        updateNowLine()
    }

    private func updateGridHighlights() {
        let todayIndex = index(of: Date().dateOnly(calendar: calendar))
        grid.todayIndex = (0..<totalDays).contains(todayIndex) ? todayIndex : nil
        grid.contentOffset = scrollView.contentOffset
    }

    /// Creates the columns near the viewport and recycles the rest.
    private func updateVisibleColumns() {
        guard dayWidth > 0 else { return }

        let offsetX = scrollView.contentOffset.x
        // One column of slack each side so a column is ready before it scrolls into view.
        let first = max(0, Int(floor(offsetX / dayWidth)) - 1)
        let last = min(totalDays - 1, Int(ceil((offsetX + bounds.width) / dayWidth)) + 1)
        guard first <= last else { return }
        let wanted = Set(first...last)

        for (index, column) in columns where !wanted.contains(index) {
            column.removeFromSuperview()
            columns.removeValue(forKey: index)
            pool.append(column)
        }

        for index in wanted {
            let column: DayColumnView
            if let existing = columns[index] {
                column = existing
            } else {
                let day = date(at: index)
                if let recycled = pool.popLast() {
                    recycled.reuse(for: day)
                    column = recycled
                } else {
                    column = DayColumnView(date: day, calendar: calendar)
                }
                column.style = style
                canvas.addSubview(column)
                columns[index] = column
                column.events = events(for: day)
            }
            column.frame = CGRect(x: style.leadingInset + Double(index) * dayWidth,
                                  y: 0,
                                  width: dayWidth,
                                  height: fullHeight)
        }

        updateGridHighlights()
        canvas.bringSubviewToFront(nowLine)
    }

    private func updateNowLine() {
        let now = Date()
        // Recomputed rather than cached, so the line and the "today" wash both follow the date
        // over midnight without the view being reloaded.
        let today = now.dateOnly(calendar: calendar)
        let todayIndex = index(of: today)
        guard (0..<totalDays).contains(todayIndex), dayWidth > 0 else {
            nowLine.isHidden = true
            return
        }
        nowLine.isHidden = false
        let y = TimelineGeometry(date: today, calendar: calendar, style: style).y(for: now)
        nowLine.frame = CGRect(x: style.leadingInset + Double(todayIndex) * dayWidth,
                               y: y - 6,
                               width: dayWidth,
                               height: 12)
    }

    // MARK: - Gestures

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard isInsideColumns(recognizer) else { return }
        let point = recognizer.location(in: canvas)
        if let (_, eventView) = hitEvent(at: point) {
            delegate?.multiDayTimeline(self, didTap: eventView)
        } else if let date = date(atCanvasPoint: point) {
            delegate?.multiDayTimeline(self, didTapAt: date)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, isInsideColumns(recognizer) else { return }
        let point = recognizer.location(in: canvas)
        if let (_, eventView) = hitEvent(at: point) {
            delegate?.multiDayTimeline(self, didLongPress: eventView)
        } else if let date = date(atCanvasPoint: point) {
            delegate?.multiDayTimeline(self, didLongPressAt: date)
        }
    }

    /// Whether a gesture landed on the columns rather than on the hour gutter.
    ///
    /// The gutter floats over the canvas instead of scrolling with it, so once the view is
    /// scrolled a touch on the gutter maps to a canvas position well inside some column. The
    /// only trustworthy answer comes from where the touch is on screen.
    private func isInsideColumns(_ recognizer: UIGestureRecognizer) -> Bool {
        isInsideColumns(recognizer.location(in: self))
    }

    /// - Parameter point: in this view's coordinates, i.e. what is on screen.
    func isInsideColumns(_ point: CGPoint) -> Bool {
        point.x >= style.leadingInset
    }

    private func hitEvent(at point: CGPoint) -> (DayColumnView, EventView)? {
        for (_, column) in columns {
            let converted = canvas.convert(point, to: column)
            if let eventView = column.eventView(at: converted) {
                return (column, eventView)
            }
        }
        return nil
    }

    /// The date and time under a point in canvas coordinates, or nil in the gutter.
    public func date(atCanvasPoint point: CGPoint) -> Date? {
        guard dayWidth > 0, point.x >= style.leadingInset else { return nil }
        let index = Int((point.x - style.leadingInset) / dayWidth)
        guard (0..<totalDays).contains(index) else { return nil }
        let day = date(at: index)
        return TimelineGeometry(date: day, calendar: calendar, style: style).date(forY: point.y)
    }
}
