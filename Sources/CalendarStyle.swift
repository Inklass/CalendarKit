import Foundation
import UIKit

public enum DateStyle {
    ///Times should be shown in the 12 hour format
    case twelveHour
    
    ///Times should be shown in the 24 hour format
    case twentyFourHour
    
    ///Times should be shown according to the user's system preference.
    case system
}

public struct CalendarStyle {
    public var header = DayHeaderStyle()
    public var timeline = TimelineStyle()
    public var multiDay = MultiDayStyle()
    public init() {}
}

/// Styling specific to the several-days-at-once view.
public struct MultiDayStyle {
    /// Height of the weekday letter and date pill. The all-day strip is added below it.
    public static let headerBaseHeight: Double = 48
    public static let allDayRowHeight: Double = 18
    /// Beyond this the strip would eat the timeline, so the rest collapse into a "+n" chip.
    public static let maximumAllDayRows = 3

    public var daySeparatorColor = SystemColors.systemSeparator
    /// A wash behind today's column. Nil leaves it plain.
    public var todayColumnBackgroundColor: UIColor? = SystemColors.systemRed.withAlphaComponent(0.04)
    /// A wash behind Saturday and Sunday, the way a paper diary greys the weekend.
    public var weekendColumnBackgroundColor: UIColor? = SystemColors.secondarySystemBackground
    public var allDayFont = UIFont.systemFont(ofSize: 10)
    public var allDayOverflowTextColor = SystemColors.secondaryLabel
    public init() {}
}

public struct DayHeaderStyle {
    public var daySymbols = DaySymbolsStyle()
    public var daySelector = DaySelectorStyle()
    public var swipeLabel = SwipeLabelStyle()
    public var backgroundColor = SystemColors.systemBackground
    public var separatorColor = SystemColors.systemSeparator
    public init() {}
}

public struct DaySelectorStyle {
    public var activeTextColor = SystemColors.systemBackground
    public var selectedBackgroundColor = SystemColors.label

    public var weekendTextColor = SystemColors.secondaryLabel
    public var inactiveTextColor = SystemColors.label
    public var inactiveBackgroundColor = UIColor.clear

    public var todayInactiveTextColor = SystemColors.systemRed
    public var todayActiveTextColor = UIColor.white
    public var todayActiveBackgroundColor = SystemColors.systemRed
    
    public var font = UIFont.systemFont(ofSize: 18)
    public var todayFont = UIFont.boldSystemFont(ofSize: 18)

    public init() {}
}

public struct DaySymbolsStyle {
    public var weekendColor = SystemColors.secondaryLabel
    public var weekDayColor = SystemColors.label
    public var font = UIFont.systemFont(ofSize: 10)
    public init() {}
}

public struct SwipeLabelStyle {
    public var textColor = SystemColors.label
    public var font = UIFont.systemFont(ofSize: 15)
    public var isVisible = true
    public init() {}
}

public struct TimelineStyle {
    public var allDayStyle = AllDayViewStyle()
    public var timeIndicator = CurrentTimeIndicatorStyle()
    public var timeColor = SystemColors.secondaryLabel
    public var separatorColor = SystemColors.systemSeparator
    public var backgroundColor = SystemColors.systemBackground
    public var font = UIFont.boldSystemFont(ofSize: 11)
    public var dateStyle : DateStyle = .system
    public var eventsWillOverlap: Bool = false
    public var minimumEventDurationInMinutesWhileEditing: Int = 30
    public var splitMinuteInterval: Int = 15
    public var verticalDiff: Double = 50
    public var verticalInset: Double = 10
    public var leadingInset: Double = 53
    public var eventGap: Double = 0
    public init() {}
}

public struct CurrentTimeIndicatorStyle {
    public var color = SystemColors.systemRed
    public var font = UIFont.systemFont(ofSize: 11)
    public var dateStyle : DateStyle = .system
    public init() {}
}

public struct AllDayViewStyle {
    public var backgroundColor: UIColor = SystemColors.systemGray4
    public var allDayFont = UIFont.systemFont(ofSize: 12.0)
    public var allDayColor: UIColor = SystemColors.label
    public init() {}
}
