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
    public var events: [EventDescriptor] = [] {
        didSet {
            attributes = events
                .filter { !$0.isAllDay }
                .sorted { $0.dateInterval.start < $1.dateInterval.start }
                .map(EventLayoutAttributes.init)
            prepareEventViews()
            setNeedsLayout()
        }
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
