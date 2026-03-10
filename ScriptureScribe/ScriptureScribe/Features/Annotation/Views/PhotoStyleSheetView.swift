//
//  PhotoStyleSheetView.swift
//  ScriptureScribe
//
//  Style panel for a placed photo.
//  Every control applies its change to the live canvas immediately.
//  Tapping Cancel reverts all fields to the values they had when the sheet opened.
//

import SwiftUI

struct PhotoStyleSheetView: View {

    let photo:        AnnotationViewModel.PhotoAnnotation
    let chapterId:    String
    @ObservedObject var annotationVM: AnnotationViewModel

    @Environment(\.dismiss) private var dismiss

    // Originals captured at init — used to restore on Cancel
    private let origOpacity:        Double
    private let origRotation:       Double
    private let origBorderWidth:    CGFloat
    private let origBorderColorHex: String

    // Live state
    @State private var opacity:     Double
    @State private var rotation:    Double
    @State private var borderWidth: CGFloat
    @State private var borderColor: Color

    private let rotStep: Double = 15    // degrees per button tap

    private let borderPresets: [(CGFloat, String)] = [
        (0,   "None"),
        (1.5, "Thin"),
        (3,   "Med"),
        (6,   "Thick"),
    ]

    init(photo: AnnotationViewModel.PhotoAnnotation,
         chapterId: String,
         annotationVM: AnnotationViewModel) {
        self.photo        = photo
        self.chapterId    = chapterId
        self.annotationVM = annotationVM

        origOpacity        = photo.opacity
        origRotation       = photo.rotation
        origBorderWidth    = photo.borderWidth
        origBorderColorHex = photo.borderColorHex

        _opacity     = State(initialValue: photo.opacity)
        _rotation    = State(initialValue: photo.rotation)
        _borderWidth = State(initialValue: photo.borderWidth)

        let uiColor = UIColor(hexString: photo.borderColorHex) ?? .white
        _borderColor = State(initialValue: Color(uiColor))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                // ── Opacity ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opacity")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundStyle(.secondary)
                        Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
                            .onChange(of: opacity) { _, val in
                                applyStyle(opacity: val)
                            }
                        Text("\(Int(opacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Divider()

                // ── Rotation ─────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("Rotation")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 16) {
                        Spacer()

                        Button {
                            let r = rotation - rotStep
                            rotation = r
                            applyRotation(r)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "rotate.left").font(.title2)
                                Text("−\(Int(rotStep))°").font(.caption)
                            }
                            .frame(width: 72, height: 52)
                        }
                        .buttonStyle(.bordered)

                        Text("\(Int(rotation))°")
                            .font(.title3.monospacedDigit())
                            .frame(minWidth: 56, alignment: .center)

                        Button {
                            let r = rotation + rotStep
                            rotation = r
                            applyRotation(r)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "rotate.right").font(.title2)
                                Text("+\(Int(rotStep))°").font(.caption)
                            }
                            .frame(width: 72, height: 52)
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    Button("Reset") {
                        rotation = 0
                        applyRotation(0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                // ── Border ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("Border")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 0) {
                        ForEach(borderPresets, id: \.0) { (width, label) in
                            borderPresetButton(width: width, label: label)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Color picker — only visible when a border is active
                    if borderWidth > 0 {
                        ColorPicker("Border Color", selection: $borderColor, supportsOpacity: false)
                            .onChange(of: borderColor) { _, c in
                                applyStyle(borderColor: c)
                            }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .navigationTitle("Image Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Revert every field to its original value
                        annotationVM.updatePhotoStyle(
                            id:             photo.id,
                            opacity:        origOpacity,
                            borderWidth:    origBorderWidth,
                            borderColorHex: origBorderColorHex,
                            for:            chapterId
                        )
                        annotationVM.rotatePhotoAnnotation(
                            id:       photo.id,
                            rotation: origRotation,
                            for:      chapterId
                        )
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Live apply helpers

    /// Push the current opacity + border state to the canvas immediately.
    private func applyStyle(opacity: Double? = nil,
                            borderWidthOverride: CGFloat? = nil,
                            borderColor: Color? = nil) {
        let op  = opacity             ?? self.opacity
        let bw  = borderWidthOverride ?? self.borderWidth
        let hex = UIColor(borderColor ?? self.borderColor).hexString
        annotationVM.updatePhotoStyle(
            id:             photo.id,
            opacity:        op,
            borderWidth:    bw,
            borderColorHex: hex,
            for:            chapterId
        )
    }

    /// Push a rotation change to the canvas immediately.
    private func applyRotation(_ degrees: Double) {
        annotationVM.rotatePhotoAnnotation(
            id:       photo.id,
            rotation: degrees,
            for:      chapterId
        )
    }

    // MARK: - Border preset button

    @ViewBuilder
    private func borderPresetButton(width: CGFloat, label: String) -> some View {
        let isOn = abs(borderWidth - width) < 0.1
        Button {
            borderWidth = width
            applyStyle(borderWidthOverride: width)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary, lineWidth: max(0.5, width))
                    )
                    .overlay(
                        isOn
                            ? RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(-3)
                            : nil
                    )
                    .frame(height: 44)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isOn ? Color.accentColor : .primary)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
