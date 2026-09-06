import XCTest
@testable import CalendarKit

/// Renders the calendar the way the app draws it so the layout can be looked at rather than
/// argued about. Opt-in: set `TIMELINE_SNAPSHOT_DIR` to a writable directory.
///
/// Run with:
///     TIMELINE_SNAPSHOT_DIR=/tmp/shots xcodebuild test -scheme CalendarKit \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CalendarKitTests/ScreenshotTests
final class ScreenshotTests: XCTestCase {

    /// iPhone 17 Pro in points.
    private let phone = CGSize(width: 402, height: 874)

    override func setUpWithError() throws {
        try XCTSkipIf(Shots.directory == nil, "set TIMELINE_SNAPSHOT_DIR to write screenshots")
    }

    /// The single-day view as it ships today: header, all-day row, timeline.
    func testDayView() throws {
        let dayView = DayView(calendar: .current)
        let source = StaticEvents(Shots.teachingDay())
        dayView.dataSource = source
        dayView.updateStyle(Shots.inklassStyle())
        // The pager seeds itself with today and assigning `state` only subscribes to it, so the
        // fixture day has to be moved to explicitly. Start a day off it or `move` is a no-op.
        dayView.state = DayViewState(date: Shots.at(0, 0, dayOffset: -1), calendar: .current)
        dayView.reloadData()

        let image = Shots.render(dayView, size: phone) { _ in
            dayView.move(to: Shots.anchorDay)
            Shots.pump()
            dayView.scrollTo(hour24: 8.3, animated: false)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "01-day-view")
    }

    /// Short events only, so nothing distracts from how their titles are drawn.
    /// This is the fixture the text fix is judged on.
    func testShortEvents() throws {
        let controller = TimelineContainerController()
        controller.timeline.date = Shots.anchorDay
        controller.timeline.updateStyle(Shots.inklassStyle().timeline)
        controller.timeline.layoutAttributes = Shots.shortEvents().map(EventLayoutAttributes.init)

        let size = CGSize(width: phone.width, height: 380)
        let image = Shots.render(controller, size: size) { _ in
            controller.container.contentOffset.y = controller.timeline.dateToY(Shots.at(8, 50))
        }
        try Shots.write(image, "02-short-events")
    }
    /// Three days at once. The days either side of the fixture day carry their own timetables
    /// so the columns are visibly distinct.
    func testThreeDayView() throws {
        let (controller, source) = makeThreeDay()
        let image = Shots.render(controller, size: phone) { _ in
            controller.move(to: Shots.anchorDay)
            controller.multiDayView.scrollTo(hour24: 8.3, animated: false)
            Shots.pump(0.3)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "03-three-day")
    }

    /// The same three-day view scrolled on by a single day. A paged view would have jumped a
    /// whole block of three; this window starts on the day after.
    func testThreeDayViewScrolledByOneDay() throws {
        let (controller, source) = makeThreeDay()
        let image = Shots.render(controller, size: phone) { _ in
            controller.move(to: Shots.at(0, 0, dayOffset: 1))
            controller.multiDayView.scrollTo(hour24: 8.3, animated: false)
            Shots.pump(0.3)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "04-three-day-plus-one")
    }

    /// Five days on a phone, to show the column count is a setting rather than a rebuild.
    func testFiveDayView() throws {
        let (controller, source) = makeThreeDay()
        controller.numberOfVisibleDays = 5
        let image = Shots.render(controller, size: phone) { _ in
            controller.move(to: Shots.at(0, 0, dayOffset: -1))
            controller.multiDayView.scrollTo(hour24: 8.3, animated: false)
            Shots.pump(0.3)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "05-five-day")
    }

    /// A day with more all-day entries than the strip shows: the last row is the "+n" that
    /// opens it out.
    func testThreeDayAllDayOverflow() throws {
        let (controller, source) = makeThreeDay(allDay: Shots.busyAllDayEvents())
        let image = Shots.render(controller, size: phone) { _ in
            controller.move(to: Shots.anchorDay)
            controller.multiDayView.scrollTo(hour24: 8.3, animated: false)
            Shots.pump(0.3)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "06-all-day-overflow")
    }

    /// The same window with the strip opened out, which is what a tap on "+n" does.
    func testThreeDayAllDayExpanded() throws {
        let (controller, source) = makeThreeDay(allDay: Shots.busyAllDayEvents())
        let image = Shots.render(controller, size: phone) { _ in
            controller.move(to: Shots.anchorDay)
            controller.multiDayView.scrollTo(hour24: 8.3, animated: false)
            Shots.pump(0.3)
            self.tapOverflowChip(in: controller.multiDayView)
            Shots.pump(0.4)
        }
        withExtendedLifetime(source) {}
        try Shots.write(image, "07-all-day-expanded")
    }

    private func tapOverflowChip(in view: MultiDayView) {
        for cell in view.headerView.cells {
            guard let chip = cell.chips.first(where: { $0.isToggle }) else { continue }
            view.headerView.handleTap(at: CGPoint(x: cell.frame.midX, y: chip.frame.midY))
            return
        }
    }

    private func makeThreeDay(allDay: [Event] = Shots.allDayEvents()) -> (MultiDayViewController, StaticEvents) {
        let controller = MultiDayViewController()
        var events = [Event]()
        for offset in -3...3 {
            events += Shots.teachingDay(dayOffset: offset)
        }
        events += allDay
        let source = StaticEvents(events)
        controller.loadViewIfNeeded()
        controller.dataSource = source
        controller.updateStyle(Shots.inklassStyle())
        controller.reloadData()
        return (controller, source)
    }
}

/// Serves one fixed set of events regardless of the date asked for, filtered to that day.
final class StaticEvents: EventDataSource {
    private let events: [Event]
    init(_ events: [Event]) { self.events = events }

    func eventsForDate(_ date: Date) -> [EventDescriptor] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.dateInterval.start, inSameDayAs: date) }
    }
}
