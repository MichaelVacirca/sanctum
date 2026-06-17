import XCTest
import simd
@testable import Sanctum

final class ThemeTests: XCTestCase {

    // MARK: - Lookup

    func testNamedResolvesKnownThemes() {
        XCTAssertEqual(Theme.named("cathedral").id, "cathedral")
        XCTAssertEqual(Theme.named("beach").id, "beach")
        // Case-insensitive
        XCTAssertEqual(Theme.named("BEACH").id, "beach")
    }

    func testNamedFallsBackToCathedral() {
        XCTAssertEqual(Theme.named("does-not-exist").id, "cathedral")
        XCTAssertEqual(Theme.named("").id, "cathedral")
    }

    func testAllThemesAreWellFormed() {
        XCTAssertFalse(Theme.all.isEmpty)
        for theme in Theme.all {
            XCTAssertEqual(theme.phases.count, 5, "\(theme.id) should have 5 phases")
            XCTAssertFalse(theme.panelOrder.isEmpty, "\(theme.id) needs panels")
            XCTAssertFalse(theme.icons.isEmpty, "\(theme.id) needs icons")
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }

    // MARK: - Arc sampling

    func testPhaseIndexMatchesCorruptionThresholds() {
        // Theme phase selection must line up with CorruptionPhase's 0.2 steps.
        let beach = Theme.beach
        XCTAssertEqual(beach.phaseIndex(at: 0.0), 0)
        XCTAssertEqual(beach.phaseIndex(at: 0.1), 0)
        XCTAssertEqual(beach.phaseIndex(at: 0.2), 1)
        XCTAssertEqual(beach.phaseIndex(at: 0.5), 2)
        XCTAssertEqual(beach.phaseIndex(at: 0.7), 3)
        XCTAssertEqual(beach.phaseIndex(at: 0.9), 4)
        XCTAssertEqual(beach.phaseIndex(at: 1.0), 4)
    }

    func testPhaseNameTracksArc() {
        XCTAssertEqual(Theme.beach.phaseName(at: 0.0), "SUNSET")
        XCTAssertEqual(Theme.beach.phaseName(at: 0.9), "MIDNIGHT")
        XCTAssertEqual(Theme.cathedral.phaseName(at: 0.0), "SACRED")
        XCTAssertEqual(Theme.cathedral.phaseName(at: 0.9), "ABYSS")
    }

    func testInterpolatedTintEndpoints() {
        let beach = Theme.beach
        assertClose(beach.interpolatedTint(at: 0.0), beach.phases[0].tint)
        assertClose(beach.interpolatedTint(at: 1.0), beach.phases[4].tint)
        // Final phase is held across the top of the range.
        assertClose(beach.interpolatedTint(at: 0.85), beach.phases[4].tint)
    }

    func testInterpolatedTintMidpoint() {
        // Keypoints sit every 0.2; halfway between phase 0 and 1 is index 0.1.
        let beach = Theme.beach
        let expected = (beach.phases[0].tint + beach.phases[1].tint) * 0.5
        assertClose(beach.interpolatedTint(at: 0.1), expected)
    }

    func testInterpolatedTintHitsKeypointExactly() {
        let beach = Theme.beach
        assertClose(beach.interpolatedTint(at: 0.2), beach.phases[1].tint)
        assertClose(beach.interpolatedTint(at: 0.4), beach.phases[2].tint)
    }

    func testEnergyTintLerpsFromWhite() {
        // At zero energy the composite tint is neutral white.
        assertClose(Theme.beach.energyTint(at: 0.0), SIMD3(1, 1, 1))
        assertClose(Theme.cathedral.energyTint(at: 0.0), SIMD3(1, 1, 1))
        // At full energy it reaches the profile's energyTint.
        assertClose(Theme.cathedral.energyTint(at: 1.0), SIMD3(0.8, 0.7, 0.95))
        // Cathedral's curve must still match the original 1 - k*c darkening.
        let half = Theme.cathedral.energyTint(at: 0.5)
        assertClose(half, SIMD3(1.0 - 0.2 * 0.5, 1.0 - 0.3 * 0.5, 1.0 - 0.05 * 0.5))
    }

    // MARK: - Preservation of the original gothic look

    func testCathedralPaletteUnchanged() {
        let c = Theme.cathedral
        assertClose(c.phases[0].tint, SIMD3(0.9, 0.85, 1.1))
        assertClose(c.phases[4].tint, SIMD3(1.3, 0.4, 1.4))
        // Effect profile reproduces the original cranked shader constants.
        XCTAssertEqual(c.effects.crack, 1.0)
        XCTAssertEqual(c.effects.fold, 1.0)
        XCTAssertEqual(c.effects.shimmer, 0.0)
        XCTAssertEqual(c.effects.brightness, 1.15, accuracy: 0.0001)
    }

    func testBeachIsFeelGoodNotDestructive() {
        let b = Theme.beach
        // No cracking, no Escher folding; shimmer on; never darkens.
        XCTAssertEqual(b.effects.crack, 0.0)
        XCTAssertEqual(b.effects.fold, 0.0)
        XCTAssertGreaterThan(b.effects.shimmer, 0.0)
        XCTAssertGreaterThanOrEqual(b.effects.energyTint.x, 1.0)
        XCTAssertGreaterThanOrEqual(b.effects.energyTint.y, 0.9)
    }

    // MARK: - Helpers

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>,
                             accuracy: Float = 0.0001,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
    }
}
