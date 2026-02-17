//
//  ColorPickerWheelView.swift
//  ScriptureScribe
//
//  A color picker sheet with two ways to choose a color:
//    1. A color wheel (the same one built into iOS — just tap a color)
//    2. A hex text field (type in a code like "FF5733" for a precise color)
//
//  Both controls stay in sync: changing one immediately updates the other.
//

import SwiftUI

struct ColorPickerWheelView: View {

    /// The color the user has picked — written back to AnnotationViewModel.selectedColor.
    @Binding var selectedColor: UIColor

    @Environment(\.dismiss) private var dismiss

    // Local state: the hex text the user is typing
    @State private var hexText: String = ""
    // Tracks if the hex text field is being edited (avoids overwriting mid-type)
    @State private var isEditingHex = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                // — Color Wheel —
                // SwiftUI's built-in ColorPicker wraps iOS's UIColorPickerViewController.
                // supportsOpacity: false → no transparency slider (simpler UX).
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 260, height: 260)
                    .padding(.top, 8)

                // — Hex Code Field —
                VStack(alignment: .leading, spacing: 6) {
                    Text("Or type a hex code:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("#")
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("e.g. 5C8A6B", text: $hexText)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: hexText) { _, newValue in
                                applyHex(newValue)
                            }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 32)

                // — Current Color Preview —
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(selectedColor))
                    .frame(height: 48)
                    .padding(.horizontal, 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator, lineWidth: 1)
                    )

                Spacer()
            }
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            hexText = selectedColor.hexString
        }
    }

    // MARK: - Helpers

    /// Binding that keeps SwiftUI Color and UIColor in sync.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(selectedColor) },
            set: { newColor in
                selectedColor = UIColor(newColor)
                hexText = selectedColor.hexString
            }
        )
    }

    /// Tries to parse the hex text as a UIColor. Only updates if the string is a valid 6-digit hex.
    private func applyHex(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 6, let color = UIColor(hexString: clean) else { return }
        selectedColor = color
    }
}
