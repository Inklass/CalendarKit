import XCTest
@testable import CalendarKit

/// A navy all-day event ("Week 4") was unreadable in dark mode.
///
/// Dark mode drew the text in the event's own colour on a background of that colour dimmed,
/// so a dark colour came out navy on navy. Dark colours are now lifted towards white; bright
/// ones are left alone.
final class EventDarkThemeTextColorTests: XCTestCase {

    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func darkText(for color: UIColor) -> UIColor {
        let event = Event()
        event.color = color
        return event.textColor.resolvedColor(with: dark)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func testANavyEventIsLiftedSoItReadsOnItsBackground() {
        let navy = UIColor(red: 0, green: 0, blue: 0.5, alpha: 1)
        let text = darkText(for: navy)
        XCTAssertGreaterThan(luminance(text), 0.5)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        text.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(b, r, "the lifted colour keeps its blue hue")
    }

    func testABrightEventKeepsItsOwnColour() {
        let lightGreen = UIColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1)
        XCTAssertEqual(darkText(for: lightGreen), lightGreen)
    }

    func testLightModeIsUnchanged() {
        let navy = UIColor(red: 0, green: 0, blue: 0.5, alpha: 1)
        let event = Event()
        event.color = navy
        let light = event.textColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertLessThan(luminance(light), luminance(navy))
    }
}
