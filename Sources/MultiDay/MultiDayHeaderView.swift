import UIKit

/// One day's heading: weekday letter, date, and any all-day events beneath it.
final class DayHeaderCell: UIView {
    private let symbolLabel = UILabel()
    private let dateLabel = UILabel()
    private let datePill = UIView()
    private var chips = [UILabel]()

    private(set) var date = Date()
    private var style = MultiDayStyle()
    private var daySelectorStyle = DaySelectorStyle()

    /// How many all-day rows the strip is showing. Every cell uses the same number so the
    /// headings stay on one baseline.
    var allDayRows = 0 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolLabel.textAlignment = .center
        dateLabel.textAlignment = .center
        datePill.isUserInteractionEnabled = false
        addSubview(symbolLabel)
        addSubview(datePill)
        addSubview(dateLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(date: Date,
                   calendar: Calendar,
                   allDayEvents: [EventDescriptor],
                   style: MultiDayStyle,
                   daySelectorStyle: DaySelectorStyle,
                   symbolsStyle: DaySymbolsStyle) {
        self.date = date
        self.style = style
        self.daySelectorStyle = daySelectorStyle

        let isToday = calendar.isDateInToday(date)
        let isWeekend = calendar.isDateInWeekend(date)

        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekday = calendar.component(.weekday, from: date) - 1
        symbolLabel.text = symbols.indices.contains(weekday) ? symbols[weekday] : ""
        symbolLabel.font = symbolsStyle.font
        symbolLabel.textColor = isWeekend ? symbolsStyle.weekendColor : symbolsStyle.weekDayColor

        dateLabel.text = String(calendar.component(.day, from: date))
        dateLabel.font = isToday ? daySelectorStyle.todayFont : daySelectorStyle.font
        dateLabel.textColor = isToday
            ? daySelectorStyle.todayActiveTextColor
            : (isWeekend ? daySelectorStyle.weekendTextColor : daySelectorStyle.inactiveTextColor)
        datePill.backgroundColor = isToday ? daySelectorStyle.todayActiveBackgroundColor : .clear

        configureChips(for: allDayEvents)
        setNeedsLayout()
    }

    /// Shows as many all-day events as the strip has room for, then a "+n" for the rest —
    /// dropping them silently would hide an excursion from the person looking for it.
    private func configureChips(for events: [EventDescriptor]) {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        guard allDayRows > 0, !events.isEmpty else { return }

        let overflowing = events.count > allDayRows
        let shown = overflowing ? Array(events.prefix(allDayRows - 1)) : Array(events.prefix(allDayRows))

        for event in shown {
            chips.append(makeChip(text: event.text,
                                  textColor: event.textColor,
                                  background: event.backgroundColor))
        }
        if overflowing {
            let remaining = events.count - shown.count
            chips.append(makeChip(text: "+\(remaining)",
                                  textColor: style.allDayOverflowTextColor,
                                  background: .clear))
        }
        chips.forEach { addSubview($0) }
    }

    private func makeChip(text: String, textColor: UIColor, background: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = style.allDayFont
        label.textColor = textColor
        label.backgroundColor = background
        label.lineBreakMode = .byTruncatingTail
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        return label
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let symbolHeight: Double = 14
        let pillSize: Double = 26

        symbolLabel.frame = CGRect(x: 0, y: 2, width: bounds.width, height: symbolHeight)
        datePill.frame = CGRect(x: (bounds.width - pillSize) / 2,
                                y: symbolLabel.frame.maxY + 2,
                                width: pillSize,
                                height: pillSize)
        datePill.layer.cornerRadius = pillSize / 2
        dateLabel.frame = datePill.frame

        var y = datePill.frame.maxY + 4
        for chip in chips {
            chip.frame = CGRect(x: 2, y: y, width: max(0, bounds.width - 4), height: MultiDayStyle.allDayRowHeight - 2)
            y += MultiDayStyle.allDayRowHeight
        }
    }
}

/// The row of day headings above a `MultiDayTimelineView`, kept in step with its horizontal
/// scrolling so a heading is always over its own column.
public final class MultiDayHeaderView: UIView {

