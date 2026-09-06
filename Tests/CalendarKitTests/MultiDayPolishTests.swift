import XCTest
@testable import CalendarKit

/// The things that make the three-day view feel finished rather than merely correct: how a
/// drag settles, what a tap on the header does, when the all-day strip changes height, and
/// what the view is prepared to redo on a frame it does not have to.
///
/// Every test here stands for a defect that was visible on a phone and invisible in the type
/// system.
final class MultiDayPolishTests: XCTestCase {

    private let size = CGSize(width: 402, height: 800)
    /// Thursday 26 February 2026, matching the other multi-day suites.
    private let day = Date(timeIntervalSince1970: 1_772_064_000)
    private var calendar: Calendar { .current }

    private var window: UIWindow?
    private var source: PolishSource?

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: self.day)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func timed(_ title: String, dayOffset: Int, from: Int, to: Int) -> Event {
        let event = Event()
        event.text = title
        event.dateInterval = DateInterval(start: at(from, 0, dayOffset: dayOffset),
                                          end: at(to, 0, dayOffset: dayOffset))
        return event
    }

    private func allDay(_ title: String, dayOffset: Int) -> Event {
        let event = Event()
        event.text = title
        event.isAllDay = true
        event.dateInterval = DateInterval(start: at(0, 0, dayOffset: dayOffset),
                                          end: at(23, 59, dayOffset: dayOffset))
        return event
    }

    private func makeView(events: [Event] = [], visibleDays: Int = 3, on startDay: Date? = nil) -> MultiDayView {
        let view = MultiDayView(calendar: calendar, date: startDay ?? day)
        let source = PolishSource(events)
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

    // MARK: - Settling

    /// One scroll view carries both axes, so a thumb travelling down a day used to wander into
    /// the next one. UIKit will lock a drag to whichever axis it starts on, but only if asked.
    func testAVerticalDragCannotWanderSideways() {
        let view = makeView()
        let scrollView = view.timelineView.subviews.compactMap { $0 as? UIScrollView }.first
        XCTAssertEqual(scrollView?.isDirectionalLockEnabled, true,
                       "reading down a day must not drift into the next one")
    }

    /// A nudge that projects less than half a column used to round back to where it started, so
    /// the flick read as having been ignored. Any deliberate flick moves at least one day.
    func testASmallFlickStillMovesADay() {
        let view = makeView()
        let scrollView = UIScrollView()
        scrollView.contentOffset = CGPoint(x: dayWidth * 4, y: 0)

        // Barely-there projected travel — a fifth of a column — but a real flick to the right.
        var target = CGPoint(x: dayWidth * 4.2, y: 0)
        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView,
                                                        withVelocity: CGPoint(x: 0.9, y: 0),
                                                        targetContentOffset: $0)
        }
        XCTAssertEqual(target.x, dayWidth * 5, accuracy: 0.01,
                       "a flick to the right must advance a day rather than snapping back")
    }

    func testASmallFlickBackwardsAlsoMovesADay() {
        let view = makeView()
        let scrollView = UIScrollView()
        scrollView.contentOffset = CGPoint(x: dayWidth * 4, y: 0)

        var target = CGPoint(x: dayWidth * 3.85, y: 0)
        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView,
                                                        withVelocity: CGPoint(x: -0.9, y: 0),
                                                        targetContentOffset: $0)
        }
        XCTAssertEqual(target.x, dayWidth * 3, accuracy: 0.01,
                       "a flick to the left must go back a day")
    }

    /// A slow release is not a flick, and must still land on whichever day is nearest rather
    /// than being pushed on by the minimum-travel rule.
    func testASlowReleaseSnapsToTheNearestDayWithoutBeingPushedOn() {
        let view = makeView()
        let scrollView = UIScrollView()
        scrollView.contentOffset = CGPoint(x: dayWidth * 4.1, y: 0)

        var target = CGPoint(x: dayWidth * 4.1, y: 0)
        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView,
                                                        withVelocity: CGPoint(x: 0.02, y: 0),
                                                        targetContentOffset: $0)
        }
        XCTAssertEqual(target.x, dayWidth * 4, accuracy: 0.01,
                       "letting go just past a boundary must settle back onto it")
    }

    /// The deceleration rate is chosen per gesture. A horizontal throw wants to settle on its
    /// day promptly; scrolling down a timetable wants the long natural glide, and one rate for
    /// both makes one of them feel wrong.
    func testTheDecelerationRateFollowsTheAxisOfTheGesture() {
        let view = makeView()
        let scrollView = UIScrollView()
        var target = CGPoint(x: dayWidth * 4, y: 0)

        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView,
                                                        withVelocity: CGPoint(x: 2, y: 0.1),
                                                        targetContentOffset: $0)
        }
        XCTAssertEqual(scrollView.decelerationRate, .fast, "a sideways throw settles on its day")

        withUnsafeMutablePointer(to: &target) {
            view.timelineView.scrollViewWillEndDragging(scrollView,
                                                        withVelocity: CGPoint(x: 0.1, y: 2),
                                                        targetContentOffset: $0)
        }
        XCTAssertEqual(scrollView.decelerationRate, .normal, "scrolling down a day keeps its glide")
    }

    // MARK: - All-day events

    /// They live in the header, outside the timeline, so nothing in the timeline's own tap
    /// handling could ever have reached them. Before this they were the only thing on the
    /// screen you could see and not open.
    func testTappingAnAllDayEventReportsIt() {
        let camp = allDay("Year 9 Camp", dayOffset: 1)
        let view = makeView(events: [camp])
        view.layoutIfNeeded()

        let spy = DelegateSpy()
        view.delegate = spy

        XCTAssertTrue(tapFirstChip(in: view), "the day with an all-day event must have a chip")
        XCTAssertIdentical(spy.selectedAllDayEvent as? Event, camp)
        XCTAssertNotNil(spy.selectedAllDayDate)
        XCTAssertTrue(calendar.isDate(spy.selectedAllDayDate!,
                                      inSameDayAs: at(0, 0, dayOffset: 1)),
                      "the event must be reported against the day it was tapped on")
    }

    /// A "+n" that only tells you something is hidden is a dead end. Tapping it opens the strip
    /// out, and the strip is then taller than it was.
    func testTheOverflowChipOpensTheStripAndClosesItAgain() {
        let events = (0..<5).map { allDay("Excursion \($0)", dayOffset: 1) }
        let view = makeView(events: events)
        view.layoutIfNeeded()

        let collapsed = view.headerView.preferredHeight
        XCTAssertEqual(view.headerView.allDayRows, MultiDayStyle.maximumAllDayRows,
                       "five all-day events must collapse to the capped number of rows")

        XCTAssertTrue(tapToggleChip(in: view), "the busiest day must carry the overflow chip")
        view.layoutIfNeeded()

        XCTAssertGreaterThan(view.headerView.preferredHeight, collapsed,
                             "expanding must make room for the events that were hidden")
        XCTAssertTrue(view.headerView.isAllDayExpanded)

        XCTAssertTrue(tapToggleChip(in: view), "the expanded strip must offer a way back")
        view.layoutIfNeeded()
        XCTAssertEqual(view.headerView.preferredHeight, collapsed, accuracy: 0.01,
                       "collapsing must return the timeline the height it lent")
        XCTAssertFalse(view.headerView.isAllDayExpanded)
    }

    /// Expanding is capped too. A day carrying twenty all-day entries must not push the
    /// timetable off the bottom of the screen.
    func testExpandingIsStillCapped() {
        let events = (0..<40).map { allDay("Notice \($0)", dayOffset: 1) }
        let view = makeView(events: events)
        view.layoutIfNeeded()
        XCTAssertTrue(tapToggleChip(in: view))
        view.layoutIfNeeded()

        XCTAssertLessThanOrEqual(view.headerView.allDayRows, MultiDayStyle.maximumExpandedAllDayRows)
    }

    /// Scrolling away from the day that was expanded takes the reason for the expansion with
    /// it, so the strip must close rather than sitting open over days that do not need it.
    func testScrollingToQuieterDaysClosesTheStrip() {
        let events = (0..<5).map { allDay("Excursion \($0)", dayOffset: 0) }
        let view = makeView(events: events)
        view.layoutIfNeeded()
        XCTAssertTrue(tapToggleChip(in: view))
        view.layoutIfNeeded()
        XCTAssertTrue(view.headerView.isAllDayExpanded)

        view.move(to: at(0, 0, dayOffset: 10))
        view.layoutIfNeeded()

        XCTAssertFalse(view.headerView.isAllDayExpanded)
        XCTAssertEqual(view.headerView.allDayRows, 0)
    }

    /// Tapping the date itself, rather than an event under it, brings that day to the front.
    func testTappingADayHeadingReportsTheDay() {
        let view = makeView()
        view.layoutIfNeeded()
        let spy = DelegateSpy()
        view.delegate = spy

        let cell = view.headerView.cells[2]
        view.headerView.handleTap(at: CGPoint(x: cell.frame.midX, y: 20))

        XCTAssertNotNil(spy.selectedHeading)
        XCTAssertTrue(calendar.isDate(spy.selectedHeading!, inSameDayAs: cell.date))
    }

    // MARK: - Header height

    /// The header decides its own height from the days it is about to show, so the owner has to
    /// ask it *before* handing out frames. Doing it the other way round left the strip one
    /// frame behind — laid out at the outgoing height with its chips clipped to nothing, which
    /// on a fast scroll reads as the top of the screen flickering.
    func testTheStripIsTheRightHeightInTheSamePassAsTheDayThatNeedsIt() {
        let view = makeView(events: [allDay("Year 9 Camp", dayOffset: 6)])
        view.layoutIfNeeded()
        XCTAssertEqual(view.headerView.allDayRows, 0, "no all-day events on the opening window")
        let bare = view.timelineView.frame.minY

        // One layout pass, landing on the week that has the camp in it.
        view.move(to: at(0, 0, dayOffset: 6))
        view.layoutIfNeeded()

        XCTAssertEqual(view.headerView.allDayRows, 1)
        XCTAssertEqual(view.headerView.frame.height, view.headerView.preferredHeight, accuracy: 0.01,
                       "the header must already be the height it asked for")
        XCTAssertEqual(view.timelineView.frame.minY,
                       bare + MultiDayStyle.allDayRowHeight,
                       accuracy: 0.01,
                       "and the timeline must already have been pushed down by exactly one row")
    }

    /// The chips have to fit inside the header they are drawn in, or they are clipped away and
    /// the all-day strip looks like it is colliding with the timetable below it.
    func testEveryChipFitsInsideTheHeader() {
        let view = makeView(events: [allDay("Year 9 Camp", dayOffset: 0),
                                     allDay("Casual Clothes Day", dayOffset: 0)])
        view.layoutIfNeeded()

        let height = view.headerView.bounds.height
        XCTAssertGreaterThan(height, MultiDayStyle.headerBaseHeight)
        for cell in view.headerView.cells {
            for chip in cell.chips {
                XCTAssertLessThanOrEqual(chip.frame.maxY, height + 0.01,
                                         "a chip drawn past the header's height is clipped away")
            }
        }
    }

    // MARK: - Month

    /// Three date numbers say nothing about where in the year they are, and within a few flicks
    /// that is genuinely disorienting.
    func testTheCornerNamesTheMonth() {
        let view = makeView()
        view.layoutIfNeeded()
        let text = view.headerView.monthLabel.attributedText?.string ?? ""
        XCTAssertEqual(text, calendar.shortStandaloneMonthSymbols[1], "26 February is in February")
    }

    /// The month follows the majority of the days on screen, so a window straddling the end of
    /// a month does not flicker between the two as it is dragged.
    func testTheMonthFollowsTheMajorityOfTheWindow() {
        // 27 Feb, 28 Feb, 1 Mar — still mostly February.
        let view = makeView()
        view.move(to: at(0, 0, dayOffset: 1))
        view.layoutIfNeeded()
        XCTAssertEqual(view.headerView.monthLabel.attributedText?.string,
                       calendar.shortStandaloneMonthSymbols[1])

        // 28 Feb, 1 Mar, 2 Mar — now mostly March.
        view.move(to: at(0, 0, dayOffset: 2))
        view.layoutIfNeeded()
        XCTAssertEqual(view.headerView.monthLabel.attributedText?.string,
                       calendar.shortStandaloneMonthSymbols[2])
    }

    /// The year is only worth the space when it is not the obvious one.
    func testTheYearAppearsOnlyWhenItIsNotThisYear() {
        let thisYear = calendar.component(.year, from: Date())
        let view = makeView(on: calendar.date(from: DateComponents(year: thisYear, month: 6, day: 15))!)
        view.layoutIfNeeded()
        XCTAssertFalse(view.headerView.monthLabel.attributedText?.string.contains("\(thisYear)") ?? true,
                       "this year is not worth saying")

        view.move(to: calendar.date(from: DateComponents(year: thisYear + 1, month: 6, day: 15))!)
        view.layoutIfNeeded()
        XCTAssertTrue(view.headerView.monthLabel.attributedText?.string.contains("\(thisYear + 1)") ?? false,
                      "a different year has to be said out loud")
    }

    // MARK: - Redrawing no more than necessary

    /// The app reloads the whole timeline whenever any one day's request lands, so a week of
    /// requests used to tear down and rebuild every event view on screen several times over —
    /// mid-scroll. An unchanged day now costs nothing.
    func testReloadingWithTheSameEventsDoesNotRebuildAColumn() {
        let column = DayColumnView(date: day, calendar: calendar)
        column.frame = CGRect(x: 0, y: 0, width: 120, height: 1700)
        column.events = [timed("Period 1", dayOffset: 0, from: 9, to: 10)]
        column.layoutIfNeeded()
        let first = column.subviews.compactMap { $0 as? EventView }.first
        XCTAssertNotNil(first)

        column.events = [timed("Period 1", dayOffset: 0, from: 9, to: 10)]
        column.layoutIfNeeded()

        XCTAssertIdentical(column.subviews.compactMap { $0 as? EventView }.first, first,
                           "an unchanged day must keep the views it already has")
    }

    /// The saving must not extend to changes that matter. Turning off a calendar layer changes
    /// which events a day has; recolouring one changes how it reads.
    func testAChangedDayIsStillRebuilt() {
        let column = DayColumnView(date: day, calendar: calendar)
        column.frame = CGRect(x: 0, y: 0, width: 120, height: 1700)
        column.events = [timed("Period 1", dayOffset: 0, from: 9, to: 10)]
        column.layoutIfNeeded()

        column.events = [timed("Period 1", dayOffset: 0, from: 9, to: 10),
                         timed("Period 2", dayOffset: 0, from: 10, to: 11)]
        column.layoutIfNeeded()
        XCTAssertEqual(column.subviews.compactMap { $0 as? EventView }.count, 2,
                       "an added lesson has to appear")

        let recoloured = timed("Period 1", dayOffset: 0, from: 9, to: 10)
        recoloured.color = .systemPink
        column.events = [recoloured]
        column.layoutIfNeeded()
        let views = column.subviews.compactMap { $0 as? EventView }.filter { $0.frame.height > 0 }
        XCTAssertEqual(views.count, 1, "a day that lost a lesson has to lose its view")
    }

    /// A recycled column is pointed at a different day, and two quiet days can hash the same.
    /// The fingerprint must not be allowed to mistake one for the other.
    func testARecycledColumnAlwaysTakesItsNewDaysEvents() {
        let column = DayColumnView(date: day, calendar: calendar)
        column.frame = CGRect(x: 0, y: 0, width: 120, height: 1700)
        column.events = []
        column.layoutIfNeeded()

        column.reuse(for: calendar.date(byAdding: .day, value: 1, to: day)!)
        column.events = []
        column.layoutIfNeeded()
        XCTAssertEqual(column.subviews.compactMap { $0 as? EventView }.filter { $0.frame.height > 0 }.count, 0)

        column.reuse(for: calendar.date(byAdding: .day, value: 2, to: day)!)
        column.events = [timed("Period 1", dayOffset: 2, from: 9, to: 10)]
        column.layoutIfNeeded()
        XCTAssertEqual(column.subviews.compactMap { $0 as? EventView }.filter { $0.frame.height > 0 }.count, 1,
                       "the day it was recycled onto has a lesson and it must be drawn")
    }

    // MARK: - Helpers

    /// Taps the first real all-day chip on screen. Returns false when there is none.
    @discardableResult
    private func tapFirstChip(in view: MultiDayView) -> Bool {
        for cell in view.headerView.cells {
            guard let chip = cell.chips.first(where: { !$0.isToggle }) else { continue }
            view.headerView.handleTap(at: CGPoint(x: cell.frame.midX,
                                                  y: chip.frame.midY))
            return true
        }
        return false
    }

    /// Taps the "+n" / "−" chip. Returns false when there is none.
    @discardableResult
    private func tapToggleChip(in view: MultiDayView) -> Bool {
        for cell in view.headerView.cells {
            guard let chip = cell.chips.first(where: { $0.isToggle }) else { continue }
            view.headerView.handleTap(at: CGPoint(x: cell.frame.midX,
                                                  y: chip.frame.midY))
            return true
        }
        return false
    }
}

private final class PolishSource: EventDataSource {
    private let events: [Event]
    init(_ events: [Event]) { self.events = events }
    func eventsForDate(_ date: Date) -> [EventDescriptor] {
        events.filter { Calendar.current.isDate($0.dateInterval.start, inSameDayAs: date) }
    }
}

private final class DelegateSpy: MultiDayViewDelegate {
    var selectedAllDayEvent: EventDescriptor?
    var selectedAllDayDate: Date?
    var selectedHeading: Date?

    func multiDayView(_ multiDayView: MultiDayView, didSelectAllDayEvent event: EventDescriptor, on date: Date) {
        selectedAllDayEvent = event
        selectedAllDayDate = date
    }

    func multiDayView(_ multiDayView: MultiDayView, didSelectDayHeading date: Date) {
        selectedHeading = date
    }
}
