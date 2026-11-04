//
//  SeedHandwriting.swift
//  ScriptureScribeTests
//
//  A development helper, not a test of behaviour.
//
//  The simulator has no Apple Pencil, so there is no way to produce a real
//  drawing by hand and check that the read-only handwriting page renders it.
//  This writes a drawing into the app's own Documents folder — unit tests run
//  inside the app process, so it lands exactly where the app looks for it.
//
//  Off by default so it never runs as part of the suite. `.disabled` would skip
//  it even when named explicitly, so it is gated on an environment variable:
//
//      TEST_RUNNER_SEED_HANDWRITING=1 xcodebuild test ... \
//        -only-testing:ScriptureScribeTests/SeedHandwriting
//
//  The TEST_RUNNER_ prefix matters: xcodebuild strips it and passes the rest
//  into the test process in the simulator. Without it the variable stays on the
//  Mac and the test simply skips.
//

import Testing
import PencilKit
import UIKit
@testable import ScriptureScribe

@MainActor
struct SeedHandwriting {

    /// Writes a few strokes onto Genesis 1 so the handwriting page has
    /// something real to draw.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEED_HANDWRITING"] == "1",
                   "Development helper — set SEED_HANDWRITING=1 to run"))
    func seedGenesisOne() {
        let vm = AnnotationViewModel()

        // An iPad-sized page, so the phone has to scale it down the way a real
        // iPad drawing would.
        vm.currentCanvasSize = CGSize(width: 820, height: 1735)

        let ink = PKInk(.pen, color: .systemBlue)
        var strokes: [PKStroke] = []

        // Three wavy lines, roughly where someone might underline early verses.
        for (row, baseY) in [220.0, 430.0, 980.0].enumerated() {
            var points: [PKStrokePoint] = []
            for step in 0...60 {
                let x = 90.0 + Double(step) * 10.0
                let y = baseY + sin(Double(step) / 4.0) * (8.0 + Double(row) * 3.0)
                points.append(
                    PKStrokePoint(
                        location: CGPoint(x: x, y: y),
                        timeOffset: Double(step) * 0.01,
                        size: CGSize(width: 4, height: 4),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    )
                )
            }
            strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date())))
        }

        vm.saveDrawing(PKDrawing(strokes: strokes), for: "GEN.1")

        #expect(vm.drawingGeometry(for: "GEN.1")?.height == 1735)
    }
}
