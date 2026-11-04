//
//  HandwritingPageUITests.swift
//  ScriptureScribeUITests
//
//  Opens the read-only handwriting page the way a person would.
//
//  The simulator has no Apple Pencil, so the drawing itself is planted first by
//  ScriptureScribeTests/SeedHandwriting. This test only covers the journey:
//  the toolbar button appears when a chapter has handwriting, and tapping it
//  opens a page that renders.
//

import XCTest

final class HandwritingPageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHandwritingPageOpensFromTheReader() throws {
        let app = XCUIApplication()
        app.launch()

        // The Bible text arrives over the network, and the button only appears
        // once a chapter with handwriting is on screen.
        let button = app.buttons["View handwriting"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 60),
            "Handwriting button never appeared — is the drawing seeded for this chapter?"
        )

        button.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Handwriting page did not open")

        // Give the page a moment to render the strokes before capturing it.
        Thread.sleep(forTimeInterval: 3)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "handwriting-page"
        shot.lifetime = .keepAlways
        add(shot)

        // The empty state and the rendered page are mutually exclusive; seeing
        // the empty text here would mean the drawing never reached the view.
        XCTAssertFalse(
            app.staticTexts["No handwriting on this chapter"].exists,
            "Page opened but showed the empty state"
        )
    }
}
