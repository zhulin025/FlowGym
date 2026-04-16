import AppKit
import AVFoundation
import CoreGraphics
import Foundation

setbuf(stdout, nil)

// Stability / debounce.
let neededFrames = 3
let rearmFrames = 5
let pinchNeededFrames = 2
let pinchCooldownSeconds: TimeInterval = 0.8

// Swipe-down config.
let swipeWindowSeconds: TimeInterval = 0.4
let swipeMinDropRatio: CGFloat = 0.25
let swipeCooldownSeconds: TimeInterval = 1.0

// Squat config.
let squatWindowSeconds: TimeInterval = 2.0
let squatMinDipRatio: CGFloat = 0.60   // as fraction of torso length (reduced from 0.80 for better sensitivity)
let squatRiseBackRatio: CGFloat = 0.10
let squatCooldownSeconds: TimeInterval = 1.5
let squatMinFrames = 10

final class EdgeTrigger {
    private var streak = 0
    private var awayStreak = 999
    private var armed = true
    let needed: Int
    let rearm: Int
    init(needed: Int = neededFrames, rearm: Int = rearmFrames) {
        self.needed = needed
        self.rearm = rearm
    }

    func update(_ active: Bool) -> Bool {
        if active {
            awayStreak = 0
            streak += 1
            if armed && streak >= needed {
                armed = false
                return true
            }
        } else {
            streak = 0
            awayStreak += 1
            if awayStreak >= rearm {
                armed = true
            }
        }
        return false
    }
}

// MARK: - Hand mode controller

final class HandController {
    weak var overlay: Overlay?

    private let thumbsUp = EdgeTrigger()
    private let thumbsDown = EdgeTrigger()
    private var isFnActive = false
    private let pointIndex = EdgeTrigger()
    private let peace = EdgeTrigger()
    private let rock = EdgeTrigger()

    private var pinchStreak = 0
    private var lastPinchAt: Date = .distantPast

    private var wristHistory: [(Date, CGFloat)] = []
    private var lastSwipeAt: Date = .distantPast

    func handle(_ gesture: Gesture, wristY: CGFloat?, landmarks: HandLandmarks?) {
        overlay?.updateHand(landmarks: landmarks, status: gesture.rawValue)
        if let y = wristY {
            let now = Date()
            wristHistory.append((now, y))
            wristHistory = wristHistory.filter { now.timeIntervalSince($0.0) <= swipeWindowSeconds }
        } else {
            wristHistory.removeAll()
        }

        if thumbsUp.update(gesture == .thumbsUp) {
            if !isFnActive {
                Keyboard.fnDown()
                isFnActive = true
                Feedback.play("Tink")
                overlay?.flash("Fn Start (👍)")
                print("[thumbsUp] Fn DOWN")
            }
        }
        if thumbsDown.update(gesture == .thumbsDown) {
            if isFnActive {
                Keyboard.fnUp()
                isFnActive = false
                Feedback.play("Funk")
                overlay?.flash("Fn Stop (👎)")
                print("[thumbsDown] Fn UP")
            }
        }

        if pointIndex.update(gesture == .pointIndex) {
            Keyboard.tapCmdA()
            Feedback.play("Morse")
            overlay?.flash("⌘A")
            print("[pointIndex] Cmd+A")
        }
        if peace.update(gesture == .peace) {
            Keyboard.tapCmdV()
            Feedback.play("Glass")
            overlay?.flash("⌘V")
            print("[peace] Cmd+V")
        }
        if rock.update(gesture == .rock) {
            Keyboard.tapCmdC()
            Feedback.play("Hero")
            overlay?.flash("⌘C")
            print("[rock] Cmd+C")
        }

        if gesture == .pinch {
            pinchStreak += 1
            if pinchStreak >= pinchNeededFrames,
               Date().timeIntervalSince(lastPinchAt) > pinchCooldownSeconds {
                lastPinchAt = Date()
                pinchStreak = 0
                Keyboard.tapReturn()
                Feedback.play("Pop")
                overlay?.flash("Enter")
                print("[pinch] Enter")
            }
        } else {
            pinchStreak = 0
        }

        if gesture == .openPalm {
            detectSwipeDown()
        }
    }

