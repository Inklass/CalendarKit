import XCTest
@testable import CalendarKit

/// Locks the two properties a school timetable needs from `recalculateEventLayout`:
/// consecutive periods get the full width, and genuinely concurrent events still split.
///
/// `DateInterval.intersects` counts a shared endpoint as an overlap, so Period 1 (09:00–10:00)
/// and Period 2 (10:00–11:00) used to be grouped and drawn side-by-side at half width.
/// The exemption for a shared endpoint was gated on `style.eventGap > 0` — a *cosmetic* value
/// that `layoutEvents` subtracts from every event view's width **and height**. Correct grouping
/// therefore cost a visible gap above every consecutive lesson, and two separate workarounds
/// shipped chasing that gap (Inklass PRO-80719, PRO-80759).
///
/// A shared endpoint is not an overlap, whatever `eventGap` is set to. These tests assert the
/// rendered `EventView` frames, so they cover the grouping and the inset together.
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
    private func render(eventGap: Double) -> [(title: String, frame: CGRect)] {
        let timeline = TimelineView()
        timeline.date = day
        timeline.style.eventGap = eventGap
        timeline.frame = CGRect(x: 0, y: 0, width: width, height: timeline.fullHeight)
        timeline.layoutAttributes = schoolDay().map { EventLayoutAttributes($0) }
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

    // MARK: - The app's real configuration: eventGap = 0

    /// The regression PRO-80759 was raised for. Before the fix these came back at 1/5 width,
    /// because with `eventGap = 0` the exemption never fired and the whole day chained into
    /// one group.
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

    /// The symptom the user reported: a visible gap above every consecutive lesson.
    /// `layoutEvents` subtracts `eventGap` from each view's height, so buying correct
    /// grouping with `eventGap = 2` drew a 60-minute period 2pt short.
    func testNoVerticalGapBetweenBackToBackPeriods() {
        let rendered = render(eventGap: 0)

        XCTAssertEqual(frame("Period 1", in: rendered).maxY,
                       frame("Period 2", in: rendered).minY, accuracy: 0.01,
                       "Period 1 ends exactly when Period 2 starts, so their views must meet")
        XCTAssertEqual(frame("Recess", in: rendered).maxY,
                       frame("Period 3", in: rendered).minY, accuracy: 0.01,
                       "recess ends exactly when Period 3 starts, so their views must meet")
    }

    /// Why the app must leave `eventGap` at 0, and why "just turn the gap on" was never a fix:
    /// the inset comes off the height too, so a 60-minute period draws short and every
    /// consecutive lesson gets a visible gap above it. This is the regression as reported.
    func testTheCosmeticGapReallyDoesOpenAVerticalGap() {
        let rendered = render(eventGap: 2)

        XCTAssertEqual(frame("Period 1", in: rendered).maxY + 2,
                       frame("Period 2", in: rendered).minY, accuracy: 0.01,
                       "eventGap is subtracted from height, so it shortens every event by 2pt")
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
