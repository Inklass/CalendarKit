import UIKit

public protocol MultiDayViewDelegate: AnyObject {
    func multiDayViewDidSelectEventView(_ eventView: EventView)
    func multiDayViewDidLongPressEventView(_ eventView: EventView)
    func multiDayView(_ multiDayView: MultiDayView, didTapTimelineAt date: Date)
    func multiDayView(_ multiDayView: MultiDayView, didLongPressTimelineAt date: Date)
    /// The leftmost day changed, either mid-drag or after a programmatic move.
    func multiDayView(_ multiDayView: MultiDayView, didMoveTo date: Date)
}

public extension MultiDayViewDelegate {
    func multiDayViewDidSelectEventView(_ eventView: EventView) {}
    func multiDayViewDidLongPressEventView(_ eventView: EventView) {}
    func multiDayView(_ multiDayView: MultiDayView, didTapTimelineAt date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didLongPressTimelineAt date: Date) {}
    func multiDayView(_ multiDayView: MultiDayView, didMoveTo date: Date) {}
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
        syncHeader()
    }

    /// Brings `date` to the leading column. Unlike a paged view, any day can be first — the
    /// three days on screen are not locked to a fixed grouping.
    public func move(to date: Date, animated: Bool = false) {
        timelineView.scroll(to: date, animated: animated)
        syncHeader()
        delegate?.multiDayView(self, didMoveTo: timelineView.firstVisibleDate)
    }

    public func scrollTo(hour24: Float, animated: Bool = true) {
        timelineView.scroll(toHour24: hour24, animated: animated)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaLayoutGuide.layoutFrame
        let headerHeight = isHeaderViewVisible ? headerView.preferredHeight : 0

        headerView.frame = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: headerHeight)
        timelineView.frame = CGRect(x: safe.minX,
                                    y: safe.minY + headerHeight,
                                    width: safe.width,
                                    height: max(0, bounds.maxY - safe.minY - headerHeight))
        syncHeader()
    }

    /// Feeds the header the days the timeline is showing, plus a day of slack each side, and
    /// the sub-day part of the scroll offset so the two move together.
    private func syncHeader() {
        guard isHeaderViewVisible, timelineView.bounds.width > 0 else { return }

        let dayWidth = (timelineView.bounds.width - style.timeline.leadingInset) / Double(numberOfVisibleDays)
        guard dayWidth > 0 else { return }

        let offsetX = timelineView.contentOffset.x
        let cellCount = numberOfVisibleDays + 2
        // Clamped to the scrollable range so a rubber-band bounce past either end does not put
        // a heading over empty space. The fraction is measured from the clamped index, so the
        // headings still slide with the bounce.
        let firstIndex = Int(floor(offsetX / dayWidth))
            .clamped(to: 0...max(0, timelineView.numberOfDays - cellCount))
        let fractional = offsetX - Double(firstIndex) * dayWidth
        let dates = (0..<cellCount).map { timelineView.date(at: firstIndex + $0) }

        let heightChanged = headerView.show(dates: dates,
                                            dayWidth: dayWidth,
                                            leadingInset: style.timeline.leadingInset,
                                            fractionalOffset: fractional)
        if heightChanged {
            setNeedsLayout()
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