    private func detectSwipeDown() {
        guard wristHistory.count >= 4 else { return }
        guard Date().timeIntervalSince(lastSwipeAt) > swipeCooldownSeconds else { return }
        let maxY = wristHistory.map { $0.1 }.max() ?? 0
        let minY = wristHistory.map { $0.1 }.min() ?? 0
        let drop = maxY - minY
        guard drop >= swipeMinDropRatio else { return }
        guard let latest = wristHistory.last?.1, latest <= minY + 0.02 else { return }
        lastSwipeAt = Date()
        wristHistory.removeAll()
        Keyboard.tapEscape()
        Feedback.play("Funk")
        overlay?.flash("Esc")
        print("[swipeDown] Escape")
    }
}

// MARK: - Body mode controller

final class BodyController {
    weak var overlay: Overlay?

    private var isFnActive = false
    private var standingY: CGFloat? = nil
    private let clap = EdgeTrigger(needed: 1, rearm: 8)
    private let crossArms = EdgeTrigger(needed: 2, rearm: 8)
    private let kneeUp = EdgeTrigger(needed: 2, rearm: 6)
    private let sideLeanLeft = EdgeTrigger(needed: 3, rearm: 10)
    private let sideLeanRight = EdgeTrigger(needed: 3, rearm: 10)
    private let punchLeft = EdgeTrigger(needed: 2, rearm: 15)
    private let punchRight = EdgeTrigger(needed: 2, rearm: 15)
    private let sideLiftLeft = EdgeTrigger(needed: 1, rearm: 8)
    private let sideLiftRight = EdgeTrigger(needed: 1, rearm: 8)
    private let jump = EdgeTrigger(needed: 3, rearm: 15)
    private let raiseRight = EdgeTrigger(needed: 3, rearm: 15)
    private var hipHistory: [(Date, CGFloat, CGFloat)] = []  // (time, hipY, torsoLen)

    // Jump detection state
    private var ankleBaselineY: CGFloat? = nil
    private var ankleBaselineHistory: [(Date, CGFloat)] = []
    private var hipBaselineY: CGFloat? = nil
    private var hipBaselineHistory: [(Date, CGFloat)] = []
    private let jumpBaselineWindowSeconds: TimeInterval = 1.0
    private var lastJumpAt: Date = .distantPast
    private let jumpCooldownSeconds: TimeInterval = 1.0

    private var lastSquatAt: Date = .distantPast
    private var frameCount = 0
    private var noBodyStreak = 0

    // Arm reset tracking: arm must be lowered before can punch again
    private var leftArmWasLow = true   // Allow first punch
    private var rightArmWasLow = true

    // raiseRight must have hand lowered below shoulder before next trigger (just like punch)
    private var rightArmWasRaised = false  // Tracks if right arm was at raise height

    // Arm punch height history: track if arm stays at punch height for long enough
    private var leftPunchHeightHistory: [(Date, Bool)] = []  // (time, isAtPunchHeight)
    private var rightPunchHeightHistory: [(Date, Bool)] = []  // (time, isAtPunchHeight)
    private let punchHeightWindowSeconds: TimeInterval = 1.2
    private let punchMinStaySeconds: TimeInterval = 0.2  // Must stay at punch height for 0.2+ sec to avoid being a raise motion

    // raiseRight history: track if arm stays at raise height
    private var raiseRightHeightHistory: [(Date, Bool)] = []  // (time, isAtRaiseHeight)
    private let raiseRightHeightWindowSeconds: TimeInterval = 0.5
    private let raiseRightMinStaySeconds: TimeInterval = 0.1  // Must stay at raise height for 0.1+ sec
    private var lastRaiseRightAt: Date = .distantPast
    private let raiseRightCooldownSeconds: TimeInterval = 0.8  // Cooldown between triggers

