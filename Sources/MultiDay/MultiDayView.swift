import UIKit

public protocol MultiDayViewDelegate: AnyObject {
    func multiDayViewDidSelectEventView(_ eventView: EventView)
    func multiDayViewDidLongPressEventView(_ eventView: EventView)
    func multiDayView(_ multiDayView: MultiDayView, didTapTimelineAt date: Date)
    func multiDayView(_ multiDayView: MultiDayView, didLongPressTimelineAt date: Date)
    /// The leftmost day changed, either mid-drag or after a programmatic move.
    func multiDayView(_ multiDayView: MultiDayView, didMoveTo date: Date)
    /// An all-day event in the header was tapped. They sit outside the timeline, so a tap on
    /// one never reaches `multiDayViewDidSelectEventView`.
    func multiDayView(_ multiDayView: MultiDayView, didSelectAllDayEvent event: EventDescriptor, on date: Date)
    /// A day's heading was tapped, rather than one of the events under it.
    func multiDayView(_ multiDayView: MultiDayView, didSelectDayHeading date: Date)
}

public extension MultiDayViewDelegate {
    func multiDayViewDidSelectEventView(_ eventView: EventView) {}
    func multiDayViewDidLongPressEventView(_ eventView: EventView) {}
    func multiDayView(_ multiDayView: MultiDayView, didTapTimelineAt date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didLongPressTimelineAt date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didMoveTo date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didSelectAllDayEvent event: EventDescriptor, on date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didSelectDayHeading date: Date) {}
}

/// Several days side by side, scrolling a day at a time — the multi-day counterpart to
/// `DayView`.
///
/// It takes the same `EventDataSource` as `DayView`, so a screen already feeding one can show
/// the other without touching how it loads events.
///
/// Editing (drag to move, drag to resize) is deliberately not wired up here. Dragging an event
/// between columns means re-dating it as well as re-timing it, and that deserves its own piece
/// of work rather than a half-answer bolted on.
public class MultiDayView: UIView, MultiDayTimelineViewDelegate {

    public weak var dataSource: EventDataSource? {
        get { timelineView.dataSource }
        set {
            timelineView.dataSource = newValue
            headerView.allDayEventsProvider = { [weak newValue] date in
                (newValue?.eventsForDate(date) ?? []).filter(\.isAllDay)
            }
        }
    }

    public weak var delegate: MultiDayViewDelegate?

    public let headerView: MultiDayHeaderView
    public let timelineView: MultiDayTimelineView

    /// How long the all-day strip takes to open or close. Short enough to keep up with a drag,
    /// long enough that the timetable underneath is seen to move rather than to jump.
    private let allDayStripDuration: TimeInterval = 0.22

    /// Days on screen at once. Three by default, which is what fits a phone without the
    /// columns becoming too narrow to read a subject name in.
    public var numberOfVisibleDays: Int {
        get { timelineView.numberOfVisibleDays }
        set {
            timelineView.numberOfVisibleDays = newValue
            setNeedsLayout()
        }
    }

    public var isHeaderViewVisible = true {
        didSet {
            headerView.isHidden = !isHeaderViewVisible
            setNeedsLayout()
        }
    }

    public var calendar: Calendar {
        didSet {
            timelineView.updateCalendar(calendar)
            headerView.updateCalendar(calendar)
        }
    }

    private var style = CalendarStyle()

    public init(calendar: Calendar = .autoupdatingCurrent, date: Date = Date()) {
        self.calendar = calendar
        self.headerView = MultiDayHeaderView(calendar: calendar)
        self.timelineView = MultiDayTimelineView(calendar: calendar, date: date)
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        addSubview(timelineView)
        addSubview(headerView)
        timelineView.delegate = self
        timelineView.onHorizontalScroll = { [weak self] _ in
            self?.syncHeader()
        }

        headerView.onSelectAllDayEvent = { [weak self] event, date in
            guard let self else { return }
            self.timelineView.emitSelectionTap()
            self.delegate?.multiDayView(self, didSelectAllDayEvent: event, on: date)
        }
        headerView.onSelectDay = { [weak self] date in
            guard let self else { return }
            self.delegate?.multiDayView(self, didSelectDayHeading: date)
        }
        headerView.onToggleExpansion = { [weak self] in
            guard let self else { return }
            self.timelineView.emitSelectionTap()
            self.syncHeader(animateHeightChanges: true)
        }
        updateStyle(style)
    }

    public func updateStyle(_ newStyle: CalendarStyle) {
        style = newStyle
        headerView.updateStyle(newStyle.header, multiDay: newStyle.multiDay)
        timelineView.updateStyle(newStyle.timeline, multiDay: newStyle.multiDay)
        setNeedsLayout()
    }

    public func reloadData() {
        timelineView.reloadData()
        // The days on screen have not changed, but what is on them has.
        headerView.invalidateConfiguration()
        syncHeader(animateHeightChanges: !timelineView.isUserScrolling)
    }