    public private(set) var calendar: Calendar
    private var style = MultiDayStyle()
    private var headerStyle = DayHeaderStyle()

    private let content = UIView()
    private let separator = UIView()
    private let allDayLabel = UILabel()
    private var cells = [DayHeaderCell]()

    /// Supplies the all-day events for a day. Set by `MultiDayView`.
    var allDayEventsProvider: ((Date) -> [EventDescriptor])?

    private(set) var allDayRows = 0

    /// Height the header needs for the days it is currently showing.
    public var preferredHeight: Double {
        MultiDayStyle.headerBaseHeight + Double(allDayRows) * MultiDayStyle.allDayRowHeight
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = headerStyle.backgroundColor
        allDayLabel.font = style.allDayFont
        allDayLabel.textColor = style.allDayOverflowTextColor
        allDayLabel.textAlignment = .right
        allDayLabel.text = localizedString("all-day")
        addSubview(content)
        addSubview(allDayLabel)
        addSubview(separator)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateStyle(_ header: DayHeaderStyle, multiDay: MultiDayStyle) {
        headerStyle = header
        style = multiDay
        backgroundColor = header.backgroundColor
        separator.backgroundColor = header.separatorColor
        allDayLabel.font = multiDay.allDayFont
        allDayLabel.textColor = multiDay.allDayOverflowTextColor
        setNeedsLayout()
    }

    func updateCalendar(_ calendar: Calendar) {
        self.calendar = calendar
        setNeedsLayout()
    }

    /// Renders headings for `dates`, whose first entry is the column at `fractionalOffset`
    /// points to the left of the timeline's leading edge.
    ///
    /// The caller passes a day of slack on each side and the sub-day part of the scroll offset,
    /// so the headings track the columns continuously rather than snapping at the halfway mark.
    ///
    /// - Returns: true when the header's preferred height changed, so the owner can re-lay out.
    @discardableResult
    func show(dates: [Date], dayWidth: Double, leadingInset: Double, fractionalOffset: Double) -> Bool {
        let allDay = dates.map { allDayEventsProvider?($0) ?? [] }
        let rows = min(MultiDayStyle.maximumAllDayRows, allDay.map(\.count).max() ?? 0)
        let heightChanged = rows != allDayRows
        allDayRows = rows

        while cells.count < dates.count {
            let cell = DayHeaderCell()
            content.addSubview(cell)
            cells.append(cell)
        }
        while cells.count > dates.count {
            cells.removeLast().removeFromSuperview()
        }

        for (index, date) in dates.enumerated() {
            cells[index].allDayRows = rows
            cells[index].configure(date: date,
                                   calendar: calendar,
                                   allDayEvents: allDay[index],
                                   style: style,
                                   daySelectorStyle: headerStyle.daySelector,
                                   symbolsStyle: headerStyle.daySymbols)
            cells[index].frame = CGRect(x: Double(index) * dayWidth, y: 0, width: dayWidth, height: bounds.height)
        }

        content.frame = CGRect(x: leadingInset - fractionalOffset,
                               y: 0,
                               width: Double(dates.count) * dayWidth,
                               height: bounds.height)
        allDayLabel.frame = CGRect(x: 0,
                                   y: MultiDayStyle.headerBaseHeight - 2,
                                   width: leadingInset - 6,
                                   height: MultiDayStyle.allDayRowHeight)
        allDayLabel.isHidden = rows == 0
        return heightChanged
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        separator.frame = CGRect(x: 0,
                                 y: bounds.height - 1 / UIScreen.main.scale,
                                 width: bounds.width,
                                 height: 1 / UIScreen.main.scale)
        for cell in cells {
            cell.frame.size.height = bounds.height
        }
        content.frame.size.height = bounds.height
    }
}
