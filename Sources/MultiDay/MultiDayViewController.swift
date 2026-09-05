import UIKit

/// Drop-in host for `MultiDayView`, mirroring `DayViewController` so a screen can switch
/// between one day and several by changing which one it subclasses.
open class MultiDayViewController: UIViewController, EventDataSource, MultiDayViewDelegate {

    public lazy var multiDayView: MultiDayView = MultiDayView(calendar: calendar)

    public var dataSource: EventDataSource? {
        get { multiDayView.dataSource }
        set { multiDayView.dataSource = newValue }
    }

    public var delegate: MultiDayViewDelegate? {
        get { multiDayView.delegate }
        set { multiDayView.delegate = newValue }
    }

    public var calendar = Calendar.autoupdatingCurrent {
        didSet { multiDayView.calendar = calendar }
    }

    /// Days on screen at once.
    public var numberOfVisibleDays: Int {
        get { multiDayView.numberOfVisibleDays }
        set { multiDayView.numberOfVisibleDays = newValue }
    }

    open override func loadView() {
        view = multiDayView
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout = []
        view.tintColor = SystemColors.systemRed
        dataSource = self
        delegate = self
        multiDayView.reloadData()
    }

    // MARK: - CalendarKit API

    open func move(to date: Date, animated: Bool = false) {
        multiDayView.move(to: date, animated: animated)
    }

    open func reloadData() {
        multiDayView.reloadData()
    }

    open func updateStyle(_ newStyle: CalendarStyle) {
        multiDayView.updateStyle(newStyle)
    }

    open func eventsForDate(_ date: Date) -> [EventDescriptor] {
        [Event]()
    }

    // MARK: - MultiDayViewDelegate

    open func multiDayViewDidSelectEventView(_ eventView: EventView) {}
    open func multiDayViewDidLongPressEventView(_ eventView: EventView) {}
    open func multiDayView(_ multiDayView: MultiDayView, didTapTimelineAt date: Date) {}
    open func multiDayView(_ multiDayView: MultiDayView, didLongPressTimelineAt date: Date) {}
    open func multiDayView(_ multiDayView: MultiDayView, didMoveTo date: Date) {}
}
