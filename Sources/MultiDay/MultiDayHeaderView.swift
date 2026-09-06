import UIKit

/// One all-day event, drawn as a chip under a day's heading.
///
/// A plain `UILabel` sets its text hard against the left edge, which put every title touching
/// the day separator beside it. It also has to remember which event it stands for, so a tap can
/// open the right one.
final class AllDayChipView: UILabel {

    /// The event this chip stands for, or nil when it is the "+n" affordance.
    var descriptor: EventDescriptor?
    /// True for the "+n" / "Less" chip, which toggles the strip instead of opening an event.
    var isToggle = false

    private let insets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

/// One day's heading: weekday letter, date, and any all-day events beneath it.
final class DayHeaderCell: UIView {
    private let symbolLabel = UILabel()
    private let dateLabel = UILabel()
    private let datePill = UIView()
    private(set) var chips = [AllDayChipView]()

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
                   toggle: DayHeaderCell.Toggle,
                   style: MultiDayStyle,
                   daySelectorStyle: DaySelectorStyle,
                   symbolsStyle: DaySymbolsStyle) {
        self.date = date
        self.style = style
        self.daySelectorStyle = daySelectorStyle

        let isToday = calendar.isDateInToday(date)
        let isWeekend = calendar.isDateInWeekend(date)

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
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

        configureChips(for: allDayEvents, toggle: toggle)
        setNeedsLayout()
    }

    /// What the last row of this cell should offer, once the events have been placed.
    enum Toggle {
        /// Nothing beyond the events themselves.
        case none
        /// The strip is collapsed and this day has more events than fit: offer "+n".
        case expand
        /// The strip is expanded because of this day: offer the way back.
        case collapse
    }

    /// Shows as many all-day events as the strip has room for, then a "+n" for the rest —
    /// dropping them silently would hide an excursion from the person looking for it.
    private func configureChips(for events: [EventDescriptor], toggle: Toggle) {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        guard allDayRows > 0 else { return }

        let rowsForEvents = toggle == .none ? allDayRows : allDayRows - 1
        let shown = Array(events.prefix(max(0, rowsForEvents)))

        for event in shown {
            let chip = makeChip(text: event.text,
                                textColor: event.textColor,
                                background: event.backgroundColor)
            chip.descriptor = event
            chip.isAccessibilityElement = true
            chip.accessibilityTraits = .button
            chips.append(chip)
        }

        switch toggle {
        case .none:
            break
        case .expand:
            let remaining = events.count - shown.count
            guard remaining > 0 else { break }
            let chip = makeToggleChip(text: "+\(remaining)")
            chip.accessibilityLabel = "\(remaining) more all-day, show all"
            chips.append(chip)
        case .collapse:
            // Deliberately a bare minus rather than a word: it sits in the slot "+3" occupied a
            // moment ago, so the pairing carries the meaning without needing a translation in
            // fourteen locales. The accessibility label says it in full.
            let chip = makeToggleChip(text: "\u{2212}")
            chip.accessibilityLabel = localizedString("all-day") + ", show fewer"
            chips.append(chip)
        }

        chips.forEach { addSubview($0) }
    }

    private func makeChip(text: String, textColor: UIColor, background: UIColor) -> AllDayChipView {
        let label = AllDayChipView()
        label.text = text
        label.font = style.allDayFont
        label.textColor = textColor
        label.backgroundColor = background
        label.lineBreakMode = .byTruncatingTail
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        return label
    }

