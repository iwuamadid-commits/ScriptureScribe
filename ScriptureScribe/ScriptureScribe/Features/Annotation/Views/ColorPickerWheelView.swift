//
//  ColorPickerWheelView.swift
//  ScriptureScribe
//
//  Full-screen color picker with a large color wheel and a hex text field.
//  The wheel takes up most of the screen so it's easy to tap precisely.
//

import SwiftUI

struct ColorPickerWheelView: View {

    @Binding var selectedColor: UIColor
    @Environment(\.dismiss) private var dismiss

    @State private var hexText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // Large color wheel — fills available width
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)   // much larger than the default compact size
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Hex text field
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
                            .onChange(of: hexText) { _, v in
                                if let c = UIColor(hexString: v) { selectedColor = c }
                            }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 24)

                // Live color preview swatch
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(selectedColor))
                    .frame(height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1))
                    .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { hexText = selectedColor.hexString }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(selectedColor) },
            set: { selectedColor = UIColor($0); hexText = selectedColor.hexString }
        )
    }
}