    func handle(_ lm: BodyLandmarks?) {
        frameCount += 1
        guard let lm = lm else {
            overlay?.updateBody(landmarks: nil, status: "no body")
            hipHistory.removeAll()
            ankleBaselineHistory.removeAll()
            _ = clap.update(false)
            _ = crossArms.update(false)
            noBodyStreak += 1
            if frameCount % 30 == 0 {
                // print("[debug] no body in frame (\(noBodyStreak) frames)")
            }
            return
        }
        noBodyStreak = 0

        // Update arm reset state: mark as "low" when wrist is below shoulder
        if lm.leftWrist.y < lm.leftShoulder.y - 0.12 {
            leftArmWasLow = true
        }

        // Right arm tracking for raiseRight gesture
        if lm.rightWrist.y < lm.rightShoulder.y - 0.12 {
            rightArmWasLow = true
            rightArmWasRaised = false  // When right arm is lowered, allow raiseRight to be triggered again
        }
        // Note: we don't set rightArmWasRaised = true here; it gets set when raiseRight actually triggers

        let gesture = BodyGestureClassifier.classify(lm)
        overlay?.updateBody(landmarks: lm, status: gesture.rawValue)
        if frameCount % 30 == 0 {
            let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
            let shoY = (lm.leftShoulder.y + lm.rightShoulder.y) / 2
            let torso = shoY - hipY
            let maxH = hipHistory.map { $0.1 }.max() ?? 0
            let minH = hipHistory.map { $0.1 }.min() ?? 0
            let dip = maxH - minH
            let dipRatio = torso > 0 ? dip / torso : 0
            print(String(format: "[debug] body OK  hipY=%.3f torso=%.3f history=%d dip=%.3f (%.0f%% of torso) gesture=%@",
                         Double(hipY), Double(torso), hipHistory.count, Double(dip), Double(dipRatio * 100), gesture.rawValue))
        }

        if clap.update(gesture == .clap) {
            Keyboard.tapReturn()
            Feedback.play("Pop")
            overlay?.flash("👏 击掌")
            print("[clap] Enter")
        }
        if crossArms.update(gesture == .crossArms) {
            Keyboard.tapEscape()
            Feedback.play("Funk")
            overlay?.flash("❌ 双臂交叉")
            print("[crossArms] Escape")
        }
        if kneeUp.update(gesture == .kneeUp) {
            // Determine scroll direction based on wrist height:
            // If wrist is above shoulder → scroll up; otherwise → scroll down (default)
            let leftWristAboveShoulder = lm.leftWrist.y > lm.leftShoulder.y + 0.05
            let rightWristAboveShoulder = lm.rightWrist.y > lm.rightShoulder.y + 0.05
            let scrollUp = leftWristAboveShoulder || rightWristAboveShoulder

            if scrollUp {
                SystemControl.Application.scrollUp()
                overlay?.flash("🦵 抬膝⬆️ 向上")
                print("[kneeUp] Scroll Up")
            } else {
                SystemControl.Application.scrollDown()
                overlay?.flash("🦵 抬膝⬇️ 向下")
                print("[kneeUp] Scroll Down")
            }
            Feedback.play("Pop")
        }
        if sideLeanLeft.update(gesture == .sideLeanLeft) {
            SystemControl.Application.switchDesktop(direction: "left")
            Feedback.play("Tink")
            overlay?.flash("⬅️ 侧弯腰左")
            print("[sideLeanLeft] Desktop ←")
        }
        if sideLeanRight.update(gesture == .sideLeanRight) {
            SystemControl.Application.switchDesktop(direction: "right")
            Feedback.play("Tink")
            overlay?.flash("➡️ 侧弯腰右")
            print("[sideLeanRight] Desktop →")
        }

        if punchLeft.update(gesture == .punchLeft) && leftArmWasLow && isPunchHeightStable(lm.leftWrist.y, lm.leftShoulder.y, &leftPunchHeightHistory) {
            leftArmWasLow = false  // Must reset by lowering arm before next punch
            Keyboard.tapLeft()
            Feedback.play("Morse")
            overlay?.flash("👊 左出拳")
            print("[punchLeft] Left Arrow")
        }
        if punchRight.update(gesture == .punchRight) && rightArmWasLow && isPunchHeightStable(lm.rightWrist.y, lm.rightShoulder.y, &rightPunchHeightHistory) {
            rightArmWasLow = false  // Must reset by lowering arm before next punch
            Keyboard.tapRight()
            Feedback.play("Glass")
            overlay?.flash("👊 右出拳")
            print("[punchRight] Right Arrow")
        }

        if sideLiftLeft.update(gesture == .sideLiftLeft) && leftArmWasLow {
            leftArmWasLow = false  // Must reset by lowering arm before next side lift
            Keyboard.tapControlShiftTab()  // Previous tab (left direction)
            Feedback.play("Morse")
            overlay?.flash("💪 左侧平举 ←")
            print("[sideLiftLeft] Ctrl+Shift+Tab (previous tab)")
        }

        if sideLiftRight.update(gesture == .sideLiftRight) && rightArmWasLow {
            rightArmWasLow = false  // Must reset by lowering arm before next side lift
            Keyboard.tapControlTab()  // Next tab (right direction)
            Feedback.play("Glass")
            overlay?.flash("💪 右侧平举 →")
            print("[sideLiftRight] Ctrl+Tab (next tab)")
        }

        if raiseRight.update(gesture == .raiseRight) && !rightArmWasRaised {
            let now = Date()
            if now.timeIntervalSince(lastRaiseRightAt) > raiseRightCooldownSeconds {
                lastRaiseRightAt = now
                rightArmWasRaised = true  // Mark as raised, can only trigger again after arm is lowered
                let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
                let screenCenter = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
                Keyboard.mouseClick(at: screenCenter)
                Feedback.play("Pop")
                overlay?.flash("🤚 举手点击")
                print("[raiseRight] Clicked screen center")
            }
        }

        detectJump(lm)
        detectSquat(lm)
    }

