import UIKit

open class EventView: UIView {
    public var descriptor: EventDescriptor?
    public var color = SystemColors.label
    
    public var contentHeight: Double {
        textView.frame.height
    }
    
    public private(set) lazy var textView: UITextView = {
        let view = UITextView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.clipsToBounds = true
        // UITextView ships with an 8pt inset above and below the text. On a five-minute event
        // the whole box is about 4pt tall, so the single line was laid out entirely below it
        // and then clipped away — the title simply did not appear. Only the vertical inset is
        // trimmed; `lineFragmentPadding` is horizontal and is left alone so the leading gap
        // between the accent bar and the title stays as it was.
        view.textContainerInset = UIEdgeInsets(top: 1, left: 0, bottom: 1, right: 2)
        return view
    }()
    
    /// Resize Handle views showing up when editing the event.
    /// The top handle has a tag of `0` and the bottom has a tag of `1`
    public private(set) lazy var eventResizeHandles = [EventResizeHandleView(), EventResizeHandleView()]

    /// When an event is too short to fit even one line, its title is centred on the event and
    /// allowed to spill a little past it rather than being clipped away entirely. `EventView`
    /// does not clip its own bounds, so the title stays readable.
    ///
    /// Set to `false` to clip instead, which is the pre-fix behaviour.
    public var showsTitleForVeryShortEvents = true

    /// The wrapping mode the descriptor asked for, restored whenever more than one line fits.
    private var preferredLineBreakMode: NSLineBreakMode?
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }
    
    private func configure() {
        clipsToBounds = false
        color = tintColor
        addSubview(textView)
        
        for (idx, handle) in eventResizeHandles.enumerated() {
            handle.tag = idx
            addSubview(handle)
        }
    }
    
    public func updateWithDescriptor(event: EventDescriptor) {
        if let attributedText = event.attributedText {
            textView.attributedText = attributedText
            textView.setNeedsLayout()
        } else {
            textView.text = event.text
            textView.textColor = event.textColor
            textView.font = event.font
        }
        preferredLineBreakMode = event.lineBreakMode
        descriptor = event
        backgroundColor = .clear
        layer.backgroundColor = event.backgroundColor.cgColor
        layer.cornerRadius = 5
        color = event.color
        eventResizeHandles.forEach{
            $0.borderColor = event.color
            $0.isHidden = event.editedEvent == nil
        }
        drawsShadow = event.editedEvent != nil
        setNeedsDisplay()
        setNeedsLayout()
    }
    
    public func animateCreation() {
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        func scaleAnimation() {
            transform = .identity
        }
        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       usingSpringWithDamping: 0.2,
                       initialSpringVelocity: 10,
                       options: [],
                       animations: scaleAnimation,
                       completion: nil)
    }
    
    /**
     Custom implementation of the hitTest method is needed for the tap gesture recognizers
     located in the ResizeHandleView to work.
     Since the ResizeHandleView could be outside of the EventView's bounds, the touches to the ResizeHandleView
     are ignored.
     In the custom implementation the method is recursively invoked for all of the subviews,
     regardless of their position in relation to the Timeline's bounds.
     */
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for resizeHandle in eventResizeHandles {
            if let subSubView = resizeHandle.hitTest(convert(point, to: resizeHandle), with: event) {
                return subSubView
            }
        }
        return super.hitTest(point, with: event)
    }
    
    override open func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.interpolationQuality = .none
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.translateBy(x: 0, y: 0.5)
        let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
        let x: Double = leftToRight ? 0 : frame.width - 1.0  // 1 is the line width
        let y: Double = 0
        let hOffset: Double = 3
        let vOffset: Double = 5
        context.beginPath()
        context.move(to: CGPoint(x: x + 2 * hOffset, y: y + vOffset))
        context.addLine(to: CGPoint(x: x + 2 * hOffset, y: (bounds).height - vOffset))
        context.strokePath()
        context.restoreGState()
    }
    
    private var drawsShadow = false
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        layoutTextView()
        let first = eventResizeHandles.first
        let last = eventResizeHandles.last
        let radius: Double = 40
        let yPad: Double =  -radius / 2
        let width = bounds.width
        let height = bounds.height
        let size = CGSize(width: radius, height: radius)
        first?.frame = CGRect(origin: CGPoint(x: width - radius - layoutMargins.right, y: yPad),
                              size: size)
        last?.frame = CGRect(origin: CGPoint(x: layoutMargins.left, y: height - yPad - radius),
                             size: size)
        
        if drawsShadow {
            applySketchShadow(alpha: 0.13,
                              blur: 10)
        }
    }
    
    /// Centres the title in the event and guarantees at least one legible line.
    ///
    /// Two separate faults used to show here. Short events lost their title completely: the
    /// text view was given the event's full height, and once that height fell below a line the
    /// text was laid out past the bottom edge and clipped. Everything else was top-aligned, so
    /// a one-line title in a tall event floated against the top rather than reading as part of
    /// the block.
    private func layoutTextView() {
        let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
        let x = rightToLeft ? bounds.minX : bounds.minX + 8
        let width = max(0, rightToLeft ? bounds.width - 3 : bounds.width - 6)

        // The part of the event actually on screen. An event that began on a previous day is
        // drawn with a negative origin, so only what sits below y = 0 can hold text.
        var visible = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
        if frame.minY < 0 {
            visible.origin.y = -frame.minY
            visible.size.height += frame.minY
        }

        let lineHeight = resolvedFont.lineHeight
        let chromeHeight = textView.textContainerInset.top + textView.textContainerInset.bottom
        let oneLine = lineHeight + chromeHeight

        // Drop to a single truncated line as soon as a second one would not fit, so a long
        // title cannot wrap itself out of a short event.
        let linesThatFit = max(1, Int((visible.height - chromeHeight) / lineHeight))
        textView.textContainer.maximumNumberOfLines = linesThatFit
        textView.textContainer.lineBreakMode = linesThatFit == 1
            ? .byTruncatingTail
            : (preferredLineBreakMode ?? .byWordWrapping)

        let naturalHeight = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let floor = showsTitleForVeryShortEvents ? oneLine : 0
        let height = max(min(naturalHeight, visible.height), floor)

        textView.frame = CGRect(x: visible.minX,
                                y: visible.midY - height / 2,
                                width: width,
                                height: height)
    }

    /// `textView.font` is nil while an `attributedText` is in use, so fall back to what the
    /// descriptor asked for before giving up on a system default.
    private var resolvedFont: UIFont {
        textView.font ?? descriptor?.font ?? UIFont.boldSystemFont(ofSize: 12)
    }

    private func applySketchShadow(
        color: UIColor = .black,
        alpha: Float = 0.5,
        x: Double = 0,
        y: Double = 2,
        blur: Double = 4,
        spread: Double = 0)
    {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = alpha
        layer.shadowOffset = CGSize(width: x, height: y)
        layer.shadowRadius = blur / 2.0
        if spread == 0 {
            layer.shadowPath = nil
        } else {
            let dx = -spread
            let rect = bounds.insetBy(dx: dx, dy: dx)
            layer.shadowPath = UIBezierPath(rect: rect).cgPath
        }
    }
}
