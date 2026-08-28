import XCTest
@testable import CalendarKit

/// Locks what a school timetable needs from the timeline layout:
///
/// 1. Consecutive periods each span the full width — touching is not overlapping.
/// 2. Genuinely concurrent events still split into columns.
/// 3. An event is only ever narrowed by events it *actually* runs alongside, so one long
///    event does not squash the periods it merely spans.
/// 4. None of the above changes when `style.eventGap` — a purely cosmetic inset — changes.
///
/// Point 4 is the one that kept biting. `recalculateEventLayout` used to gate its
/// shared-endpoint exemption on `eventGap > 0`, so a decoration silently decided whether
/// back-to-back periods counted as overlapping, and two workarounds shipped chasing the
/// resulting gap instead of the cause (Inklass PRO-80719, PRO-80759).
///
/// These assert the rendered `EventView` frames rather than the layout attributes, so they
/// cover the grouping and the cosmetic inset together.
final class TimelineLayoutTests: XCTestCase {

    private let width: Double = 320
    private let day = Date(timeIntervalSince1970: 1_772_064_000) // arbitrary, fixed

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func event(_ title: String, _ from: Date, _ to: Date) -> Event {
        let event = Event()
        event.text = title
        event.dateInterval = DateInterval(start: from, end: to)
        return event
    }

    /// A real school day: four back-to-back blocks, plus a staff meeting that genuinely
    /// runs concurrently with Period 2 so we can prove real overlaps are still detected.
    private func schoolDay() -> [Event] {
        [
            event("Period 1",  at(9),  at(10)),
            event("Period 2",  at(10), at(11)),
            event("Recess",    at(11), at(11, 20)),
            event("Period 3",  at(11, 20), at(12, 20)),
            event("Staff Mtg", at(10), at(11)),
        ]
    }

