import UIKit
@testable import CalendarKit

/// Shared fixtures and rendering plumbing for the screenshot harness.
///
/// Screenshots go through a real `UIWindow` rather than `layer.render(in:)` so they are
/// rasterised at the simulator's screen scale and exercise the same layout path the app does.
/// `TimelineView` pins its `contentsScale` to 1, so a layer render upscales a 1x backing store
/// and the hour rules and time labels come out soft.
enum Shots {

    /// Fixed so screenshots are byte-comparable between runs — Thursday 26 February 2026.
    /// Deliberately not today, so the red now-line never lands in the middle of a fixture.
    static let anchorDay = Date(timeIntervalSince1970: 1_772_064_000)

    static var directory: String? {
        ProcessInfo.processInfo.environment["TIMELINE_SNAPSHOT_DIR"]
    }

    static func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: anchorDay)!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    static func event(_ title: String, _ from: Date, _ to: Date, _ color: UIColor) -> Event {
        let event = Event()
        event.text = title
        event.dateInterval = DateInterval(start: from, end: to)
        event.color = color
        return event
    }

    /// A teacher's day with the short entries that motivated the text fix: a 5-minute
    /// transition, a 10-minute briefing and a 15-minute yard duty sit between full periods.
    static func teachingDay(dayOffset: Int = 0) -> [Event] {
        func t(_ h: Int, _ m: Int = 0) -> Date { at(h, m, dayOffset: dayOffset) }
        return [
            event("Homeroom",           t(8, 40), t(9),      .systemIndigo),
            event("Period 1 — 9 Maths", t(9),     t(10),     .systemBlue),
            event("Transition",         t(10),    t(10, 5),  .systemOrange),
            event("Period 2 — 10 Sci",  t(10, 5), t(11, 5),  .systemBlue),
            event("Briefing",           t(11, 5), t(11, 15), .systemPink),
            event("Period 3 — 7 Eng",   t(11, 15), t(12, 15), .systemBlue),
            event("Yard duty",          t(12, 15), t(12, 30), .systemGreen),
            event("Lunch",              t(12, 30), t(13, 10), .systemGray),
            event("Period 4 — 8 Hist",  t(13, 10), t(14, 10), .systemBlue),
            event("Staff meeting",      t(14, 10), t(15),     .systemPurple),
        ]
    }

    /// Nothing but short events, so the title rendering is the only thing on screen to judge.
    static func shortEvents(dayOffset: Int = 0) -> [Event] {
        func t(_ h: Int, _ m: Int = 0) -> Date { at(h, m, dayOffset: dayOffset) }
        return [
            event("5 min — Transition",  t(9),      t(9, 5),   .systemOrange),
            event("10 min — Briefing",   t(9, 15),  t(9, 25),  .systemPink),
            event("15 min — Yard duty",  t(9, 35),  t(9, 50),  .systemGreen),
            event("20 min — Assembly",   t(10),     t(10, 20), .systemTeal),
            event("30 min — Mentoring",  t(10, 30), t(11),     .systemPurple),
            event("60 min — Period 1",   t(11, 10), t(12, 10), .systemBlue),
        ]
    }

    /// All-day entries, which a multi-day view has to show in the header rather than letting
    /// them scroll away with the timeline.
    static func allDayEvents() -> [Event] {
        func allDay(_ title: String, _ dayOffset: Int, _ color: UIColor) -> Event {
            let event = event(title,
                              at(0, 0, dayOffset: dayOffset),
                              at(23, 59, dayOffset: dayOffset),
                              color)
            event.isAllDay = true
            return event
        }
        return [
            allDay("Year 9 Camp", 0, .systemGreen),
            allDay("Year 9 Camp", 1, .systemGreen),
            allDay("Casual Clothes Day", 1, .systemOrange),
            allDay("Parent-Teacher Night", 2, .systemPurple),
        ]
    }

    static func inklassStyle() -> CalendarStyle {
        var style = CalendarStyle()
        style.timeline.eventGap = 2
        return style
    }

    // MARK: - Rendering

    /// Hosts `view` in a key window at `size`, lets it lay out, then rasterises it.
    static func render(_ view: UIView, size: CGSize, before: ((UIView) -> Void)? = nil) -> UIImage {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(view)
        view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        before?(view)
        window.layoutIfNeeded()

        return UIGraphicsImageRenderer(size: size).image { context in
            if !window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    /// Hosts a view controller, which is what the scrolling components need.
    static func render(_ controller: UIViewController, size: CGSize, before: ((UIViewController) -> Void)? = nil) -> UIImage {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        before?(controller)
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        return UIGraphicsImageRenderer(size: size).image { context in
            if !window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    /// Lets UIKit finish animated work — `DayView` moves between days through an animated
    /// `UIPageViewController` transition, so the target day is not on screen until it settles.
    static func pump(_ seconds: TimeInterval = 0.7) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func write(_ image: UIImage, _ name: String) throws {
        guard let dir = directory else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try image.pngData()!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
