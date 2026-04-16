import AppKit
import CoreGraphics
import Foundation

// Global reference for CGEventTap callback
private var globalOverlay: Overlay?

// CGEventTap callback for learning mode
private func learnTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let globalOverlay = globalOverlay,
          let frontApp = NSWorkspace.shared.frontmostApplication,
          let bundleId = frontApp.bundleIdentifier else { return Unmanaged.passRetained(event) }

    // Filter out VibeMove's own clicks
    if bundleId == Bundle.main.bundleIdentifier { return Unmanaged.passRetained(event) }

    let loc = event.location
    SystemControl.Application.recordInputLocation(bundleId: bundleId, at: loc)
    globalOverlay.flash("📍 已记录: \(frontApp.localizedName ?? bundleId)")
    NSSound(named: "Tink")?.play()

    return Unmanaged.passRetained(event)
}

/// Floating HUD that draws a body skeleton + status text in a screen corner.
/// Lets the user see what the camera sees and which gesture is currently classified.
final class Overlay {
    private let window: NSWindow
    private let view: SkeletonView
    private let learnButton: NSButton
    private let helpButton: NSButton
    private let quitButton: NSButton
    private let centerWindow: NSWindow
    private let centerView: CenterNotificationView
    private let helpWindow: NSWindow
    private let helpView: HelpOverlayView
    private var learnEventTap: CFMachPort?

    var onLearnModeToggle: ((Bool) -> Void)?
    private(set) var isLearning = false

    init() {
        let size = NSSize(width: 140, height: 180)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        let frame = NSRect(origin: origin, size: size)

        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true // Fix jitter by using native dragging
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.backgroundColor = .clear

        view = SkeletonView(frame: NSRect(origin: .zero, size: size))

        // Create buttons (shrunk and side-by-side)
        helpButton = NSButton(title: "❓ 帮助", target: nil, action: nil)
        helpButton.bezelStyle = .rounded
        helpButton.font = NSFont.systemFont(ofSize: 9)
        helpButton.frame = NSRect(x: 12, y: 8, width: 54, height: 20)

        learnButton = NSButton(title: "⚙ 配置", target: nil, action: nil)
        learnButton.bezelStyle = .rounded
        learnButton.font = NSFont.systemFont(ofSize: 9)
        learnButton.frame = NSRect(x: 74, y: 8, width: 54, height: 20)

        // Create quit button (top right)
        quitButton = NSButton(title: "✕", target: nil, action: nil)
        quitButton.bezelStyle = .circular
        quitButton.isBordered = false
        quitButton.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        quitButton.frame = NSRect(x: size.width - 22, y: size.height - 22, width: 16, height: 16)
        quitButton.contentTintColor = NSColor.white.withAlphaComponent(0.4)

        window.contentView = view
        view.addSubview(helpButton)
        view.addSubview(learnButton)
        view.addSubview(quitButton)

        // Help window (HUD list)
        let helpSize = NSSize(width: 260, height: 240)
        let helpFrame = NSRect(
            x: screen.midX - helpSize.width / 2,
            y: screen.midY - helpSize.height / 2,
            width: helpSize.width,
            height: helpSize.height
        )
        helpWindow = NSWindow(contentRect: helpFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        helpWindow.level = .floating
        helpWindow.isOpaque = false
        helpWindow.hasShadow = true
        helpWindow.backgroundColor = .clear
        helpWindow.alphaValue = 0 // Hidden by default
        helpWindow.isMovableByWindowBackground = true

        helpView = HelpOverlayView(frame: NSRect(origin: .zero, size: helpSize))
        helpWindow.contentView = helpView

        // Center notification window (shrunk by half)
        let centerSize = NSSize(width: 200, height: 60)
        let centerOrigin = NSPoint(
            x: screen.midX - centerSize.width / 2,
            y: screen.minY + 80
        )
        let centerFrame = NSRect(origin: centerOrigin, size: centerSize)

        centerWindow = NSWindow(
            contentRect: centerFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        centerWindow.level = .floating
        centerWindow.isOpaque = false
        centerWindow.hasShadow = false
        centerWindow.ignoresMouseEvents = true
        centerWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        centerWindow.backgroundColor = .clear
        centerWindow.alphaValue = 0

        centerView = CenterNotificationView(frame: NSRect(origin: .zero, size: centerSize))
        centerWindow.contentView = centerView

        // Configure buttons
        helpButton.target = self
        helpButton.action = #selector(helpButtonTapped)
        learnButton.target = self
        learnButton.action = #selector(learnButtonTapped)
        quitButton.target = NSApp
        quitButton.action = #selector(NSApplication.terminate(_:))

        DispatchQueue.main.async {
            self.window.orderFrontRegardless()
            self.centerWindow.orderFrontRegardless()
            self.helpWindow.orderFrontRegardless() // Ensure help window is in hierarchy
        }

        // Set global reference for CGEventTap callback
        globalOverlay = self
    }

    func updateBody(landmarks: BodyLandmarks?, status: String) {
        DispatchQueue.main.async {
            self.view.bodyLandmarks = landmarks
            self.view.handLandmarks = nil
            self.view.statusText = status
            self.view.needsDisplay = true
        }
    }

    func updateHand(landmarks: HandLandmarks?, status: String) {
        DispatchQueue.main.async {
            self.view.handLandmarks = landmarks
            self.view.bodyLandmarks = nil
            self.view.statusText = status
            self.view.needsDisplay = true
        }
    }

    func flash(_ action: String) {
        DispatchQueue.main.async {
            self.view.lastAction = action
            self.view.lastActionExpiry = Date().addingTimeInterval(1.2)
            self.view.needsDisplay = true

            // Show center notification
            self.centerView.setText(action)
            self.centerView.needsDisplay = true
            self.centerWindow.alphaValue = 1.0

            // Fade out after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                self.centerWindow.animator().alphaValue = 0
                NSAnimationContext.endGrouping()
            }
        }
    }

    func setLearning(_ on: Bool) {
        isLearning = on
        DispatchQueue.main.async {
            self.learnButton.title = on ? "🔴 停止" : "⚙ 配置"
            if on {
                self.learnButton.bezelColor = NSColor.systemRed
            } else {
                self.learnButton.bezelColor = nil
            }
        }
    }

    @objc private func helpButtonTapped() {
        let isShowing = helpWindow.alphaValue > 0
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.2
        helpWindow.animator().alphaValue = isShowing ? 0 : 1.0
        NSAnimationContext.endGrouping()
    }

    @objc private func learnButtonTapped() {
        isLearning = !isLearning
        setLearning(isLearning)

        if isLearning {
            startLearning()
        } else {
            stopLearning()
        }

        onLearnModeToggle?(isLearning)
    }

    private func startLearning() {
        guard learnEventTap == nil else { return }

        let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
            callback: learnTapCallback,
            userInfo: nil
        )

        if let tap = tap {
            learnEventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[LearnMode] 已启动学习模式")
        }
    }

