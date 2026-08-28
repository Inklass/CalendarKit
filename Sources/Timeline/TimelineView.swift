import UIKit

public protocol TimelineViewDelegate: AnyObject {
    func timelineView(_ timelineView: TimelineView, didTapAt date: Date)
    func timelineView(_ timelineView: TimelineView, didLongPressAt date: Date)
    func timelineView(_ timelineView: TimelineView, didTap event: EventView)
    func timelineView(_ timelineView: TimelineView, didLongPress event: EventView)
}

public final class TimelineView: UIView {
    public weak var delegate: TimelineViewDelegate?

    public var date = Date() {
        didSet {
            setNeedsLayout()
        }
    }

    private var currentTime: Date {
        Date()
    }

    private var eventViews = [EventView]()
    public private(set) var regularLayoutAttributes = [EventLayoutAttributes]()
    public private(set) var allDayLayoutAttributes = [EventLayoutAttributes]()

    public var layoutAttributes: [EventLayoutAttributes] {
        get {
            allDayLayoutAttributes + regularLayoutAttributes
        }
        set {

            // update layout attributes by separating all-day from non-all-day events
            allDayLayoutAttributes.removeAll()
            regularLayoutAttributes.removeAll()
            for anEventLayoutAttribute in newValue {
                let eventDescriptor = anEventLayoutAttribute.descriptor
                if eventDescriptor.isAllDay {
                    allDayLayoutAttributes.append(anEventLayoutAttribute)
                } else {
                    regularLayoutAttributes.append(anEventLayoutAttribute)
                }
            }

            recalculateEventLayout()
            prepareEventViews()
            allDayView.events = allDayLayoutAttributes.map { $0.descriptor }
            allDayView.isHidden = allDayLayoutAttributes.count == 0
            allDayView.scrollToBottom()

            setNeedsLayout()
        }
    }
    private var pool = ReusePool<EventView>()

    public var firstEventYPosition: Double? {
        let first = regularLayoutAttributes.sorted{$0.frame.origin.y < $1.frame.origin.y}.first
        guard let firstEvent = first else {return nil}
        let firstEventPosition = firstEvent.frame.origin.y
        let beginningOfDayPosition = dateToY(date)
        return max(firstEventPosition, beginningOfDayPosition)
    }

    private lazy var nowLine: CurrentTimeIndicator = CurrentTimeIndicator()

    private var allDayViewTopConstraint: NSLayoutConstraint?
    private lazy var allDayView: AllDayView = {
        let allDayView = AllDayView(frame: CGRect.zero)

        allDayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(allDayView)

        allDayViewTopConstraint = allDayView.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        allDayViewTopConstraint?.isActive = true

        allDayView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0).isActive = true
        allDayView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true