    /// The "+n" / "−" chip. Centred and on a faint fill so it reads as something to press
    /// rather than as a stray word left over at the bottom of the strip.
    private func makeToggleChip(text: String) -> AllDayChipView {
        let chip = makeChip(text: text,
                            textColor: style.allDayOverflowTextColor,
                            background: style.allDayToggleBackgroundColor)
        chip.textAlignment = .center
        chip.isToggle = true
        chip.isAccessibilityElement = true
        chip.accessibilityTraits = .button
        return chip
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

    /// The chip under `point`, in this cell's coordinates.
    func chip(at point: CGPoint) -> AllDayChipView? {
        chips.first { $0.frame.insetBy(dx: 0, dy: -1).contains(point) }
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
    private(set) var monthLabel = UILabel()
    private(set) var cells = [DayHeaderCell]()

    /// Supplies the all-day events for a day. Set by `MultiDayView`.
    var allDayEventsProvider: ((Date) -> [EventDescriptor])?

    /// Someone tapped an all-day event.
    var onSelectAllDayEvent: ((EventDescriptor, Date) -> Void)?
    /// Someone tapped a day's heading rather than one of its events.
    var onSelectDay: ((Date) -> Void)?
    /// The all-day strip was expanded or collapsed.
    var onToggleExpansion: (() -> Void)?

    private(set) var allDayRows = 0

    /// Whether the all-day strip is showing everything rather than the first few rows.
    ///
    /// Set by tapping the "+n" chip. Without it that chip was a dead end: it told you an
    /// excursion existed and gave you no way to read it.
    private(set) var isAllDayExpanded = false

    /// The days the cells are currently configured for. Rebuilding a heading costs a data
    /// source read and a fresh set of chip labels, and `position` is called for every scroll
    /// callback — several times a frame — so the expensive half only runs when the window of
    /// days actually changes. Sliding is just a frame move.
    private var configuredDates: [Date]?
    /// The days actually on screen, which decide the month shown in the corner. The configured
    /// window is a day wider on each side, so it is not the same question.
    private var monthDates: [Date] = []

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
        monthLabel.textAlignment = .center
        monthLabel.numberOfLines = 2
        addSubview(content)
        addSubview(monthLabel)
        addSubview(allDayLabel)
        addSubview(separator)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
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
        invalidateConfiguration()
        setNeedsLayout()
    }

    func updateCalendar(_ calendar: Calendar) {
        self.calendar = calendar
        invalidateConfiguration()
        setNeedsLayout()
    }

    // MARK: - Configuration

    /// Builds the headings for `dates`, of which `visible` are the ones actually on screen.
    ///
    /// Separated from `position` because it decides `preferredHeight`, and the owner has to
    /// know that *before* it lays anything out. Doing it the other way round left the header a
    /// frame behind: the all-day strip appeared at the old height for one frame and the chips
    /// were clipped to nothing, which on a fast scroll reads as the headings flickering.
    ///
    /// - Returns: true when the header's preferred height changed.
    @discardableResult
    func configure(dates: [Date], visible: [Date]) -> Bool {
        // `visible` is a slice of `dates`, so an unchanged window means an unchanged month too
        // and there is nothing to do. This runs on every scroll callback — several times a
        // frame — so the early exit is the whole reason sliding stays cheap.
        guard needsReconfiguring(for: dates) else { return false }
        configuredDates = dates
        monthDates = visible
        let changed = reconfigure(for: dates)
        updateMonthLabel()
        return changed
    }

    /// Slides the already-configured headings to match the timeline's offset. Cheap: only
    /// frames move.
    ///
    /// - Parameter fractionalOffset: how far the first heading sits to the left of the
    ///   timeline's leading edge.
    func position(dayWidth: Double, leadingInset: Double, fractionalOffset: Double) {
        for (index, cell) in cells.enumerated() {
            cell.frame = CGRect(x: Double(index) * dayWidth, y: 0, width: dayWidth, height: bounds.height)
        }
        content.frame = CGRect(x: leadingInset - fractionalOffset,
                               y: 0,
                               width: Double(cells.count) * dayWidth,
                               height: bounds.height)
        monthLabel.frame = CGRect(x: 2, y: 2, width: max(0, leadingInset - 6), height: MultiDayStyle.headerBaseHeight - 8)
        allDayLabel.frame = CGRect(x: 0,
                                   y: MultiDayStyle.headerBaseHeight - 2,
                                   width: leadingInset - 6,
                                   height: MultiDayStyle.allDayRowHeight)
        allDayLabel.isHidden = allDayRows == 0
    }

    private func needsReconfiguring(for dates: [Date]) -> Bool {
        guard let configuredDates, configuredDates.count == dates.count else { return true }
        return !zip(configuredDates, dates).allSatisfy { calendar.isDate($0, inSameDayAs: $1) }
    }

    /// - Returns: true when the header's preferred height changed.
    private func reconfigure(for dates: [Date]) -> Bool {
        let allDay = dates.map { allDayEventsProvider?($0) ?? [] }
        let counts = allDay.map(\.count)
        let busiest = counts.max() ?? 0
        // Which day the toggle belongs to: the one that has more events than fit. Putting it on
        // every column would repeat "+2" three times across a strip that expands as a whole.
        let overflowIndex = busiest > MultiDayStyle.maximumAllDayRows
            ? counts.firstIndex(of: busiest)
            : nil
        if overflowIndex == nil {
            // Nothing overflows any more, so there is nothing to be expanded out of.
            isAllDayExpanded = false
        }

        let rows: Int
        if let overflowIndex, isAllDayExpanded {
            // Room for every event on the busiest day, plus the row that collapses it again.
            rows = min(MultiDayStyle.maximumExpandedAllDayRows, busiest + 1)
            _ = overflowIndex
        } else {
            rows = min(MultiDayStyle.maximumAllDayRows, busiest)
        }
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
            let toggle: DayHeaderCell.Toggle
            if index == overflowIndex {
                toggle = isAllDayExpanded ? .collapse : .expand
            } else if !isAllDayExpanded && allDay[index].count > rows {
                // A day that overflows the collapsed strip but is not the busiest still needs
                // to say so rather than silently dropping its last event.
                toggle = .expand
            } else {
                toggle = .none
            }
            cells[index].allDayRows = rows
            cells[index].configure(date: date,
                                   calendar: calendar,
                                   allDayEvents: allDay[index],
                                   toggle: toggle,
                                   style: style,
                                   daySelectorStyle: headerStyle.daySelector,
                                   symbolsStyle: headerStyle.daySymbols)
        }
        return heightChanged
    }

