import CoreGraphics
import Testing
@testable import FrameShift

struct ShotSpecClassificationTests {

    @Test func feetVisibleIsFullBodyEvenWhenThePersonBoxFillsTheFrame() {
        let framing = ShotSpec.inferFraming(
            subjectHeight: 0.79,
            headRadius: 0.05,
            bodyCoverage: .feet
        )
        #expect(framing == .wide)
    }

    @Test func tightThreeQuarterCropIsMediumNotCloseUp() {
        let framing = ShotSpec.inferFraming(
            subjectHeight: 0.79,
            headRadius: 0.07,
            bodyCoverage: .unknown
        )
        #expect(framing == .medium)
    }

    @Test func waistUpDinnerStaysMedium() {
        let framing = ShotSpec.inferFraming(
            subjectHeight: 0.56,
            headRadius: 0.11,
            bodyCoverage: .unknown
        )
        #expect(framing == .medium)
    }

    @Test func largeHeadIsCloseUp() {
        let framing = ShotSpec.inferFraming(
            subjectHeight: 0.62,
            headRadius: 0.20,
            bodyCoverage: .torso
        )
        #expect(framing == .closeUp)
    }

    @Test func kneesWithoutFeetIsMedium() {
        let framing = ShotSpec.inferFraming(
            subjectHeight: 0.80,
            headRadius: 0.08,
            bodyCoverage: .knees
        )
        #expect(framing == .medium)
    }

    @Test func cafeSeatedLowAngle() {
        // Measured on SampleRefCafeSip: knees closer than the torso.
        let look = ShotSpec.inferAngleLook(
            shoulderSpan: 162,
            hipSpan: 95,
            kneeSpan: 303,
            hasAnkles: true
        )
        #expect(look == .low)
    }

    @Test func sofaWideStanceIsNotLowAngle() {
        let look = ShotSpec.inferAngleLook(
            shoulderSpan: 178,
            hipSpan: 127,
            kneeSpan: 383,
            hasAnkles: true
        )
        #expect(look == .none)
    }

    @Test func walkingTowardCameraIsNotLowAngle() {
        let look = ShotSpec.inferAngleLook(
            shoulderSpan: 182,
            hipSpan: 100,
            kneeSpan: 94,
            hasAnkles: true
        )
        #expect(look == .none)
    }
}