    private func stopLearning() {
        guard let tap = learnEventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        learnEventTap = nil
        print("[LearnMode] 已停止学习模式")
    }
}

final class SkeletonView: NSView {
    var bodyLandmarks: BodyLandmarks?
    var handLandmarks: HandLandmarks?
    var statusText: String = "—"
    var lastAction: String = ""
    var lastActionExpiry: Date = .distantPast

    override var isFlipped: Bool { false }  // keep Vision's bottom-left origin
 
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background: rounded translucent dark panel.
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor(white: 0, alpha: 0.72).setFill()
        bg.fill()

        let topPadding: CGFloat = 25
        let bottomPadding: CGFloat = 45
        let drawArea = NSRect(
            x: 16,
            y: bottomPadding,
            width: bounds.width - 32,
            height: bounds.height - topPadding - bottomPadding
        )
 
        if let lm = bodyLandmarks {
            drawBodySkeleton(lm, in: drawArea, ctx: ctx)
        } else if let lm = handLandmarks {
            drawHandSkeleton(lm, in: drawArea, ctx: ctx)
        } else {
            drawNoBody(in: drawArea)
        }

        drawHeader()
        drawFooter()
    }


    // MARK: drawing helpers

    private func drawBodySkeleton(_ lm: BodyLandmarks, in area: NSRect, ctx: CGContext) {
        let segs: [(CGPoint, CGPoint)] = [
            (lm.leftShoulder, lm.rightShoulder),
            (lm.leftShoulder, lm.leftHip),
            (lm.rightShoulder, lm.rightHip),
            (lm.leftHip, lm.rightHip),
            (lm.leftShoulder, lm.leftWrist),
            (lm.rightShoulder, lm.rightWrist),
            (lm.leftHip, lm.leftKnee),
            (lm.rightHip, lm.rightKnee),
        ]
        let joints: [CGPoint] = [
            lm.nose,
            lm.leftShoulder, lm.rightShoulder,
            lm.leftHip, lm.rightHip,
            lm.leftWrist, lm.rightWrist,
            lm.leftKnee, lm.rightKnee,
        ]
        drawLines(segs, in: area, ctx: ctx, color: NSColor.systemGreen.withAlphaComponent(0.85))
        drawDots(joints, in: area, color: NSColor.systemGreen)
    }

    private func drawHandSkeleton(_ lm: HandLandmarks, in area: NSRect, ctx: CGContext) {
        let segs: [(CGPoint, CGPoint)] = [
            (lm.wrist, lm.thumbCMC), (lm.thumbCMC, lm.thumbMP), (lm.thumbMP, lm.thumbIP), (lm.thumbIP, lm.thumbTip),
            (lm.wrist, lm.indexMCP), (lm.indexMCP, lm.indexPIP), (lm.indexPIP, lm.indexDIP), (lm.indexDIP, lm.indexTip),
            (lm.wrist, lm.middleMCP), (lm.middleMCP, lm.middleTip),
            (lm.wrist, lm.ringMCP), (lm.ringMCP, lm.ringTip),
            (lm.wrist, lm.littleMCP), (lm.littleMCP, lm.littleTip),
        ]
        let joints: [CGPoint] = [
            lm.wrist,
            lm.thumbCMC, lm.thumbMP, lm.thumbIP, lm.thumbTip,
            lm.indexMCP, lm.indexPIP, lm.indexDIP, lm.indexTip,
            lm.middleMCP, lm.middleTip,
            lm.ringMCP, lm.ringTip,
            lm.littleMCP, lm.littleTip,
        ]
        drawLines(segs, in: area, ctx: ctx, color: NSColor.systemTeal.withAlphaComponent(0.85))
        drawDots(joints, in: area, color: NSColor.systemTeal)
    }

    private func drawNoBody(in area: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]
        let str = NSAttributedString(string: "no person", attributes: attrs)
        let size = str.size()
        let pt = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        str.draw(at: pt)
    }

    private func drawLines(_ segs: [(CGPoint, CGPoint)], in area: NSRect, ctx: CGContext, color: NSColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        for (a, b) in segs {
            guard isValid(a), isValid(b) else { continue }
            let pa = mapPoint(a, in: area)
            let pb = mapPoint(b, in: area)
            ctx.move(to: pa)
            ctx.addLine(to: pb)
        }
        ctx.strokePath()
    }

    private func drawDots(_ pts: [CGPoint], in area: NSRect, color: NSColor) {
        color.setFill()
        for p in pts {
            guard isValid(p) else { continue }
            let m = mapPoint(p, in: area)
            let r: CGFloat = 2.0
            let rect = NSRect(x: m.x - r, y: m.y - r, width: 2 * r, height: 2 * r)
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private func mapPoint(_ p: CGPoint, in area: NSRect) -> NSPoint {
        // Vision normalized (0..1, bottom-left origin) → view coords inside `area`.
        // Mirror x so it feels like a mirror to the user.
        let x = area.minX + (1.0 - p.x) * area.width
        let y = area.minY + p.y * area.height
        return NSPoint(x: x, y: y)
    }

    private func isValid(_ p: CGPoint) -> Bool {
        return p.x > 0.001 || p.y > 0.001
    }

    private func drawHeader() {
        let title = "牛马健身"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: 16, y: bounds.maxY - 20))
    }

    private func drawFooter() {
        let now = Date()
        guard now < lastActionExpiry else { return }
        let alpha = max(0, min(1, lastActionExpiry.timeIntervalSince(now) / 1.2))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.systemYellow.withAlphaComponent(alpha),
        ]
        let str = NSAttributedString(string: "→ \(lastAction)", attributes: attrs)
        str.draw(at: NSPoint(x: 16, y: 32))
    }
}