    /// Names the month in the corner above the hour gutter.
    ///
    /// Scrolling three days at a time, the date numbers alone stop meaning anything within a
    /// few flicks — "12, 13, 14" says nothing about which month, still less which year. The
    /// month follows the majority of the days on screen, so it changes over when most of the
    /// window has, and the year only appears when it is not the current one.
    private func updateMonthLabel() {
        guard let month = dominantMonth() else {
            monthLabel.attributedText = nil
            return
        }
        let symbols = calendar.shortStandaloneMonthSymbols
        let name = symbols.indices.contains(month.month - 1) ? symbols[month.month - 1] : ""
        let text = NSMutableAttributedString(
            string: name,
            attributes: [.font: style.monthFont, .foregroundColor: style.monthTextColor]
        )
        if month.year != calendar.component(.year, from: Date()) {
            text.append(NSAttributedString(
                string: "\n\(month.year)",
                attributes: [.font: style.monthYearFont, .foregroundColor: style.allDayOverflowTextColor]
            ))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 0
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        monthLabel.attributedText = text
    }

    /// The month most of the visible days belong to. A window straddling the end of a month
    /// keeps saying the old one until the majority has crossed over, which is what stops the
    /// label flickering back and forth on a slow drag.
    private func dominantMonth() -> (month: Int, year: Int)? {
        guard !monthDates.isEmpty else { return nil }
        var tally = [String: (count: Int, month: Int, year: Int)]()
        for date in monthDates {
            let components = calendar.dateComponents([.month, .year], from: date)
            guard let month = components.month, let year = components.year else { continue }
            let key = "\(year)-\(month)"
            tally[key, default: (0, month, year)].count += 1
        }
        // Ties go to the earlier month, so a two-day window does not flip on every frame.
        return tally.values
            .sorted { ($0.count, -($0.year * 12 + $0.month)) > ($1.count, -($1.year * 12 + $1.month)) }
            .first
            .map { ($0.month, $0.year) }
    }

    /// Forces the next `configure` to rebuild, for when the events behind the headings changed
    /// but the days did not.
    func invalidateConfiguration() {
        configuredDates = nil
    }

    // MARK: - Taps

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        handleTap(at: recognizer.location(in: content))
    }

    /// Split from the recogniser so the hit-testing can be exercised without synthesising a
    /// gesture — where a tap lands is the whole behaviour here.
    ///
    /// - Parameter point: in `content`'s coordinates, i.e. the sliding row of headings.
    func handleTap(at point: CGPoint) {
        guard let cell = cells.first(where: { $0.frame.contains(point) }) else { return }
        let inCell = content.convert(point, to: cell)

        if let chip = cell.chip(at: inCell) {
            if chip.isToggle {
                isAllDayExpanded.toggle()
                invalidateConfiguration()
                onToggleExpansion?()
            } else if let descriptor = chip.descriptor {
                onSelectAllDayEvent?(descriptor, cell.date)
            }
            return
        }
        onSelectDay?(cell.date)
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
