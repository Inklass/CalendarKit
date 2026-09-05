import XCTest
@testable import CalendarKit

/// The awkward cases: rotation, daylight saving, midnight, the ends of the range, and the
/// hour gutter that floats over the columns.
final class MultiDayEdgeCaseTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_772_064_000) // Thursday 26 February 2026
    private var window: UIWindow?
    private var source: Source?

    private func makeView(events: [Event] = [],
                          calendar: Calendar = .current,
                          size: CGSize = CGSize(width: 402, height: 800)) -> MultiDayView {
        let view = MultiDayView(calendar: calendar, date: day)
        let source = Source(events, calendar: calendar)
        self.source = source
        view.dataSource = source

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view)
        view.frame = CGRect(origin: .zero, size: size)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        self.window = window
        return view
    }

    private func resize(_ view: MultiDayView, to size: CGSize) {
        window?.frame = CGRect(origin: .zero, size: size)
        view.frame = CGRect(origin: .zero, size: size)
        window?.layoutIfNeeded()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - The view changing size

    /// Rotating changes the width of a day, so the same scroll offset would land on a
    /// different date. The day you were looking at has to stay put.
    func testRotationKeepsTheSameLeadingDay() {
        let view = makeView()
        let target = Calendar.current.date(byAdding: .day, value: 5, to: day)!
        view.move(to: target)
        view.layoutIfNeeded()
        XCTAssertTrue(Calendar.current.isDate(view.timelineView.firstVisibleDate, inSameDayAs: target))

        resize(view, to: CGSize(width: 874, height: 402))

        XCTAssertTrue(Calendar.current.isDate(view.timelineView.firstVisibleDate, inSameDayAs: target),
                      "the leading day must survive a rotation")
    }

    /// Same requirement when the column count changes rather than the width.
    func testChangingTheNumberOfVisibleDaysKeepsTheLeadingDay() {
        let view = makeView()
        let target = Calendar.current.date(byAdding: .day, value: 5, to: day)!
        view.move(to: target)
        view.layoutIfNeeded()

        view.numberOfVisibleDays = 5
        view.layoutIfNeeded()

        XCTAssertTrue(Calendar.current.isDate(view.timelineView.firstVisibleDate, inSameDayAs: target),
                      "widening the window must not move the day you were looking at")
        XCTAssertEqual(view.timelineView.visibleDates.count, 5)
    }

    /// A zero-sized view is laid out before it has a frame; it must not divide by zero.
    func testAZeroSizedViewIsHarmless() {
        let view = makeView(size: CGSize(width: 0, height: 0))
        view.layoutIfNeeded()
        view.reloadData()
        XCTAssertEqual(view.timelineView.visibleDates.count, view.numberOfVisibleDays)
    }

    // MARK: - Daylight saving

    /// Adding days and counting days have to agree, or the columns drift by one after a
    /// clock change. Sydney's clocks go back on 5 April 2026, so the range spans it.
    func testDayIndexingSurvivesADaylightSavingChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let view = makeView(calendar: calendar)

        for index in (view.timelineView.numberOfDays / 2 - 20)...(view.timelineView.numberOfDays / 2 + 20) {
            let date = view.timelineView.date(at: index)
            XCTAssertEqual(view.timelineView.index(of: date), index,
                           "index ⇄ date must round-trip across the daylight saving change")
        }
    }

    /// The same, in a zone where the clocks go forward at midnight so the date has no 00:00.
    func testDayIndexingSurvivesAMissingMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        let view = makeView(calendar: calendar)

        for index in (view.timelineView.numberOfDays / 2 - 200)...(view.timelineView.numberOfDays / 2 + 200) {
            let date = view.timelineView.date(at: index)
            XCTAssertEqual(view.timelineView.index(of: date), index,
                           "a date without a midnight must still count as one day")
        }
    }

    // MARK: - Midnight

    /// An event running past midnight belongs to both days: the tail hangs below the first
    /// column and the head sits above the top of the second.
    func testAnEventCrossingMidnightIsDrawnInBothDays() {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day)!
        let end = calendar.date(byAdding: .hour, value: 4, to: start)!

        let event = Event()
        event.text = "Astronomy night"
        event.dateInterval = DateInterval(start: start, end: end)

        let first = DayColumnView(date: day, calendar: calendar)
        first.frame = CGRect(x: 0, y: 0, width: 200, height: 1220)
        first.events = [event]
        first.layoutIfNeeded()

        let second = DayColumnView(date: calendar.date(byAdding: .day, value: 1, to: day)!, calendar: calendar)
        second.frame = CGRect(x: 0, y: 0, width: 200, height: 1220)
        second.events = [event]
        second.layoutIfNeeded()

        let firstFrame = eventFrame(in: first)
        let secondFrame = eventFrame(in: second)

        XCTAssertNotNil(firstFrame)
        XCTAssertNotNil(secondFrame)
        XCTAssertGreaterThan(firstFrame!.maxY, 1200, "the tail should run off the bottom of the first day")
        XCTAssertLessThan(secondFrame!.minY, 0, "the head should start above the top of the next day")
    }

    private func eventFrame(in view: UIView) -> CGRect? {
        view.subviews.compactMap { $0 as? EventView }.first?.frame
    }

    // MARK: - The ends of the range

    /// Both ends of the scrollable range must be reachable and must not overscroll into
    /// nothing.
    func testTheFirstAndLastDaysOfTheRangeAreReachable() {
        let view = makeView()
        let timeline = view.timelineView

        view.move(to: timeline.date(at: 0))
        view.layoutIfNeeded()
        XCTAssertEqual(timeline.contentOffset.x, 0, accuracy: 0.01)
        XCTAssertTrue(Calendar.current.isDate(timeline.firstVisibleDate, inSameDayAs: timeline.date(at: 0)))

        let last = timeline.date(at: timeline.numberOfDays - 1)
        view.move(to: last)
        view.layoutIfNeeded()
        let visible = timeline.visibleDates
        XCTAssertTrue(visible.contains { Calendar.current.isDate($0, inSameDayAs: last) },
                      "the last day of the range must end up on screen")
    }

    /// Asking for a date beyond the range settles at the edge rather than scrolling into
    /// empty space.
    func testScrollingBeyondTheRangeClampsToTheEdge() {
        let view = makeView()
        let timeline = view.timelineView

        view.move(to: Calendar.current.date(byAdding: .year, value: 10, to: day)!)
        view.layoutIfNeeded()

        let maximum = timeline.contentOffset.x
        XCTAssertLessThanOrEqual(maximum, max(0, view.frame.width * Double(timeline.numberOfDays)))
        XCTAssertGreaterThanOrEqual(timeline.contentOffset.x, 0)
        XCTAssertFalse(timeline.contentOffset.x.isNaN)
    }

    /// A single-day range is degenerate but must not crash or produce a negative offset.
    func testASingleDayRangeIsHandled() {
        let view = makeView()
        view.timelineView.daysBefore = 0
        view.timelineView.daysAfter = 0
        view.layoutIfNeeded()

        XCTAssertEqual(view.timelineView.numberOfDays, 1)
        view.move(to: day)
        view.layoutIfNeeded()
        XCTAssertEqual(view.timelineView.contentOffset.x, 0, accuracy: 0.01)
    }

    // MARK: - The floating gutter

    /// The gutter is drawn over the canvas rather than scrolling with it, so a touch on it maps
    /// to a canvas position deep inside some column. Hit testing has to use the position on
    /// screen or tapping an hour label would open whatever lesson happened to be underneath.
    func testATouchOnTheHourGutterIsNotATouchOnAColumn() {
        let view = makeView()
        view.move(to: Calendar.current.date(byAdding: .day, value: 30, to: day)!)
        view.layoutIfNeeded()

        let inset = TimelineStyle().leadingInset
        XCTAssertFalse(view.timelineView.isInsideColumns(CGPoint(x: inset - 1, y: 400)),
                       "a touch on the gutter is not a touch on a column, however far we have scrolled")
        XCTAssertTrue(view.timelineView.isInsideColumns(CGPoint(x: inset + 1, y: 400)))
    }

    /// The same rule expressed against the canvas: the gutter strip has no date.
    func testTheGutterHasNoDate() {
        let view = makeView()
        XCTAssertNil(view.timelineView.date(atCanvasPoint: CGPoint(x: 10, y: 400)))
        XCTAssertNotNil(view.timelineView.date(atCanvasPoint: CGPoint(x: 100, y: 400)))
    }

    // MARK: - Data

    /// No data source at all is a normal state before the first load.
    func testNoDataSourceIsHarmless() {
        let view = MultiDayView(calendar: .current, date: day)
        view.frame = CGRect(x: 0, y: 0, width: 402, height: 800)
        view.layoutIfNeeded()
        view.reloadData()
        XCTAssertEqual(view.timelineView.visibleDates.count, 3)
    }

    /// More all-day events than the strip can hold collapse into a count rather than pushing
    /// the timeline off the bottom of the screen.
    func testTheAllDayStripIsCapped() {
        var events = [Event]()
        for index in 0..<10 {
            let event = Event()
            event.text = "Excursion \(index)"
            event.isAllDay = true
            event.dateInterval = DateInterval(start: day, end: day.addingTimeInterval(3600))
            events.append(event)
        }
        let view = makeView(events: events)
        view.move(to: day)
        view.layoutIfNeeded()

        XCTAssertEqual(view.headerView.allDayRows, MultiDayStyle.maximumAllDayRows,
                       "the strip should stop growing at its cap")
        XCTAssertLessThanOrEqual(view.headerView.preferredHeight,
                                 MultiDayStyle.headerBaseHeight
                                    + Double(MultiDayStyle.maximumAllDayRows) * MultiDayStyle.allDayRowHeight)
    }

    private final class Source: EventDataSource {
        private let events: [Event]
        private let calendar: Calendar
        init(_ events: [Event], calendar: Calendar) {
            self.events = events
            self.calendar = calendar
        }
        func eventsForDate(_ date: Date) -> [EventDescriptor] {
            events.filter { calendar.isDate($0.dateInterval.start, inSameDayAs: date) }
        }
    }
}
