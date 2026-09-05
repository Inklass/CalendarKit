import XCTest
@testable import CalendarKit

/// A short event used to lose its title completely.
///
/// `UITextView` insets its text by 8pt top and bottom. `EventView` handed it the event's full
/// height, so on anything under about 20 minutes the single line was laid out below the box
/// and then clipped away — a five-minute duty rendered as a bare coloured stripe. Everything
/// taller was top-aligned rather than centred.
final class EventTextLayoutTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_772_064_000)
    private let width: Double = 200

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return Calendar.current.date(byAdding: .minute, value: minute, to: start)!
    }

    /// Renders one event for `minutes` and returns its view.
    private func view(minutes: Int, title: String = "Yard duty", height: Double? = nil) -> EventView {
        let event = Event()
        event.text = title
        event.dateInterval = DateInterval(start: at(9), end: at(9, minutes))

        let style = TimelineStyle()
        let eventView = EventView()
        eventView.updateWithDescriptor(event: event)
        let naturalHeight = Double(minutes) * style.verticalDiff / 60
        eventView.frame = CGRect(x: 0, y: 0, width: width, height: height ?? naturalHeight)
        eventView.layoutIfNeeded()
        return eventView
    }

    /// The headline fix. At `verticalDiff` 50 a five-minute event is about 4pt tall, so its
    /// title cannot fit inside — but it must still be drawn and readable.
    func testAVeryShortEventStillShowsItsTitle() {
        for minutes in [5, 10, 15, 20] {
            let eventView = view(minutes: minutes)
            let text = eventView.textView.frame

            XCTAssertGreaterThan(text.height, 0, "\(minutes)min: the text view must have height")
            let lineHeight = eventView.textView.font?.lineHeight ?? 0
            XCTAssertGreaterThanOrEqual(text.height, lineHeight,
                                        "\(minutes)min: at least one whole line must be laid out")
            XCTAssertTrue(text.intersects(eventView.bounds),
                          "\(minutes)min: the title must overlap the event it belongs to")
        }
    }

    /// The other half of the report: titles sat against the top rather than in the middle.
    func testTheTitleIsVerticallyCentred() {
        for minutes in [5, 30, 60, 240] {
            let eventView = view(minutes: minutes)
            XCTAssertEqual(eventView.textView.frame.midY, eventView.bounds.midY, accuracy: 0.5,
                           "\(minutes)min: the title should be centred on the event")
        }
    }

    /// A long title in a short event must truncate on one line rather than wrap itself out of
    /// sight.
    func testAShortEventTruncatesToASingleLine() {
        let eventView = view(minutes: 10, title: "Period 4 — Year 9 Mathematics with Mr Fitzgerald")
        XCTAssertEqual(eventView.textView.textContainer.maximumNumberOfLines, 1)
        XCTAssertEqual(eventView.textView.textContainer.lineBreakMode, .byTruncatingTail)
    }

    /// A tall event still wraps: the single-line rule is for events with no room, not for all.
    func testATallEventStillWraps() {
        let eventView = view(minutes: 120, title: "Period 4 — Year 9 Mathematics with Mr Fitzgerald")
        XCTAssertGreaterThan(eventView.textView.textContainer.maximumNumberOfLines, 1)
        XCTAssertNotEqual(eventView.textView.textContainer.lineBreakMode, .byTruncatingTail)
    }

    /// A tall event's title is not stretched to fill it — it takes the height it needs and is
    /// centred in what is left.
    func testATallEventDoesNotStretchItsTitle() {
        let eventView = view(minutes: 240)
        XCTAssertLessThan(eventView.textView.frame.height, eventView.bounds.height,
                          "a one-line title should not claim four hours of height")
    }

    /// The overflow is opt-out for anyone who would rather clip.
    func testClippingCanBeOptedBackIn() {
        let eventView = view(minutes: 5)
        eventView.showsTitleForVeryShortEvents = false
        eventView.setNeedsLayout()
        eventView.layoutIfNeeded()

        XCTAssertLessThanOrEqual(eventView.textView.frame.height, eventView.bounds.height + 0.01,
                                 "with the fix opted out the text stays inside the event")
    }

    /// An event that began the previous day is drawn with a negative origin. Its title belongs
    /// in the part that is actually on screen, not in the part above it.
    func testAnEventStartingYesterdayKeepsItsTitleOnScreen() {
        let event = Event()
        event.text = "Overnight excursion"
        event.dateInterval = DateInterval(start: at(9), end: at(11))

        let eventView = EventView()
        eventView.updateWithDescriptor(event: event)
        eventView.frame = CGRect(x: 0, y: -60, width: width, height: 100)
        eventView.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(eventView.textView.frame.minY, 59,
                                    "the title should sit inside the visible remainder of the event")
        XCTAssertLessThanOrEqual(eventView.textView.frame.maxY, eventView.bounds.maxY + 0.01)
    }

    /// A zero-height event — a data glitch, or an event whose start and end are the same — must
    /// not crash or produce a negative frame.
    func testAZeroHeightEventIsHandled() {
        let eventView = view(minutes: 0, height: 0)
        XCTAssertGreaterThanOrEqual(eventView.textView.frame.height, 0)
        XCTAssertFalse(eventView.textView.frame.height.isNaN)
    }

    /// A column narrower than the text inset must not produce a negative width.
    func testAVeryNarrowEventIsHandled() {
        let event = Event()
        event.text = "Duty"
        event.dateInterval = DateInterval(start: at(9), end: at(10))

        let eventView = EventView()
        eventView.updateWithDescriptor(event: event)
        eventView.frame = CGRect(x: 0, y: 0, width: 2, height: 50)
        eventView.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(eventView.textView.frame.width, 0)
    }

    /// Attributed text leaves `textView.font` nil, so the line-height maths has to fall back to
    /// the descriptor's font instead of crashing on a force unwrap.
    func testAttributedTitlesAreLaidOutToo() {
        let event = Event()
        event.text = "Assembly"
        event.attributedText = NSAttributedString(string: "Assembly",
                                                  attributes: [.font: UIFont.systemFont(ofSize: 11)])
        event.dateInterval = DateInterval(start: at(9), end: at(9, 10))

        let eventView = EventView()
        eventView.updateWithDescriptor(event: event)
        eventView.frame = CGRect(x: 0, y: 0, width: width, height: 8)
        eventView.layoutIfNeeded()

        XCTAssertGreaterThan(eventView.textView.frame.height, 0)
        XCTAssertEqual(eventView.textView.frame.midY, eventView.bounds.midY, accuracy: 0.5)
    }
}