    /// Lays the day out through the real `TimelineView` and returns the rendered event views.
    private func render(_ events: [Event]? = nil, eventGap: Double) -> [(title: String, frame: CGRect)] {
        let timeline = TimelineView()
        timeline.date = day
        timeline.style.eventGap = eventGap
        timeline.frame = CGRect(x: 0, y: 0, width: width, height: timeline.fullHeight)
        timeline.layoutAttributes = (events ?? schoolDay()).map { EventLayoutAttributes($0) }
        timeline.layoutIfNeeded()

        return timeline.subviews
            .compactMap { $0 as? EventView }
            .compactMap { view in
                guard let descriptor = view.descriptor as? Event else { return nil }
                return (descriptor.text, view.frame)
            }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    private func frame(_ title: String, in rendered: [(title: String, frame: CGRect)]) -> CGRect {
        guard let match = rendered.first(where: { $0.title == title }) else {
            XCTFail("no event view rendered for \(title)"); return .zero
        }
        return match.frame
    }

    // MARK: - Touching is not overlapping

    /// The regression PRO-80759 was raised for. Before the fix these came back at 1/5 width
    /// whenever `eventGap` was 0, because the exemption never fired and the whole day chained
    /// into a single group.
    func testBackToBackPeriodsGetTheFullWidth() {
        let rendered = render(eventGap: 0)
        let full = width - TimelineStyle().leadingInset

        for title in ["Period 1", "Recess", "Period 3"] {
            XCTAssertEqual(frame(title, in: rendered).width, full, accuracy: 0.5,
                           "\(title) touches its neighbours but does not overlap them, so it should span the timeline")
        }
    }

    /// The property the shared-endpoint exemption must not cost us: a real overlap still splits.
    func testGenuinelyConcurrentEventsStillSplit() {
        let rendered = render(eventGap: 0)
        let half = (width - TimelineStyle().leadingInset) / 2

        XCTAssertEqual(frame("Period 2", in: rendered).width, half, accuracy: 0.5,
                       "Period 2 really does overlap the staff meeting")
        XCTAssertEqual(frame("Staff Mtg", in: rendered).width, half, accuracy: 0.5,
                       "the staff meeting really does overlap Period 2")
        XCTAssertNotEqual(frame("Period 2", in: rendered).minX,
                          frame("Staff Mtg", in: rendered).minX,
                          "overlapping events must sit in different columns")
    }

    /// The layout itself leaves nothing between consecutive lessons: at `eventGap = 0` the
    /// views meet exactly. Any visible gap is `eventGap` doing its job, not the layout.
    func testNoVerticalGapBetweenBackToBackPeriods() {
        let rendered = render(eventGap: 0)

        XCTAssertEqual(frame("Period 1", in: rendered).maxY,
                       frame("Period 2", in: rendered).minY, accuracy: 0.01,
                       "Period 1 ends exactly when Period 2 starts, so their views must meet")
        XCTAssertEqual(frame("Recess", in: rendered).maxY,
                       frame("Period 3", in: rendered).minY, accuracy: 0.01,
                       "recess ends exactly when Period 3 starts, so their views must meet")
    }

    /// `eventGap` insets each view on all sides, height included, so consecutive lessons read
    /// as separate blocks. Inklass runs it at 2 deliberately. This is a taste choice and
    /// nothing more — `testGroupingDoesNotDependOnTheCosmeticGap` is what keeps it that way.
    func testTheCosmeticGapReallyDoesOpenAVerticalGap() {
        let rendered = render(eventGap: 2)

        XCTAssertEqual(frame("Period 1", in: rendered).maxY + 2,
                       frame("Period 2", in: rendered).minY, accuracy: 0.01,
                       "eventGap is subtracted from height, so it shortens every event by 2pt")
    }

    /// Renders both fixtures at the gap Inklass ships (2) so the layout can be looked at rather
    /// than argued about. Opt-in: set `TIMELINE_SNAPSHOT_DIR` to a writable directory.
    func testWriteSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["TIMELINE_SNAPSHOT_DIR"] else {
            throw XCTSkip("set TIMELINE_SNAPSHOT_DIR to write snapshots")
        }

        let fixtures: [(name: String, events: [Event])] = [
            ("school-day", schoolDay()),
            ("excursion-day", [
                event("Excursion", at(9), at(15)),
                event("Period 1",  at(9),  at(10)),
                event("Period 2",  at(10), at(11)),
                event("Period 3",  at(11), at(12)),
            ]),
        ]

        for fixture in fixtures {
            let timeline = TimelineView()
            timeline.date = day
            timeline.style.eventGap = 2
            timeline.frame = CGRect(x: 0, y: 0, width: width, height: timeline.fullHeight)
            timeline.layoutAttributes = fixture.events.map { EventLayoutAttributes($0) }
            timeline.layoutIfNeeded()

            // Crop to 08:30–12:45 so the periods fill the image.
            let top = timeline.dateToY(at(8, 30))
            let crop = CGRect(x: 0, y: top, width: width, height: timeline.dateToY(at(12, 45)) - top)
            let image = UIGraphicsImageRenderer(size: crop.size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: crop.size))
                context.cgContext.translateBy(x: 0, y: -crop.minY)
                timeline.layer.render(in: context.cgContext)
            }
            try image.pngData()!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(fixture.name).png"))
        }
    }

    // MARK: - Stacking: width must follow how many events actually run at once

    /// A teacher with an excursion spanning the morning still teaches their periods. The
    /// excursion overlaps each of them, but the periods do not overlap *each other*, so at any
    /// instant only two events run: the excursion and one period. Two columns, half width each.
    ///
    /// The old grouping put every transitively-connected event in one group and gave them all
    /// `1/count` width, so a single long event squashed the whole day to a quarter width.
    func testALongEventDoesNotSquashThePeriodsItSpans() {
        let events = [
            event("Excursion", at(9), at(15)),
            event("Period 1",  at(9),  at(10)),
            event("Period 2",  at(10), at(11)),
            event("Period 3",  at(11), at(12)),
        ]
        let rendered = render(events, eventGap: 0)
        let half = (width - TimelineStyle().leadingInset) / 2

        for title in ["Excursion", "Period 1", "Period 2", "Period 3"] {
            XCTAssertEqual(frame(title, in: rendered).width, half, accuracy: 0.5,
                           "only two events ever run at once, so \(title) should be half width")
        }
    }

    /// The same day, viewed as columns: the three periods never overlap one another, so they
    /// all belong in the same column, beside the excursion.
    func testPeriodsSpannedByALongEventShareOneColumn() {
        let events = [
            event("Excursion", at(9), at(15)),
            event("Period 1",  at(9),  at(10)),
            event("Period 2",  at(10), at(11)),
            event("Period 3",  at(11), at(12)),
        ]
        let rendered = render(events, eventGap: 0)

        let periodX = ["Period 1", "Period 2", "Period 3"].map { frame($0, in: rendered).minX }
        XCTAssertEqual(Set(periodX).count, 1, "the periods do not overlap, so they share a column")
        XCTAssertNotEqual(periodX[0], frame("Excursion", in: rendered).minX,
                          "the excursion overlaps them, so it needs its own column")
    }

    /// Concurrency is per-instant, not per-day: an afternoon that happens to be busy must not
    /// narrow the morning.
    func testABusyAfternoonDoesNotNarrowTheMorning() {
        let events = [
            event("Assembly", at(9),  at(10)),
            event("Duty A",   at(10), at(11)),
            event("Duty B",   at(10), at(11)),
            event("Duty C",   at(10), at(11)),
        ]
        let rendered = render(events, eventGap: 0)
        let full = width - TimelineStyle().leadingInset

        XCTAssertEqual(frame("Assembly", in: rendered).width, full, accuracy: 0.5,
                       "nothing runs alongside the assembly, so it spans the timeline")
        XCTAssertEqual(frame("Duty A", in: rendered).width, full / 3, accuracy: 0.5,
                       "three duties really do run at once")
    }

    // MARK: - The coupling itself

    /// Grouping is a question about time, so it must not change when a cosmetic inset does.
    /// This is what actually broke: the answer used to depend on `eventGap`.
    func testGroupingDoesNotDependOnTheCosmeticGap() {
        let widths = { (gap: Double) -> [String: Double] in
            let rendered = self.render(eventGap: gap)
            return Dictionary(uniqueKeysWithValues: rendered.map { ($0.title, $0.frame.width + gap) })
        }

        XCTAssertEqual(widths(0), widths(2),
                       "the same day laid out with a different eventGap must produce the same columns")
    }
}
