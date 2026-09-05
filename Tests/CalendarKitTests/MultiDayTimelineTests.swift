import XCTest
@testable import CalendarKit

/// Locks down what the several-days-at-once view is for.
///
/// The reason it does not just widen `TimelinePagerView`: that view puts one day on each
/// `UIPageViewController` page, so showing three days per page would move three days per
/// swipe. Mon–Wed, then Thu–Sat — and a Wed–Fri view would be unreachable. These tests assert
/// the opposite property: every window of consecutive days can be landed on.
final class MultiDayTimelineTests: XCTestCase {

    private let size = CGSize(width: 402, height: 800)
    private let day = Date(timeIntervalSince1970: 1_772_064_000) // Thursday 26 February 2026
    private var calendar: Calendar { .current }

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: self.day)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Keeps the window and data source alive for the duration of a test.
    private var window: UIWindow?
    private var source: Source?

    private func makeView(events: [Event] = [], visibleDays: Int = 3) -> MultiDayView {
        let view = MultiDayView(calendar: calendar, date: day)
        let source = Source(events)
        self.source = source
        view.dataSource = source
        view.numberOfVisibleDays = visibleDays

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

    private var dayWidth: Double {
        (size.width - TimelineStyle().leadingInset) / 3
    }

    // MARK: - Any window of days, not batches of three

    /// The property a paged view cannot have: start the view on each day of a week in turn and
    /// every one of them is reachable as the leading column.
    func testEveryDayCanBeTheLeadingColumn() {
        let view = makeView()

        for offset in -3...3 {
            let target = at(0, 0, dayOffset: offset)
            view.move(to: target)
            view.layoutIfNeeded()

            let visible = view.timelineView.visibleDates
            XCTAssertEqual(visible.count, 3)
            XCTAssertTrue(calendar.isDate(visible[0], inSameDayAs: target),
                          "day \(offset) should be reachable as the leading column")
            XCTAssertTrue(calendar.isDate(visible[1], inSameDayAs: calendar.date(byAdding: .day, value: 1, to: target)!))
            XCTAssertTrue(calendar.isDate(visible[2], inSameDayAs: calendar.date(byAdding: .day, value: 2, to: target)!))
        }
    }

    /// Dragging settles on a whole day, so a column never comes to rest half off screen.
    func testDraggingSnapsToADayBoundary() {
        let view = makeView()
        let scrollView = UIScrollView()

        // Let go two-thirds of the way through a day: it should settle on the next one.
        var target = CGPoint(x: dayWidth * 4.7, y: 0)
        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView, withVelocity: .zero, targetContentOffset: $0)
        }
        XCTAssertEqual(target.x, dayWidth * 5, accuracy: 0.01,
                       "the scroll must come to rest on a day boundary")
    }

    /// The snap is to the nearest *single* day, so a flick can carry across a week. Rounding to
    /// the nearest multiple of three would be the paged behaviour this view exists to avoid.
    func testAFlickCanCrossManyDaysAndStillLandOnAnyOfThem() {
        let view = makeView()
        let scrollView = UIScrollView()

        for days in [1, 2, 4, 5, 7, 11] {
            var target = CGPoint(x: dayWidth * (Double(days) + 0.2), y: 0)
            withUnsafeMutablePointer(to: &target) {
                view.timelineView.scrollViewWillEndDragging(scrollView, withVelocity: CGPoint(x: 2, y: 0), targetContentOffset: $0)
            }
            XCTAssertEqual(target.x, dayWidth * Double(days), accuracy: 0.01,
                           "a flick across \(days) days must land on day \(days), not on a multiple of the visible count")
        }
    }

    /// Moving on by one day shifts the window by one day — the whole point of the exercise.
    func testMovingOnByOneDayShiftsTheWindowByOneDay() {
        let view = makeView()
        view.move(to: day)
        view.layoutIfNeeded()
        let before = view.timelineView.visibleDates

        view.move(to: calendar.date(byAdding: .day, value: 1, to: day)!)
        view.layoutIfNeeded()
        let after = view.timelineView.visibleDates

        XCTAssertTrue(calendar.isDate(after[0], inSameDayAs: before[1]),
                      "the second day of the old window becomes the first of the new one")
        XCTAssertTrue(calendar.isDate(after[1], inSameDayAs: before[2]))
    }

    // MARK: - Columns

    /// Only what is near the viewport is built, so a two-year range costs a handful of views.
    func testColumnsAreRecycledRatherThanBuiltForTheWholeRange() {
        let view = makeView(events: schoolWeek())

        var counts = [Int]()
        for offset in stride(from: -100, through: 100, by: 25) {
            view.move(to: at(0, 0, dayOffset: offset))
            view.layoutIfNeeded()
            counts.append(columnCount(in: view))
        }

        XCTAssertLessThanOrEqual(counts.max() ?? 0, 3 + 4,
                                 "at most the visible days plus a little slack should exist at once")
        XCTAssertGreaterThanOrEqual(counts.min() ?? 0, 3,
                                    "the visible days must always be built")
    }

    private func columnCount(in view: MultiDayView) -> Int {
        func columns(_ view: UIView) -> Int {
            view.subviews.reduce(view is DayColumnView ? 1 : 0) { $0 + columns($1) }
        }
        return columns(view.timelineView)
    }

    /// A column shows the day it was asked for, not whatever day it was recycled from.
    func testRecycledColumnsShowTheirNewDay() {
        let view = makeView(events: schoolWeek())
        view.move(to: at(0, 0, dayOffset: 40))
        view.layoutIfNeeded()
        view.move(to: day)
        view.layoutIfNeeded()

        let dates = collectColumns(in: view.timelineView).map(\.date)
        let expected = view.timelineView.visibleDates
        for date in expected {
            XCTAssertTrue(dates.contains { calendar.isDate($0, inSameDayAs: date) },
                          "a column for \(date) should be present after scrolling back")
        }
    }

    private func collectColumns(in view: UIView) -> [DayColumnView] {
        view.subviews.flatMap { subview -> [DayColumnView] in
            (subview as? DayColumnView).map { [$0] } ?? collectColumns(in: subview)
        }
    }

    // MARK: - Events land on the same grid as the single-day view

    /// A multi-day column and a `TimelineView` must place the same event at the same height, or
    /// switching between the two views would nudge every lesson.
    func testAColumnPlacesEventsAtTheSameHeightAsTheSingleDayView() {
        let events = schoolDay()

        let timeline = TimelineView()
        timeline.date = day
        timeline.frame = CGRect(x: 0, y: 0, width: 320, height: timeline.fullHeight)
        timeline.layoutAttributes = events.map(EventLayoutAttributes.init)
        timeline.layoutIfNeeded()

        let column = DayColumnView(date: day, calendar: calendar)
        column.frame = CGRect(x: 0, y: 0, width: 320 - TimelineStyle().leadingInset, height: timeline.fullHeight)
        column.events = events
        column.layoutIfNeeded()

        let timelineTops = frames(in: timeline).sorted { $0.key < $1.key }
        let columnTops = frames(in: column).sorted { $0.key < $1.key }

        XCTAssertEqual(timelineTops.count, columnTops.count)
        for (single, multi) in zip(timelineTops, columnTops) {
            XCTAssertEqual(single.value.minY, multi.value.minY, accuracy: 0.01,
                           "\(single.key) must sit at the same height in both views")
            XCTAssertEqual(single.value.height, multi.value.height, accuracy: 0.01,
                           "\(single.key) must be the same height in both views")
        }
    }

    private func frames(in view: UIView) -> [String: CGRect] {
        var result = [String: CGRect]()
        for eventView in view.subviews.compactMap({ $0 as? EventView }) {
            if let event = eventView.descriptor as? Event {
                result[event.text] = eventView.frame
            }
        }
        return result
    }

    /// All-day events belong in the header, where they stay put. A column that drew them would
    /// give a whole-day excursion a 24-hour-tall block and bury the lessons behind it.
    func testAColumnLeavesAllDayEventsToTheHeader() {
        let camp = event("Year 9 Camp", at(0), at(23, 59))
        camp.isAllDay = true

        let column = DayColumnView(date: day, calendar: calendar)
        column.frame = CGRect(x: 0, y: 0, width: 200, height: 1220)
        column.events = [camp] + schoolDay()
        column.layoutIfNeeded()

        let titles = Set(frames(in: column).keys)
        XCTAssertFalse(titles.contains("Year 9 Camp"), "an all-day event must not be drawn on the timeline")
        XCTAssertTrue(titles.contains("Period 1"), "timed events on the same day must still be drawn")
    }

    /// The header takes its all-day events from the same data source the timeline uses.
    func testTheHeaderShowsAllDayEvents() {
        let camp = event("Year 9 Camp", at(0), at(23, 59))
        camp.isAllDay = true
        let view = makeView(events: [camp] + schoolDay())
        view.move(to: day)
        view.layoutIfNeeded()

        XCTAssertGreaterThan(view.headerView.allDayRows, 0,
                             "the header should make room for the all-day event")
        XCTAssertGreaterThan(view.headerView.preferredHeight, MultiDayStyle.headerBaseHeight,
                             "and grow to fit it")
    }

    /// A day with nothing all-day must not pay for an empty strip.
    func testTheHeaderStaysCompactWithoutAllDayEvents() {
        let view = makeView(events: schoolDay())
        view.move(to: day)
        view.layoutIfNeeded()

        XCTAssertEqual(view.headerView.allDayRows, 0)
        XCTAssertEqual(view.headerView.preferredHeight, MultiDayStyle.headerBaseHeight, accuracy: 0.01)
    }

    // MARK: - Fixtures

    private func event(_ title: String, _ from: Date, _ to: Date) -> Event {
        let event = Event()
        event.text = title
        event.dateInterval = DateInterval(start: from, end: to)
        return event
    }

    private func schoolDay() -> [Event] {
        [
            event("Period 1", at(9), at(10)),
            event("Period 2", at(10), at(11)),
            event("Recess", at(11), at(11, 20)),
        ]
    }

    private func schoolWeek() -> [Event] {
        (-3...3).flatMap { offset in
            [event("Period 1", at(9, 0, dayOffset: offset), at(10, 0, dayOffset: offset))]
        }
    }

    private final class Source: EventDataSource {
        private let events: [Event]
        init(_ events: [Event]) { self.events = events }
        func eventsForDate(_ date: Date) -> [EventDescriptor] {
            events.filter { Calendar.current.isDate($0.dateInterval.start, inSameDayAs: date) }
        }
    }
}
