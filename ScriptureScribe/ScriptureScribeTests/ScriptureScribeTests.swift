//
//  ScriptureScribeTests.swift
//  ScriptureScribeTests
//
//  Created by Derrick Iwuamadi on 2/16/26.
//

import Testing
import PencilKit
import UIKit
@testable import ScriptureScribe

/// Covers the page-size record written beside each drawing.
///
/// A `.pkdrawing` stores stroke coordinates and nothing about the canvas they
/// were drawn on, so this record is what lets another device show them at the
/// right proportions. These tests pin down the two things that matter: that a
/// real canvas is recorded and read back, and that the 100pt placeholder the
/// Reader parks on during a chapter change never gets written.
@MainActor
struct DrawingGeometryTests {

    /// Each test uses its own chapter id so they cannot tread on each other,
    /// and clears up after itself rather than leaving files in Documents.
    private func cleanUp(_ chapterId: String) {
        let safe = chapterId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["annotation_\(safe).pkdrawing", "annotation_\(safe).geometry.json"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        }
    }

    @Test func savingADrawingRecordsTheCanvasItWasDrawnOn() throws {
        let chapterId = "TEST.geometry.records"
        cleanUp(chapterId)
        defer { cleanUp(chapterId) }

        let vm = AnnotationViewModel()
        vm.currentCanvasSize = CGSize(width: 820, height: 1735.5)
        vm.saveDrawing(PKDrawing(), for: chapterId)

        let geo = try #require(vm.drawingGeometry(for: chapterId))
        #expect(geo.width  == 820)
        #expect(geo.height == 1735.5)
    }

    /// The outgoing chapter's drawing is saved while `contentHeight` sits at its
    /// 100pt placeholder. Recording that would claim the page was 100pt tall.
    @Test func thePlaceholderHeightIsNeverRecorded() {
        let chapterId = "TEST.geometry.placeholder"
        cleanUp(chapterId)
        defer { cleanUp(chapterId) }

        let vm = AnnotationViewModel()
        vm.currentCanvasSize = CGSize(width: 820, height: 100)
        vm.saveDrawing(PKDrawing(), for: chapterId)

        #expect(vm.drawingGeometry(for: chapterId) == nil)
    }

    /// A save during the placeholder window must not overwrite a good record
    /// with nothing — the drawing keeps the size it was last properly saved at.
    @Test func aPlaceholderSaveLeavesAnExistingRecordIntact() throws {
        let chapterId = "TEST.geometry.keeps"
        cleanUp(chapterId)
        defer { cleanUp(chapterId) }

        let vm = AnnotationViewModel()
        vm.currentCanvasSize = CGSize(width: 820, height: 1735.5)
        vm.saveDrawing(PKDrawing(), for: chapterId)

        vm.currentCanvasSize = CGSize(width: 820, height: 100)
        vm.saveDrawing(PKDrawing(), for: chapterId)

        let geo = try #require(vm.drawingGeometry(for: chapterId))
        #expect(geo.height == 1735.5)
    }

    @Test func aChapterWithNoDrawingHasNoGeometry() {
        let vm = AnnotationViewModel()
        #expect(vm.drawingGeometry(for: "TEST.geometry.absent") == nil)
    }
}
