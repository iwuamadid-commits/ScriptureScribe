//
//  DeviceCapabilities.swift
//  ScriptureScribe
//
//  Which features this device is capable of.
//
//  Scripture Scribe is one universal app. On iPad it is the full pencil
//  experience; on iPhone the pencil tools are replaced by finger-based verse
//  highlighting. This is the single place that decides which of the two a
//  given device gets.
//

import UIKit

enum DeviceCapabilities {

    /// True when the pencil feature set (pen, highlighter, eraser, lasso,
    /// placing photos on a page) is available.
    ///
    /// Deliberately based on the device IDIOM, not the horizontal size class.
    /// An iPad in Slide Over reports a .compact size class, and it must keep
    /// all of its tools — gating on size class would strip the toolbar from a
    /// multitasking iPad. Size class stays what it already is in this app: a
    /// hint for sizing chrome (see AnnotationToolbarView.isCompact).
    static let hasPencilTools: Bool = UIDevice.current.userInterfaceIdiom != .phone

    /// True on iPhone — the reduced, finger-only experience.
    /// Reads better than `!hasPencilTools` at call sites that are about layout
    /// rather than about tools.
    static var isPhoneLayout: Bool { !hasPencilTools }
}
