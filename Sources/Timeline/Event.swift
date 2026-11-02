import UIKit

public final class Event: EventDescriptor {
    public var dateInterval = DateInterval()
    public var isAllDay = false
    public var text = ""
    public var attributedText: NSAttributedString?
    public var lineBreakMode: NSLineBreakMode?
    public var color = SystemColors.systemBlue {
        didSet {
            updateColors()
        }
    }
    public var backgroundColor = SystemColors.systemBlue.withAlphaComponent(0.3)
    public var textColor = SystemColors.label
    public var font = UIFont.boldSystemFont(ofSize: 12)
    public var userInfo: Any?
    public weak var editedEvent: EventDescriptor? {
        didSet {
            updateColors()
        }
    }

    public init() {}

    public func makeEditable() -> Event {
        let cloned = Event()
        cloned.dateInterval = dateInterval
        cloned.isAllDay = isAllDay
        cloned.text = text
        cloned.attributedText = attributedText
        cloned.lineBreakMode = lineBreakMode
        cloned.color = color
        cloned.backgroundColor = backgroundColor
        cloned.textColor = textColor
        cloned.userInfo = userInfo
        cloned.editedEvent = self
        return cloned
    }

    public func commitEditing() {
        guard let edited = editedEvent else { return }
        edited.dateInterval = dateInterval
    }

    private func updateColors() {
        (editedEvent != nil) ? applyEditingColors() : applyStandardColors()
    }

    /// Colors used when event is not in editing mode
    private func applyStandardColors() {
        backgroundColor = dynamicStandardBackgroundColor()
        textColor = dynamicStandardTextColor()
    }

    /// Colors used in editing mode
    private func applyEditingColors() {
        backgroundColor = color.withAlphaComponent(0.95)
        textColor = .white
    }

    /// Dynamic color that changes depending on the user interface style (dark / light)
    private func dynamicStandardBackgroundColor() -> UIColor {
        let light = backgroundColorForLightTheme(baseColor: color)
        let dark = backgroundColorForDarkTheme(baseColor: color)
        return dynamicColor(light: light, dark: dark)
    }

    /// Dynamic color that changes depending on the user interface style (dark / light)
    private func dynamicStandardTextColor() -> UIColor {
        let light = textColorForLightTheme(baseColor: color)
        let dark = textColorForDarkTheme(baseColor: color)
        return dynamicColor(light: light, dark: dark)
    }

    /// Dark mode draws the text in the event's own colour, on a background that is the same
    /// colour dimmed. A dark colour — a navy all-day "Week 4" — then reads as navy on navy, so
    /// a dark colour is lifted towards white, keeping its hue. Colours bright enough to read
    /// stay exactly as they were.
    private func textColorForDarkTheme(baseColor: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard baseColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return baseColor }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luminance < 0.5 else { return baseColor }
        let lift: CGFloat = 0.6
        return UIColor(red: r + (1 - r) * lift, green: g + (1 - g) * lift, blue: b + (1 - b) * lift, alpha: a)
    }

    private func textColorForLightTheme(baseColor: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * 0.4, alpha: a)
    }

    private func backgroundColorForLightTheme(baseColor: UIColor) -> UIColor {
        baseColor.withAlphaComponent(0.3)
    }

    private func backgroundColorForDarkTheme(baseColor: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * 0.4, alpha: a * 0.8)
    }

    private func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13, tvOS 13, *) {
            return UIColor { traitCollection in
                let interfaceStyle = traitCollection.userInterfaceStyle
                switch interfaceStyle {
                case .dark:
                    return dark
                default:
                    return light
                }
            }
        } else {
            return light
        }
    }
}