    /// Brings `date` to the leading column. Unlike a paged view, any day can be first — the
    /// three days on screen are not locked to a fixed grouping.
    public func move(to date: Date, animated: Bool = false) {
        timelineView.scroll(to: date, animated: animated)
        // An unanimated move is a landing, not a transition — the all-day strip should already
        // be the right height when the day appears rather than easing into it afterwards.
        syncHeader(animateHeightChanges: animated)
        delegate?.multiDayView(self, didMoveTo: timelineView.firstVisibleDate)
    }

    public func scrollTo(hour24: Float, animated: Bool = true) {
        timelineView.scroll(toHour24: hour24, animated: animated)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // The header decides its own height from the days it is about to show, so it has to be
        // configured *before* anything is given a frame. Configuring it afterwards left it a
        // frame behind on every window whose all-day count differed: the strip was laid out at
        // the outgoing height, its chips clipped to nothing, and only corrected on the next
        // pass — which on a fast scroll is a visible flicker at the top of the screen.
        configureHeader()
        layoutHeaderAndTimeline()
        positionHeader()
    }

    /// Places the header and the timeline for the header's current height.
    private func layoutHeaderAndTimeline() {
        let safe = safeAreaLayoutGuide.layoutFrame
        let headerHeight = isHeaderViewVisible ? headerView.preferredHeight : 0

        headerView.frame = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: headerHeight)
        timelineView.frame = CGRect(x: safe.minX,
                                    y: safe.minY + headerHeight,
                                    width: safe.width,
                                    height: max(0, bounds.maxY - safe.minY - headerHeight))
    }

    private var dayWidth: Double {
        let available = safeAreaLayoutGuide.layoutFrame.width - style.timeline.leadingInset
        guard available > 0, numberOfVisibleDays > 0 else { return 0 }
        return available / Double(numberOfVisibleDays)
    }

    /// Feeds the header the days the timeline is showing, plus a day of slack each side, and
    /// the sub-day part of the scroll offset so the two move together.
    ///
    /// - Parameter animateHeightChanges: whether a change in the all-day strip's height should
    ///   be eased in. A drag animates, so the timetable is seen to make room rather than
    ///   jumping down by a row the moment a camp scrolls into view.
    private func syncHeader(animateHeightChanges: Bool = true) {
        guard isHeaderViewVisible, dayWidth > 0 else { return }
        let window = headerWindow()
        if configureHeader(window) {
            applyHeaderHeight(animated: animateHeightChanges)
        }
        positionHeader(window)
    }

    /// Rebuilds the headings when the window of days has moved.
    ///
    /// - Returns: true when the header now wants a different height.
    @discardableResult
    private func configureHeader(_ window: HeaderWindow? = nil) -> Bool {
        guard isHeaderViewVisible, dayWidth > 0 else { return false }
        let window = window ?? headerWindow()
        // The window begins at the leading column and runs two days past the trailing one, so a
        // heading is ready before it scrolls in. The first `numberOfVisibleDays` of them are the
        // days a reader would say they are looking at, and they are what the month follows.
        let visible = Array(window.dates.prefix(numberOfVisibleDays))
        return headerView.configure(dates: window.dates, visible: visible)
    }

    private func positionHeader(_ window: HeaderWindow? = nil) {
        guard isHeaderViewVisible, dayWidth > 0 else { return }
        headerView.position(dayWidth: dayWidth,
                            leadingInset: style.timeline.leadingInset,
                            fractionalOffset: (window ?? headerWindow()).fractionalOffset)
    }

    private struct HeaderWindow {
        let dates: [Date]
        let fractionalOffset: Double
    }

    /// The days the header should carry, and how far the first of them sits left of the
    /// timeline's leading edge.
    ///
    /// Clamped to the scrollable range so a rubber-band bounce past either end does not put a
    /// heading over empty space. The fraction is measured from the clamped index, so the
    /// headings still slide with the bounce.
    private func headerWindow() -> HeaderWindow {
        let offsetX = timelineView.contentOffset.x
        let cellCount = numberOfVisibleDays + 2
        let firstIndex = Int(floor(offsetX / dayWidth))
            .clamped(to: 0...max(0, timelineView.numberOfDays - cellCount))
        let fractional = offsetX - Double(firstIndex) * dayWidth
        let dates = (0..<cellCount).map { timelineView.date(at: firstIndex + $0) }
        return HeaderWindow(dates: dates, fractionalOffset: fractional)
    }

    private func applyHeaderHeight(animated: Bool) {
        guard animated else {
            layoutHeaderAndTimeline()
            return
        }
        UIView.animate(withDuration: allDayStripDuration,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.layoutHeaderAndTimeline()
            self.positionHeader()
        }
    }

    // MARK: - MultiDayTimelineViewDelegate

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didTapAt date: Date) {
        delegate?.multiDayView(self, didTapTimelineAt: date)
    }

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didLongPressAt date: Date) {
        delegate?.multiDayView(self, didLongPressTimelineAt: date)
    }

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didTap eventView: EventView) {
        delegate?.multiDayViewDidSelectEventView(eventView)
    }

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didLongPress eventView: EventView) {
        delegate?.multiDayViewDidLongPressEventView(eventView)
    }

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didScrollTo date: Date) {
        syncHeader()
    }

    public func multiDayTimeline(_ timeline: MultiDayTimelineView, didSettleOn date: Date) {
        delegate?.multiDayView(self, didMoveTo: date)
    }
}
