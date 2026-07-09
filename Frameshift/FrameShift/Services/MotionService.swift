import CoreMotion
import Combine

class MotionService: ObservableObject {

    private let motionManager = CMMotionManager()

    /// Left / right horizon tilt (radians).
    @Published var roll: Double = 0.0
    /// Camera elevation vs horizontal (radians). Positive = tilted up.
    @Published var pitch: Double = 0.0
    @Published var isLevel: Bool = false

    var targetRoll: Double = 0
    /// isLevel latches with hysteresis: sensor noise at a single hard
    /// threshold flips the flag many times a second right at lock, which
    /// re-fires the lock haptic and makes the leveler's yellow state flicker.
    private let levelEnterThreshold: Double = 0.02
    private let levelExitThreshold: Double = 0.035

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        // Gravity-based angles track portrait pan/level; attitude Euler angles do not.
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let g = motion.gravity

            // roll is the angle of gravity's projection onto the screen plane
            // (x,y). As the phone pitches up toward pointing straight up,
            // that projection shrinks toward zero and atan2 amplifies sensor
            // noise into large angle swings. Damp harder the less reliable
            // the reading is, so lifting the phone doesn't read as jitter.
            let horizontalMagnitude = (g.x * g.x + g.y * g.y).squareRoot()
            let rawRoll = atan2(g.x, -g.y)
            let alpha = min(0.35, max(0.04, horizontalMagnitude * 0.5))
            self.roll = Self.smoothedAngle(current: self.roll, target: rawRoll, alpha: alpha)

            // Positive pitch = camera tilted up (top of phone toward you).
            // Smoothed like roll so the pitch line and chevron tiers don't
            // flutter at their thresholds while the user fine-tunes.
            self.pitch = Self.smoothedAngle(current: self.pitch, target: atan2(g.z, -g.y), alpha: 0.3)

            let rollDeviation = abs(self.roll - self.targetRoll)
            if self.isLevel {
                if rollDeviation > self.levelExitThreshold { self.isLevel = false }
            } else if rollDeviation < self.levelEnterThreshold {
                self.isLevel = true
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    /// Exponential smoothing across the shortest angular path, so blending
    /// near the ±π wrap doesn't jump the long way around.
    private static func smoothedAngle(current: Double, target: Double, alpha: Double) -> Double {
        var delta = target - current
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return current + alpha * delta
    }
}