    private func isPunchHeightStable(_ wristY: CGFloat, _ shoulderY: CGFloat, _ history: inout [(Date, Bool)]) -> Bool {
        let heightThreshold: CGFloat = 0.08
        let now = Date()
        let isAtPunchHeight = abs(wristY - shoulderY) < heightThreshold

        // Track history
        history.append((now, isAtPunchHeight))
        history = history.filter { now.timeIntervalSince($0.0) <= punchHeightWindowSeconds }

        // Find the earliest record where hand was at punch height
        let atHeightRecords = history.filter { $0.1 == true }
        guard let earliestAtHeight = atHeightRecords.first else { return false }

        // Calculate how long hand has been continuously at punch height (from earliest to now)
        let durationAtHeight = now.timeIntervalSince(earliestAtHeight.0)

        // Also check that recent frames are all at punch height (no interruption)
        let recentRecords = history.filter { now.timeIntervalSince($0.0) <= 0.1 }  // Last 0.1 seconds
        let recentAllAtHeight = recentRecords.allSatisfy { $0.1 == true }

        return durationAtHeight >= punchMinStaySeconds && recentAllAtHeight
    }

    private func isRaiseRightHeightStable(_ wristY: CGFloat, _ shoulderY: CGFloat, _ history: inout [(Date, Bool)]) -> Bool {
        let heightThreshold: CGFloat = 0.20
        let now = Date()
        let isAtRaiseHeight = wristY > shoulderY + heightThreshold

        // Track history
        history.append((now, isAtRaiseHeight))
        history = history.filter { now.timeIntervalSince($0.0) <= raiseRightHeightWindowSeconds }

        // Check if hand has been at raise height continuously for at least raiseRightMinStaySeconds
        let recentAtHeight = history.filter { now.timeIntervalSince($0.0) <= raiseRightMinStaySeconds }

        // All recent frames must be at raise height
        guard !recentAtHeight.isEmpty else { return false }
        let allStableFrames = recentAtHeight.allSatisfy { $0.1 == true }
        let durationAtHeight = recentAtHeight.last.map { now.timeIntervalSince($0.0) } ?? 0

        return allStableFrames && durationAtHeight >= raiseRightMinStaySeconds
    }

