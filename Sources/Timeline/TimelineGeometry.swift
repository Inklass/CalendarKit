import Foundation

/// The time ⇄ vertical-position mapping for one day of a timeline.
///
/// Split out of `TimelineView` so a multi-day column can place events on exactly the same
/// grid. Two components drawing the same day at slightly different offsets is the kind of
/// drift that only shows up once a school notices its periods are a pixel out.
public struct TimelineGeometry {
    /// The day this timeline represents. Times on other days are placed a full day above or
    /// below, so an event running past midnight is drawn continuing off the edge.
    public let date: Date
    public let calendar: Calendar
    public let verticalDiff: Double
    public let verticalInset: Double

    public init(date: Date, calendar: Calendar, verticalDiff: Double, verticalInset: Double) {
        self.date = date
        self.calendar = calendar
        self.verticalDiff = verticalDiff
        self.verticalInset = verticalInset
    }

    public init(date: Date, calendar: Calendar, style: TimelineStyle) {
        self.init(date: date,
                  calendar: calendar,
                  verticalDiff: style.verticalDiff,
                  verticalInset: style.verticalInset)
    }

    /// Height of a full 24 hours, excluding the insets above and below.
    public var dayHeight: Double { 24 * verticalDiff }

    /// Height of the whole scrollable timeline, insets included.
    public var fullHeight: Double { verticalInset * 2 + dayHeight }

    public func y(for date: Date) -> Double {
        let provisionedDate = date.dateOnly(calendar: calendar)
        let timelineDate = self.date.dateOnly(calendar: calendar)
        var dayOffset: Double = 0
        if provisionedDate > timelineDate {
            // Event ending the next day
            dayOffset += 1
        } else if provisionedDate < timelineDate {
            // Event starting the previous day
            dayOffset -= 1
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let hourY = Double(hour) * verticalDiff + verticalInset
        let minuteY = Double(minute) * verticalDiff / 60
        return hourY + minuteY + dayHeight * dayOffset
    }

    public func date(forY y: Double) -> Date {
        let timeValue = y - verticalInset
        var hour = Int(timeValue / verticalDiff)
        let fullHourPoints = Double(hour) * verticalDiff
        let minuteDiff = timeValue - fullHourPoints
        let minute = Int(minuteDiff / verticalDiff * 60)
        var dayOffset = 0
        if hour > 23 {
            dayOffset += 1
            hour -= 24
        } else if hour < 0 {
            dayOffset -= 1
            hour += 24
        }
        let offsetDate = calendar.date(byAdding: DateComponents(day: dayOffset), to: date)!
        return calendar.date(bySettingHour: hour,
                             minute: minute.clamped(to: 0...59),
                             second: 0,
                             of: offsetDate)!
    }
}