        return allDayView
    }()

    var allDayViewHeight: Double {
        allDayView.bounds.height
    }

    var style = TimelineStyle()
    private var horizontalEventInset: Double = 3

    public var fullHeight: Double {
        style.verticalInset * 2 + style.verticalDiff * 24
    }

    public var calendarWidth: Double {
        bounds.width - style.leadingInset
    }
    
    public private(set) var is24hClock = true {
        didSet {
            setNeedsDisplay()
        }
    }

    public var calendar: Calendar = Calendar.autoupdatingCurrent {
        didSet {
            eventEditingSnappingBehavior.calendar = calendar
            nowLine.calendar = calendar
            regenerateTimeStrings()
            setNeedsLayout()
        }
    }

    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior = SnapTo15MinuteIntervals() {
        didSet {
            eventEditingSnappingBehavior.calendar = calendar
        }
    }

    private var times: [String] {
        is24hClock ? _24hTimes : _12hTimes
    }

    private lazy var _12hTimes: [String] = TimeStringsFactory(calendar).make12hStrings()
    private lazy var _24hTimes: [String] = TimeStringsFactory(calendar).make24hStrings()

    private func regenerateTimeStrings() {
        let factory = TimeStringsFactory(calendar)
        _12hTimes = factory.make12hStrings()
        _24hTimes = factory.make24hStrings()
    }

    public lazy private(set) var longPressGestureRecognizer = UILongPressGestureRecognizer(target: self,
                                                                                           action: #selector(longPress(_:)))

    public lazy private(set) var tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                                               action: #selector(tap(_:)))

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    // MARK: - Initialization

    public init() {
        super.init(frame: .zero)
        frame.size.height = fullHeight
        configure()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {
        contentScaleFactor = 1
        layer.contentsScale = 1
        contentMode = .redraw
        backgroundColor = .white
        addSubview(nowLine)

        // Add long press gesture recognizer
        addGestureRecognizer(longPressGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
    }

    // MARK: - Event Handling

    @objc private func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if (gestureRecognizer.state == .began) {
            // Get timeslot of gesture location
            let pressedLocation = gestureRecognizer.location(in: self)
            if let eventView = findEventView(at: pressedLocation) {
                delegate?.timelineView(self, didLongPress: eventView)
            } else {
                delegate?.timelineView(self, didLongPressAt: yToDate(pressedLocation.y))
            }
        }
    }

    @objc private func tap(_ sender: UITapGestureRecognizer) {
        let pressedLocation = sender.location(in: self)
        if let eventView = findEventView(at: pressedLocation) {
            delegate?.timelineView(self, didTap: eventView)
        } else {
            delegate?.timelineView(self, didTapAt: yToDate(pressedLocation.y))
        }
    }

    private func findEventView(at point: CGPoint) -> EventView? {
        for eventView in allDayView.eventViews {
            let frame = eventView.convert(eventView.bounds, to: self)
            if frame.contains(point) {
                return eventView
            }
        }

        for eventView in eventViews {
            let frame = eventView.frame
            if frame.contains(point) {
                return eventView
            }
        }
        return nil
    }


    /**
     Custom implementation of the hitTest method is needed for the tap gesture recognizers
     located in the AllDayView to work.
     Since the AllDayView could be outside of the Timeline's bounds, the touches to the EventViews
     are ignored.
     In the custom implementation the method is recursively invoked for all of the subviews,
     regardless of their position in relation to the Timeline's bounds.
     */
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in allDayView.subviews {
            if let subSubView = subview.hitTest(convert(point, to: subview), with: event) {
                return subSubView
            }
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Style

    public func updateStyle(_ newStyle: TimelineStyle) {
        style = newStyle
        allDayView.updateStyle(style.allDayStyle)
        nowLine.updateStyle(style.timeIndicator)

        switch style.dateStyle {
        case .twelveHour:
            is24hClock = false
        case .twentyFourHour:
            is24hClock = true
        default:
            is24hClock = calendar.locale?.uses24hClock ?? Locale.autoupdatingCurrent.uses24hClock
        }

        backgroundColor = style.backgroundColor
        setNeedsDisplay()
    }

    // MARK: - Background Pattern

    public var accentedDate: Date?

    override public func draw(_ rect: CGRect) {
        super.draw(rect)

        var hourToRemoveIndex = -1

        var accentedHour = -1
        var accentedMinute = -1

        if let accentedDate {
            accentedHour = eventEditingSnappingBehavior.accentedHour(for: accentedDate)
            accentedMinute = eventEditingSnappingBehavior.accentedMinute(for: accentedDate)
        }

        if isToday {
            let minute = component(component: .minute, from: currentTime)
            let hour = component(component: .hour, from: currentTime)
            if minute > 39 {
                hourToRemoveIndex = hour + 1
            } else if minute < 21 {
                hourToRemoveIndex = hour
            }
        }

        let mutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        mutableParagraphStyle.lineBreakMode = .byWordWrapping
        mutableParagraphStyle.alignment = .right
        let paragraphStyle = mutableParagraphStyle.copy() as! NSParagraphStyle

        let attributes = [NSAttributedString.Key.paragraphStyle: paragraphStyle,
                          NSAttributedString.Key.foregroundColor: self.style.timeColor,
                          NSAttributedString.Key.font: style.font] as [NSAttributedString.Key : Any]

        let scale = UIScreen.main.scale
        let hourLineHeight = 1 / UIScreen.main.scale

        let center: Double
        if Int(scale) % 2 == 0 {
            center = 1 / (scale * 2)
        } else {
            center = 0
        }

        let offset = 0.5 - center

        for (hour, time) in times.enumerated() {
            let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft

            let hourFloat = Double(hour)
            let context = UIGraphicsGetCurrentContext()
            context!.interpolationQuality = .none
            context?.saveGState()
            context?.setStrokeColor(style.separatorColor.cgColor)
            context?.setLineWidth(hourLineHeight)
            let xStart: Double = {
                if rightToLeft {
                    return bounds.width - 53
                } else {
                    return 53
                }
            }()
            let xEnd: Double = {
                if rightToLeft {
                    return 0
                } else {
                    return bounds.width
                }
            }()
            let y = style.verticalInset + hourFloat * style.verticalDiff + offset
            context?.beginPath()
            context?.move(to: CGPoint(x: xStart, y: y))
            context?.addLine(to: CGPoint(x: xEnd, y: y))
            context?.strokePath()
            context?.restoreGState()

            if hour == hourToRemoveIndex { continue }

            let fontSize = style.font.pointSize
            let timeRect: CGRect = {
                var x: Double
                if rightToLeft {
                    x = bounds.width - 53
                } else {
                    x = 2
                }

                return CGRect(x: x,
                              y: hourFloat * style.verticalDiff + style.verticalInset - 7,
                              width: style.leadingInset - 8,
                              height: fontSize + 2)
            }()

            let timeString = NSString(string: time)
            timeString.draw(in: timeRect, withAttributes: attributes)

            if accentedMinute == 0 {
                continue
            }

            if hour == accentedHour {

                var x: Double
                if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                    x = bounds.width - (style.leadingInset + 7)
                } else {
                    x = 2
                }

                let timeRect = CGRect(x: x, y: hourFloat * style.verticalDiff + style.verticalInset - 7     + style.verticalDiff * (Double(accentedMinute) / 60),
                                      width: style.leadingInset - 8, height: fontSize + 2)

                let timeString = NSString(string: ":\(accentedMinute)")

                timeString.draw(in: timeRect, withAttributes: attributes)
            }
        }
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()
        recalculateEventLayout()
        layoutEvents()
        layoutNowLine()
        layoutAllDayEvents()
    }

    private func layoutNowLine() {
        if !isToday {
            nowLine.alpha = 0
        } else {
            bringSubviewToFront(nowLine)
            nowLine.alpha = 1
            let size = CGSize(width: bounds.size.width, height: 20)
            let rect = CGRect(origin: CGPoint.zero, size: size)
            nowLine.date = currentTime
            nowLine.frame = rect
            nowLine.center.y = dateToY(currentTime)
        }
    }

    private func layoutEvents() {
        if eventViews.isEmpty { return }

        for (idx, attributes) in regularLayoutAttributes.enumerated() {
            let descriptor = attributes.descriptor
            let eventView = eventViews[idx]
            eventView.frame = attributes.frame

            var x: Double
            if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                x = bounds.width - attributes.frame.minX - attributes.frame.width
            } else {
                x = attributes.frame.minX
            }

            eventView.frame = CGRect(x: x,
                                     y: attributes.frame.minY,
                                     width: attributes.frame.width - style.eventGap,
                                     height: attributes.frame.height - style.eventGap)
            eventView.updateWithDescriptor(event: descriptor)
        }
    }

    private func layoutAllDayEvents() {
        //add day view needs to be in front of the nowLine
        bringSubviewToFront(allDayView)
    }

    /**
     This will keep the allDayView as a stationary view in its superview

     - parameter yValue: since the superview is a scrollView, `yValue` is the
     `contentOffset.y` of the scroll view
     */
    public func offsetAllDayView(by yValue: Double) {
        if let topConstraint = self.allDayViewTopConstraint {
            topConstraint.constant = yValue
            layoutIfNeeded()
        }
    }

    private func recalculateEventLayout() {

        // only non allDay events need their frames to be set
        let sortedEvents = self.regularLayoutAttributes.sorted { (attr1, attr2) -> Bool in
            let start1 = attr1.descriptor.dateInterval.start
            let start2 = attr2.descriptor.dateInterval.start
            return start1 < start2
        }

        if style.eventsWillOverlap {
            layoutEventsAllowingOverlap(sortedEvents)
        } else {
            layoutEventsInColumns(sortedEvents)
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
    private func layoutEventsInColumns(_ sortedEvents: [EventLayoutAttributes]) {
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

            let columnWidth = calendarWidth / Double(columnEnds.count)
            for (index, event) in cluster.enumerated() {
                let interval = event.descriptor.dateInterval
                let startY = dateToY(interval.start)
                let endY = dateToY(interval.end)
                let x = style.leadingInset + Double(columnOfEvent[index]) * columnWidth
                event.frame = CGRect(x: x, y: startY, width: columnWidth, height: endY - startY)
            }
        }
    }

    /// The `style.eventsWillOverlap` layout: events in a group are drawn at equal width from the
    /// leading edge, deliberately overlapping one another.
    private func layoutEventsAllowingOverlap(_ sortedEvents: [EventLayoutAttributes]) {
        var groupsOfEvents = [[EventLayoutAttributes]]()
        var overlappingEvents = [EventLayoutAttributes]()

        for event in sortedEvents {
            if overlappingEvents.isEmpty {
                overlappingEvents.append(event)
                continue
            }

            guard let earliestEvent = overlappingEvents.first?.descriptor.dateInterval.start else { continue }
            let dateInterval = getDateInterval(date: earliestEvent)
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
                let startY = dateToY(event.descriptor.dateInterval.start)
                let endY = dateToY(event.descriptor.dateInterval.end)
                let floatIndex = Double(index)
                let x = style.leadingInset + floatIndex / totalCount * calendarWidth
                let equalWidth = calendarWidth / totalCount
                event.frame = CGRect(x: x, y: startY, width: equalWidth, height: endY - startY)
            }
        }
    }

    private func prepareEventViews() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        for _ in regularLayoutAttributes {
            let newView = pool.dequeue()
            if newView.superview == nil {
                addSubview(newView)
            }
            eventViews.append(newView)
        }
    }

    public func prepareForReuse() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        setNeedsDisplay()
    }

    // MARK: - Helpers

    public func dateToY(_ date: Date) -> Double {
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
        let fullTimelineHeight = 24 * style.verticalDiff
        let hour = component(component: .hour, from: date)
        let minute = component(component: .minute, from: date)
        let hourY = Double(hour) * style.verticalDiff + style.verticalInset
        let minuteY = Double(minute) * style.verticalDiff / 60
        return hourY + minuteY + fullTimelineHeight * dayOffset
    }

    public func yToDate(_ y: Double) -> Date {
        let timeValue = y - style.verticalInset
        var hour = Int(timeValue / style.verticalDiff)
        let fullHourPoints = Double(hour) * style.verticalDiff
        let minuteDiff = timeValue - fullHourPoints
        let minute = Int(minuteDiff / style.verticalDiff * 60)
        var dayOffset = 0
        if hour > 23 {
            dayOffset += 1
            hour -= 24
        } else if hour < 0 {
            dayOffset -= 1
            hour += 24
        }
        let offsetDate = calendar.date(byAdding: DateComponents(day: dayOffset),
                                       to: date)!
        let newDate = calendar.date(bySettingHour: hour,
                                    minute: minute.clamped(to: 0...59),
                                    second: 0,
                                    of: offsetDate)
        return newDate!
    }

    private func component(component: Calendar.Component, from date: Date) -> Int {
        calendar.component(component, from: date)
    }

    private func getDateInterval(date: Date) -> DateInterval {
        let earliestEventMintues = component(component: .minute, from: date)
        let splitMinuteInterval = style.splitMinuteInterval
        let minute = component(component: .minute, from: date)
        let minuteRange = (minute / splitMinuteInterval) * splitMinuteInterval
        let beginningRange = calendar.date(byAdding: .minute, value: -(earliestEventMintues - minuteRange), to: date)!
        let endRange = calendar.date(byAdding: .minute, value: splitMinuteInterval, to: beginningRange)!
        return DateInterval(start: beginningRange, end: endRange)
    }
}