    private func detectJump(_ lm: BodyLandmarks) {
        // MULTIPLE-GESTURE LOCK: Disable jump detection while in an active squat (recording)
        if isFnActive { return }

        let now = Date()
        let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
        let torsoLen = lm.nose.y - hipY
        guard torsoLen > 0.05 else { return } // Basic validity check

        // 1. Update Hip Baseline (standing posture)
        if let baseline = hipBaselineY {
            let threshold = torsoLen * 0.05
            if abs(hipY - baseline) < threshold {
                hipBaselineHistory.append((now, hipY))
                hipBaselineHistory = hipBaselineHistory.filter { now.timeIntervalSince($0.0) <= jumpBaselineWindowSeconds }
                hipBaselineY = hipBaselineHistory.map { $0.1 }.reduce(0, +) / CGFloat(hipBaselineHistory.count)
            }
        } else {
            hipBaselineY = hipY
            hipBaselineHistory = [(now, hipY)]
        }

        // 2. Ankle Detection (if visible)
        var ankleSignal = false
        if lm.leftAnkle != .zero && lm.rightAnkle != .zero {
            let ankleY = (lm.leftAnkle.y + lm.rightAnkle.y) / 2
            if let baseline = ankleBaselineY {
                let threshold = torsoLen * 0.08
                if ankleY >= baseline - threshold {
                    // Update ankle baseline
                    ankleBaselineHistory.append((now, ankleY))
                    ankleBaselineHistory = ankleBaselineHistory.filter { now.timeIntervalSince($0.0) <= jumpBaselineWindowSeconds }
                    ankleBaselineY = ankleBaselineHistory.map { $0.1 }.reduce(0, +) / CGFloat(ankleBaselineHistory.count)
                }
                
                // Detect jump via ankle rise
                if ankleY > baseline + threshold {
                    ankleSignal = true
                }
            } else {
                ankleBaselineY = ankleY
                ankleBaselineHistory = [(now, ankleY)]
            }
        }

        // 3. Hip/Torso Signal (Sudden rise - fallback when feet not visible)
        var hipSignal = false
        if let baseline = hipBaselineY {
            let jumpThreshold = torsoLen * 0.12 // Require 12% of torso rise to trigger jump
            if hipY > baseline + jumpThreshold {
                hipSignal = true
            }
        }

        let isJumping = ankleSignal || hipSignal

        if frameCount % 30 == 0 {
            print(String(format: "[debug-jump] hipY=%.3f baseline=%.3f torso=%.3f log=[%@] src=[%@] isJumping=%@",
                         Double(hipY),
                         Double(hipBaselineY ?? 0),
                         Double(torsoLen),
                         isFnActive ? "LOCKED by Squat" : "READY",
                         hipSignal ? "Hip" : (ankleSignal ? "Ankle" : "None"),
                         isJumping ? "YES" : "NO"))
        }

        if jump.update(isJumping) {
            guard now.timeIntervalSince(lastJumpAt) > jumpCooldownSeconds else { return }
            lastJumpAt = now
            Keyboard.tapReturn()
            Feedback.play("Pop")
            overlay?.flash("⛹️ 跳跃发送")
            print("[jump] Enter (send) trigger: \(hipSignal ? "Hip (Center of Mass)" : "Ankle")")
        }
    }

    private func detectSquat(_ lm: BodyLandmarks) {
        let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
        let shoulderY = (lm.leftShoulder.y + lm.rightShoulder.y) / 2
        let torso = shoulderY - hipY
        guard torso > 0.05 else { return }

        // Check body tilt: if body is tilted > 5°, it's likely a lunge, not a squat
        let shoulderMidX = (lm.leftShoulder.x + lm.rightShoulder.x) / 2
        let hipMidX = (lm.leftHip.x + lm.rightHip.x) / 2
        let bodyTilt = abs(shoulderMidX - hipMidX)
        if bodyTilt > 0.04 {  // Body tilted > ~5°, exclude from squat detection
            return
        }

        let now = Date()
        hipHistory.append((now, hipY, torso))
        hipHistory = hipHistory.filter { now.timeIntervalSince($0.0) <= squatWindowSeconds }
        guard hipHistory.count >= 5 else { return } // need some history

        let currentMaxY = hipHistory.map { $0.1 }.max() ?? 0

        if !isFnActive {
            // If recently not squatting, cooldown applies
            guard now.timeIntervalSince(lastSquatAt) > squatCooldownSeconds else { return }

            // Count frames where hip is below the squat trigger threshold
            let dipFrames = hipHistory.filter { currentMaxY - $0.1 > torso * squatMinDipRatio }.count
            if dipFrames >= squatMinFrames {
                // Focus input first, then press Fn with a small delay to ensure focus is set
                SystemControl.Application.focusInput()
                usleep(50_000) // 50ms delay to let focus settle
                Keyboard.fnDown()
                isFnActive = true
                standingY = currentMaxY // Lock the standing height
                ankleBaselineHistory.removeAll()  // Clear ankle baseline history when entering squat
                Feedback.play("Tink")
                overlay?.flash("🏋️ 深蹲启动")
                print("[squat] Fn DOWN (dip detected)")
            }
        } else {
            // Restore reliability for finishing squat:
            // If we are already in Fn mode (isFnActive), we simply wait for the user to rise back to baseline.
            guard let standing = standingY else { return }

            let threshold = standing - torso * squatRiseBackRatio
            if hipY > threshold {
                Keyboard.fnUp()
                isFnActive = false
                lastSquatAt = now // Start cooldown after rising
                standingY = nil
                overlay?.flash("🎤 停止录音")
                print("[squat] Fn UP (stood up)")
            }
        }
    }
}