final class CenterNotificationView: NSView {
    private var notificationText: String = ""

    override var isFlipped: Bool { false }

    func setText(_ text: String) {
        notificationText = text
    }

    override func draw(_ dirtyRect: NSRect) {
        // Background: rounded translucent dark panel
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20)
        NSColor(white: 0, alpha: 0.85).setFill()
        bg.fill()

        // Text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: notificationText, attributes: attrs)
        let size = str.size()
        let pt = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        str.draw(at: pt)
    }
}

final class HelpOverlayView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor(white: 0, alpha: 0.95).setFill()
        bg.fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.systemYellow,
        ]
        let title = "牛马健身 健身手册"
        title.draw(at: NSPoint(x: 20, y: 15), withAttributes: titleAttrs)

        let helpItems = [
            ("🏋️ 深蹲 (深下潜)", "语音输入 (Fn 按下)"),
            ("👏 拍手 (胸前)", "Enter (确认/发送)"),
            ("❌ 双手交叉 (胸前)", "Escape (取消)"),
            ("👊 左右出拳", "← / → 方向键"),
            ("💪 侧平举 (单臂)", "Tab 切换标签"),
            ("⛹️ 跳跃 (重心上升)", "Enter (快速发送)"),
            ("🤚 右手举过头顶", "鼠标点击屏幕中心"),
            ("⚙ 配置输入框", "学习模式：点击一次输入框"),
        ]

        var currentY: CGFloat = 45
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)

        for (gesture, action) in helpItems {
            let gAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.systemGreen]
            let aAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            
            gesture.draw(at: NSPoint(x: 20, y: currentY), withAttributes: gAttrs)
            action.draw(at: NSPoint(x: 130, y: currentY), withAttributes: aAttrs)
            currentY += 21
        }

        let closeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
        ]
        "再次点击 [❓ 帮助] 关闭窗口".draw(at: NSPoint(x: 20, y: bounds.height - 22), withAttributes: closeAttrs)
    }
}
