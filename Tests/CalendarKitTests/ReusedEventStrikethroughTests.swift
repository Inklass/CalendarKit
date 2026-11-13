import XCTest
@testable import CalendarKit

/// A running class drew struck through, as if cancelled (PRO-84501).
///
/// `TimelineView` recycles its `EventView`s through a `ReusePool`. A cancelled event arrives
/// with an `attributedText` carrying the strikethrough, and assigning that to a `UITextView`
/// also sets its `typingAttributes`. The next event drawn in the same view, with no
/// `attributedText`, went through `textView.text = …`, which styles the new string from those
/// leftover typing attributes. Setting `font` and `textColor` afterwards does not clear them,
/// so the strikethrough stayed on a class that is running.
final class ReusedEventStrikethroughTests: XCTestCase {

    private func cancelled(_ title: String, _ from: Date, _ to: Date) -> Event {
        let event = Shots.event(title, from, to, .systemBlue)
        event.attributedText = NSAttributedString(
            string: event.text,
            attributes: [
                .font: event.font,
                .foregroundColor: event.textColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        return event
    }

    private func isStruckThrough(_ view: EventView) -> Bool {
        let text = view.textView.attributedText ?? NSAttributedString()
        var struck = false
        text.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let style = value as? Int, style != 0 { struck = true; stop.pointee = true }
        }
        return struck
    }

    func testARunningEventDoesNotKeepTheStrikethroughOfTheCancelledOneBeforeIt() {
        let view = EventView()
        view.updateWithDescriptor(event: cancelled("Drawing and Design", Shots.at(14), Shots.at(15)))
        XCTAssertTrue(isStruckThrough(view))

        view.updateWithDescriptor(event: Shots.event("Engineering Mathematics", Shots.at(9), Shots.at(10), .systemBlue))
        XCTAssertFalse(isStruckThrough(view))
        XCTAssertEqual(view.textView.text, "Engineering Mathematics")
    }

    /// The same thing through the timeline, the way the app reaches it: the timeline is laid out
    /// once with cancelled classes (a cached response, the previous day), then again with the
    /// fresh events. Only the two afternoon classes are cancelled in the fresh set.
    func testATimelineRelayoutOnlyStrikesTheCancelledClasses() throws {
        let timeline = TimelineView()
        timeline.date = Shots.anchorDay
        timeline.frame = CGRect(x: 0, y: 0, width: 402, height: 1600)

        let before = [
            cancelled("Engineering Mathematics", Shots.at(9), Shots.at(10)),
            cancelled("Engineering Mathematics", Shots.at(10), Shots.at(11)),
        ]
        timeline.layoutAttributes = before.map(EventLayoutAttributes.init)
        timeline.layoutIfNeeded()

        let after = [
            Shots.event("Engineering Mathematics", Shots.at(9), Shots.at(10), .systemBlue),
            Shots.event("Engineering Mathematics", Shots.at(10), Shots.at(11), .systemBlue),
            cancelled("Drawing and Design", Shots.at(14), Shots.at(15)),
            cancelled("Drawing and Design", Shots.at(15), Shots.at(16)),
        ]
        timeline.layoutAttributes = after.map(EventLayoutAttributes.init)
        timeline.layoutIfNeeded()

        let views = timeline.subviews.compactMap { $0 as? EventView }.filter { !$0.isHidden && $0.superview != nil }
        let struck = views.filter(isStruckThrough).compactMap { $0.descriptor?.text }.sorted()
        XCTAssertEqual(struck, ["Drawing and Design", "Drawing and Design"])
    }

    /// What it looks like: the screenshot from the report, rebuilt. Opt-in via
    /// `TIMELINE_SNAPSHOT_DIR`, like `ScreenshotTests`.
    func testScreenshotOfARelayoutAfterCancelledClasses() throws {
        try XCTSkipIf(Shots.directory == nil, "set TIMELINE_SNAPSHOT_DIR to write screenshots")
        let controller = TimelineContainerController()
        controller.timeline.date = Shots.anchorDay
        controller.timeline.updateStyle(Shots.inklassStyle().timeline)

        let before = [
            cancelled("Engineering Mathematics 1", Shots.at(9), Shots.at(10)),
            cancelled("Engineering Mathematics 1", Shots.at(10), Shots.at(11)),
        ]
        let after = [
            Shots.event("Engineering Mathematics 1", Shots.at(9), Shots.at(10), .systemBlue),
            Shots.event("Engineering Mathematics 1", Shots.at(10), Shots.at(11), .systemBlue),
            Shots.event("Materials and Manufacture", Shots.at(11, 30), Shots.at(12, 30), .systemTeal),
            Shots.event("Materials and Manufacture", Shots.at(12, 30), Shots.at(13, 30), .systemTeal),
            cancelled("Drawing and Design", Shots.at(14), Shots.at(15)),
            cancelled("Drawing and Design", Shots.at(15), Shots.at(16)),
        ]
        let image = Shots.render(controller, size: CGSize(width: 402, height: 640)) { _ in
            controller.timeline.layoutAttributes = before.map(EventLayoutAttributes.init)
            controller.view.layoutIfNeeded()
            controller.timeline.layoutAttributes = after.map(EventLayoutAttributes.init)
            controller.view.layoutIfNeeded()
            controller.container.contentOffset.y = controller.timeline.dateToY(Shots.at(8, 30))
        }
        try Shots.write(image, ProcessInfo.processInfo.environment["SHOT_NAME"] ?? "reused-strikethrough")
    }
}