// MARK: - Setup

func requestCameraAccess() -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
        return true
    case .notDetermined:
        let sema = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .video) { ok in
            granted = ok
            sema.signal()
        }
        sema.wait()
        return granted
    default:
        return false
    }
}

// Parse --mode argument.
var mode = "body"
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--mode"), i + 1 < args.count {
    mode = args[i + 1]
}
guard mode == "hand" || mode == "body" else {
    print("Unknown mode: \(mode). Use --mode hand or --mode body.")
    exit(1)
}

print("牛马健身 — mode: \(mode)")
if mode == "hand" {
    print("  👍 Thumbs up (tap, toggle)      → Fn tap (Typeless dictation)")
    print("  👌 Thumb + index pinch          → Enter")
    print("  🖐️  Open palm swipe down         → Escape")
    print("  ☝️  Index only                  → Cmd+A (select all)")
    print("  ✌️  Peace sign                   → Cmd+V (paste)")
    print("  🤘 Rock sign                    → Cmd+C (copy)")
} else {
    print("  🏋️ Squat (deep dip)             → Fn down (Typeless dictation)")
    print("  👏 Clap (wrists meet at chest)  → Enter")
    print("  ❌ Arms cross X at chest        → Escape")
    print("  👊 Left Punch (forward)         → ← (Left Arrow)")
    print("  👊 Right Punch (forward)        → → (Right Arrow)")
    print("  💪 Left Side Lift (arm out)     → Ctrl+Shift+Tab (previous tab)")
    print("  💪 Right Side Lift (arm out)    → Ctrl+Tab (next tab)")
    print("  ⛹️ Jump (body rises)            → Enter (send)")
    print("  🤚 Right arm raise (overhead)   → Click screen center")
    print("  (camera must see head → hips, ideally to knees)")
}
print("  Ctrl+C to quit")
print("")

guard requestCameraAccess() else {
    print("Camera access denied. Grant it in System Settings → Privacy & Security → Camera.")
    exit(1)
}

// Keep strong references at module scope so detector + controller + delegate
// stay alive for the lifetime of NSApp.run().
var handController: HandController?
var handDetector: HandDetector?
var bodyController: BodyController?
var bodyDetector: BodyDetector?
var overlay: Overlay?

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no dock icon, no menu bar
overlay = Overlay()

if mode == "hand" {
    let c = HandController()
    c.overlay = overlay
    let d = HandDetector()
    d.onLandmarks = { lm in
        guard let lm = lm else {
            c.handle(.none, wristY: nil, landmarks: nil)
            return
        }
        let g = GestureClassifier.classify(lm)
        c.handle(g, wristY: lm.wrist.y, landmarks: lm)
    }
    do {
        try d.start()
        print("Camera started. Show your hand.")
    } catch {
        print("Failed to start camera: \(error.localizedDescription)")
        exit(1)
    }
    handController = c
    handDetector = d
} else {
    let c = BodyController()
    c.overlay = overlay
    let d = BodyDetector()
    d.onLandmarks = { lm in
        c.handle(lm)
    }
    do {
        try d.start()
        print("Camera started. Stand in frame.")
    } catch {
        print("Failed to start camera: \(error.localizedDescription)")
        exit(1)
    }
    bodyController = c
    bodyDetector = d
}

signal(SIGINT) { _ in
    print("\nBye.")
    exit(0)
}

app.run()
