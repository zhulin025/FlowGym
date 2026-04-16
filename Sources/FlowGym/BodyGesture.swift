import CoreGraphics
import Foundation

enum BodyGesture: String {
    case none
    case clap
    case crossArms
    case kneeUp
    case sideLeanLeft
    case sideLeanRight
    case punchLeft
    case punchRight
    case sideLiftLeft
    case sideLiftRight
    case jump
    case raiseRight  // Right arm raised above head
    // squat is detected temporally in BodyController.
}

enum BodyGestureClassifier {
    static func classify(_ lm: BodyLandmarks) -> BodyGesture {
        let shoulderWidth = dist(lm.leftShoulder, lm.rightShoulder)
        guard shoulderWidth > 0.05 else { return .none }

        // Check raise right arm first (priority)
        if isRaiseRight(lm) { return .raiseRight }

        if isClap(lm, shoulderWidth: shoulderWidth) { return .clap }
        if isCrossArms(lm) { return .crossArms }
        if isKneeUp(lm) { return .kneeUp }

        // Check punches and side lifts (arm at shoulder height)
        let armGesture = checkArmGestures(lm)
        if armGesture != .none { return armGesture }

        let lean = isSideLean(lm)
        if lean != .none { return lean }

        return .none
    }

    private static func isClap(_ lm: BodyLandmarks, shoulderWidth: CGFloat) -> Bool {
        // Wrists close together and above hips (at chest/face height).
        // Also require both wrists to be detected (y > 0.01 excludes zero-fallback).
        guard lm.leftWrist.y > 0.01, lm.rightWrist.y > 0.01 else { return false }
        let wristGap = dist(lm.leftWrist, lm.rightWrist)
        guard wristGap < shoulderWidth * 0.5 else { return false }
        let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
        guard lm.leftWrist.y > hipY, lm.rightWrist.y > hipY else { return false }
        return true
    }

    private static func isCrossArms(_ lm: BodyLandmarks) -> Bool {
        // Each wrist must end up on the OPPOSITE side from its own shoulder.
        // This is invariant to camera mirroring.
        let midX = (lm.leftShoulder.x + lm.rightShoulder.x) / 2
        let leftCrossed = (lm.leftWrist.x - midX) * (lm.leftShoulder.x - midX) < 0
        let rightCrossed = (lm.rightWrist.x - midX) * (lm.rightShoulder.x - midX) < 0
        guard leftCrossed, rightCrossed else { return false }

        // Both wrists at chest level (between hip and shoulder).
        let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
        let shoulderY = (lm.leftShoulder.y + lm.rightShoulder.y) / 2
        guard lm.leftWrist.y > hipY, lm.leftWrist.y < shoulderY else { return false }
        guard lm.rightWrist.y > hipY, lm.rightWrist.y < shoulderY else { return false }
        return true
    }

    private static func isKneeUp(_ lm: BodyLandmarks) -> Bool {
        // Knee Y is higher than Hip Y + a small margin.
        // Vision Y: 0 bottom, 1 top.
        let hipY = (lm.leftHip.y + lm.rightHip.y) / 2
        let threshold = hipY + 0.12 // fairly high knee lift
        return lm.leftKnee.y > threshold || lm.rightKnee.y > threshold
    }

    private static func checkArmGestures(_ lm: BodyLandmarks) -> BodyGesture {
        // Wrist at shoulder height: wrist Y ≈ shoulder Y (within 0.08)
        let heightThreshold: CGFloat = 0.08
        let bodyMidX = (lm.leftShoulder.x + lm.rightShoulder.x) / 2

        // Left wrist check
        // In mirrored Vision coords: leftShoulder.x > bodyMidX > rightShoulder.x
        let leftWristAtHeight = abs(lm.leftWrist.y - lm.leftShoulder.y) < heightThreshold
        // 出拳（Punch）：手腕在中线和左肩之间（向中线靠近）
        let leftWristForward = lm.leftWrist.x > bodyMidX && lm.leftWrist.x < lm.leftShoulder.x + 0.05
        // 侧平举（Side Lift）：手腕明显超出左肩向外侧（X增大）
        let leftWristOutward = lm.leftWrist.x > lm.leftShoulder.x + 0.10

        // Right wrist check
        let rightWristAtHeight = abs(lm.rightWrist.y - lm.rightShoulder.y) < heightThreshold
        // 出拳（Punch）：手腕在中线和右肩之间（向中线靠近）
        let rightWristForward = lm.rightWrist.x < bodyMidX && lm.rightWrist.x > lm.rightShoulder.x - 0.05
        // 侧平举（Side Lift）：手腕明显超出右肩向外侧（X减小）
        let rightWristOutward = lm.rightWrist.x < lm.rightShoulder.x - 0.10

        // 侧平举优先检查（条件更严格，防止被出拳掩盖）
        if leftWristAtHeight && leftWristOutward {
            return .sideLiftLeft
        }

        if rightWristAtHeight && rightWristOutward {
            return .sideLiftRight
        }

        // 出拳次之
        if leftWristAtHeight && leftWristForward {
            return .punchLeft
        }

        if rightWristAtHeight && rightWristForward {
            return .punchRight
        }

        return .none
    }

    private static func isSideLean(_ lm: BodyLandmarks) -> BodyGesture {
        let shoMidX = (lm.leftShoulder.x + lm.rightShoulder.x) / 2
        let hipMidX = (lm.leftHip.x + lm.rightHip.x) / 2
        let diff = shoMidX - hipMidX

        // Lean Left (image left): shoulders shift to smaller X relative to hips.
        // Swapping for mirror: smaller X diff -> sideLeanRight
        // Threshold set to 0.08 for ~10-15 degree lean for easier triggering.
        if diff < -0.08 { return .sideLeanRight }
        if diff > 0.08 { return .sideLeanLeft }
        return .none
    }

    private static func isRaiseRight(_ lm: BodyLandmarks) -> Bool {
        // Right arm raised significantly above head/shoulder
        // Right wrist Y > right shoulder Y + 0.20 (well above shoulder)
        return lm.rightWrist.y > lm.rightShoulder.y + 0.20
    }

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
