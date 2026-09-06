import UIKit

/// One day's worth of timed events, drawn without a time gutter of its own.
///
/// This is the multi-day counterpart to `TimelineView`: the hour rules, the hour labels and
/// the scrolling all belong to `MultiDayTimelineView`, so a column is only responsible for
/// placing its own events. It shares `TimelineGeometry` and `EventColumnLayout` with
/// `TimelineView`, so a day looks the same whichever view is showing it.
public final class DayColumnView: UIView {

    public private(set) var date: Date
    public var calendar: Calendar {
        didSet { setNeedsLayout() }
    }

    /// Set by the owning timeline. All-day events are filtered out here — they belong in the
    /// header, where they stay put while the timeline scrolls.
    ///
    /// Assigning the same day again is free. That matters because the app reloads the whole
    /// timeline whenever any one day's network request lands, and a column that has not changed
    /// was rebuilding every event view it owns — tearing down and re-laying out a screenful of
    /// lessons, mid-scroll, several times as a week's worth of requests came back.
    public var events: [EventDescriptor] = [] {
        didSet {
            let incoming = Self.fingerprint(of: events)
            guard incoming != fingerprint else { return }
            fingerprint = incoming
            attributes = events
                .filter { !$0.isAllDay }
                .sorted { $0.dateInterval.start < $1.dateInterval.start }
                .map(EventLayoutAttributes.init)
            prepareEventViews()
            setNeedsLayout()
        }
    }

    /// What the column is currently showing. Nil until the first assignment, so an initial
    /// empty day is still applied rather than mistaken for "already empty".
    private var fingerprint: Int?

    /// Everything that decides how a day is drawn: which events, when, what they say and what
    /// colour they are. A layer being switched off changes the set; a lesson being recoloured
    /// changes a colour; either has to repaint.
    private static func fingerprint(of events: [EventDescriptor]) -> Int {
        var hasher = Hasher()
        for event in events where !event.isAllDay {
            hasher.combine(event.dateInterval.start)
            hasher.combine(event.dateInterval.end)
            hasher.combine(event.text)
            hasher.combine(event.backgroundColor)
            hasher.combine(event.textColor)
        }
        return hasher.finalize()
    }

    var style = TimelineStyle() {
        didSet { setNeedsLayout() }
    }

    private var attributes = [EventLayoutAttributes]()
    private var eventViews = [EventView]()
    private var pool = ReusePool<EventView>()

    public var geometry: TimelineGeometry {
        TimelineGeometry(date: date, calendar: calendar, style: style)
    }

    public init(date: Date, calendar: Calendar) {
        self.date = date
        self.calendar = calendar
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-points a recycled column at another day. The caller sets `events` afterwards.
    func reuse(for date: Date) {
        self.date = date
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        attributes.removeAll()
        // A different day's events must be applied even when they happen to hash the same as
        // the day this column was showing — two free periods look identical to a fingerprint.
        fingerprint = nil
    }

    private func prepareEventViews() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        for _ in attributes {
            let view = pool.dequeue()
            if view.superview == nil {
                addSubview(view)
            }
            eventViews.append(view)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }

        EventColumnLayout.apply(to: attributes,
                                width: bounds.width,
                                leadingInset: 0,
                                geometry: geometry,
                                style: style)

        for (view, attribute) in zip(eventViews, attributes) {
            view.frame = CGRect(x: attribute.frame.minX,
                                y: attribute.frame.minY,
                                width: max(0, attribute.frame.width - style.eventGap),
                                height: max(0, attribute.frame.height - style.eventGap))
            view.updateWithDescriptor(event: attribute.descriptor)
        }
    }

    /// The event view under `point`, in this column's coordinates. Searched back to front so
    /// the view drawn on top is the one that answers.
    public func eventView(at point: CGPoint) -> EventView? {
        eventViews.reversed().first { $0.frame.contains(point) }
    }
}
