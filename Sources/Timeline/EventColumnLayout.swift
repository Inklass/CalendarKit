import CoreGraphics
import Foundation

/// Decides where each event sits horizontally within one day.
///
/// Lifted out of `TimelineView` unchanged so a multi-day column packs its events by the same
/// rules. The behaviour here is load-bearing for school timetables and is locked down by
/// `TimelineLayoutTests` — see the comments on each strategy for what it is protecting.
public enum EventColumnLayout {

    /// Assigns `frame` to every attribute in `sortedEvents`, which must already be sorted by
    /// start date.
    ///
    /// - Parameters:
    ///   - width: the width available to events, i.e. excluding the time gutter.
    ///   - leadingInset: where that width begins.
    ///   - geometry: supplies the vertical placement.
    public static func apply(to sortedEvents: [EventLayoutAttributes],
                             width: Double,
                             leadingInset: Double,
                             geometry: TimelineGeometry,
                             style: TimelineStyle) {
        if style.eventsWillOverlap {
            layoutAllowingOverlap(sortedEvents, width: width, leadingInset: leadingInset, geometry: geometry, style: style)
        } else {
            layoutInColumns(sortedEvents, width: width, leadingInset: leadingInset, geometry: geometry)
        }
    }

    /// Places events into columns so an event is only ever narrowed by events it genuinely
    /// runs alongside.
    ///
    /// Two passes. First the events are split into *clusters*: a cluster ends as soon as an
    /// event starts at or after everything before it has finished. A shared endpoint therefore
    /// starts a new cluster — a period ending at 11:30 and the next starting at 11:30 do not
    /// overlap, so consecutive lessons each span the timeline. (`DateInterval.intersects` would
    /// say they overlap, which is what used to lay them out side by side at half width.)
    ///
    /// Then each cluster's events are packed into the first column free at their start time.
    /// The width comes from how many columns the cluster needed — its peak concurrency — not
    /// from how many events it contains. Without that, one long event narrowed everything it
    /// merely spanned: an excursion across the morning squeezed each period it covered to a
    /// quarter width even though only ever two things ran at once.
    private static func layoutInColumns(_ sortedEvents: [EventLayoutAttributes],
                                        width: Double,
                                        leadingInset: Double,
                                        geometry: TimelineGeometry) {
        var clusters = [[EventLayoutAttributes]]()
        var cluster = [EventLayoutAttributes]()
        var clusterEnd: Date?

        for event in sortedEvents {
            let interval = event.descriptor.dateInterval
            if let end = clusterEnd, interval.start >= end {
                clusters.append(cluster)
                cluster = []
                clusterEnd = nil
            }
            cluster.append(event)
            clusterEnd = max(clusterEnd ?? interval.end, interval.end)
        }
        if !cluster.isEmpty {
            clusters.append(cluster)
        }

        for cluster in clusters {
            // The running end of each open column, so `firstIndex` finds the leftmost one this
            // event can join. Events arrive in start order, so a column's end only ever grows.
            var columnEnds = [Date]()
            var columnOfEvent = [Int]()

            for event in cluster {
                let interval = event.descriptor.dateInterval
                if let free = columnEnds.firstIndex(where: { $0 <= interval.start }) {
                    columnEnds[free] = interval.end
                    columnOfEvent.append(free)
                } else {
                    columnEnds.append(interval.end)
                    columnOfEvent.append(columnEnds.count - 1)
                }
            }

            let columnWidth = width / Double(columnEnds.count)
            for (index, event) in cluster.enumerated() {
                let interval = event.descriptor.dateInterval
                let startY = geometry.y(for: interval.start)
                let endY = geometry.y(for: interval.end)
                let x = leadingInset + Double(columnOfEvent[index]) * columnWidth
                event.frame = CGRect(x: x, y: startY, width: columnWidth, height: endY - startY)
            }
        }
    }

    /// The `style.eventsWillOverlap` layout: events in a group are drawn at equal width from the
    /// leading edge, deliberately overlapping one another.
    private static func layoutAllowingOverlap(_ sortedEvents: [EventLayoutAttributes],
                                              width: Double,
                                              leadingInset: Double,
                                              geometry: TimelineGeometry,
                                              style: TimelineStyle) {
        var groupsOfEvents = [[EventLayoutAttributes]]()
        var overlappingEvents = [EventLayoutAttributes]()

        for event in sortedEvents {
            if overlappingEvents.isEmpty {
                overlappingEvents.append(event)
                continue
            }

            guard let earliestEvent = overlappingEvents.first?.descriptor.dateInterval.start else { continue }
            let dateInterval = splitInterval(around: earliestEvent, geometry: geometry, style: style)
            if event.descriptor.dateInterval.contains(dateInterval.start) {
                overlappingEvents.append(event)
                continue
            }

            groupsOfEvents.append(overlappingEvents)
            overlappingEvents = [event]
        }

        groupsOfEvents.append(overlappingEvents)

        for overlappingEvents in groupsOfEvents {
            let totalCount = Double(overlappingEvents.count)
            for (index, event) in overlappingEvents.enumerated() {
                let startY = geometry.y(for: event.descriptor.dateInterval.start)
                let endY = geometry.y(for: event.descriptor.dateInterval.end)
                let floatIndex = Double(index)
                let x = leadingInset + floatIndex / totalCount * width
                let equalWidth = width / totalCount
                event.frame = CGRect(x: x, y: startY, width: equalWidth, height: endY - startY)
            }
        }
    }

    private static func splitInterval(around date: Date,
                                      geometry: TimelineGeometry,
                                      style: TimelineStyle) -> DateInterval {
        let calendar = geometry.calendar
        let splitMinuteInterval = style.splitMinuteInterval
        let minute = calendar.component(.minute, from: date)
        let minuteRange = (minute / splitMinuteInterval) * splitMinuteInterval
        let beginningRange = calendar.date(byAdding: .minute, value: -(minute - minuteRange), to: date)!
        let endRange = calendar.date(byAdding: .minute, value: splitMinuteInterval, to: beginningRange)!
        return DateInterval(start: beginningRange, end: endRange)
    }
}
