//
//  SavedColorsManagerView.swift
//  ScriptureScribe
//
//  Saved color management list — navigated to from ColorPickerWheelView.
//  Layout per row:  [#]  [●]  #RRGGBB  [eye]  [...]
//    • Eye icon   — toggle visibility (hidden colors excluded from toolbar)
//    • "..." menu — Edit / Duplicate / Delete
//    • Swipe left  — delete
//    • "+" nav button — push picker to add a new color
//

import SwiftUI

struct SavedColorsManagerView: View {

    @ObservedObject var vm: AnnotationViewModel
    @EnvironmentObject var subscriptionVM: SubscriptionViewModel

    /// Set to an index to push the picker in replace-in-place mode.
    @State private var editingIndex: Int? = nil
    /// True while the picker is pushed to add a brand-new color.
    @State private var showAddPicker = false
    /// Controls List edit mode — activated by long-pressing any row.
    @State private var editMode: EditMode = .inactive
    /// Shown when a free user taps "+" at the color limit.
    @State private var showPaywall = false

    private var isAtFreeLimit: Bool {
        !subscriptionVM.isPremium && vm.savedColors.count >= PremiumLimits.maxFreeSavedColors
    }

    var body: some View {
        List {
            ForEach(Array(vm.savedColors.enumerated()), id: \.element.stringValue) { index, savedColor in
                colorRow(for: savedColor, at: index)
                    // Long press (0.4 s) → enter reorder mode + haptic
                    .onLongPressGesture(minimumDuration: 0.4) {
                        withAnimation { editMode = .active }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .listRowBackground(Color(white: 0.13))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onMove { source, destination in
                vm.moveColors(fromOffsets: source, toOffset: destination)
                // Auto-exit reorder mode after dropping
                withAnimation { editMode = .inactive }
            }
            .onDelete { indexSet in
                indexSet.sorted().reversed().forEach { vm.deleteColor(at: $0) }
            }
        }
        .environment(\.editMode, $editMode)
        .listStyle(.plain)
        .background(Color(white: 0.13))
        .scrollContentBackground(.hidden)
        .navigationTitle("Saved Colors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if editMode == .active {
                    // "Done" exits reorder mode
                    Button("Done") {
                        withAnimation { editMode = .inactive }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(white: 0.85))
                } else {
                    // "+" opens picker — shows PRO badge + routes to paywall at limit
                    Button {
                        if isAtFreeLimit { showPaywall = true } else { showAddPicker = true }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(white: 0.85))
                            if isAtFreeLimit {
                                ProBadge()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        // "+" → add a new color (picker stays open; Save Color button saves it)
        .navigationDestination(isPresented: $showAddPicker) {
            ColorPickerWheelView(
                selectedColor: .constant(vm.selectedColor),
                onAdd: { newColor in
                    vm.addSavedColor(newColor)
                },
                onDone: { newColor in
                    if !isAtFreeLimit {
                        vm.addSavedColor(newColor)
                    }
                    // dismiss() in ColorPickerWheelView handles the navigation pop
                }
            )
        }
        // "..." → Edit → replace existing swatch in-place
        .navigationDestination(item: $editingIndex) { index in
            if index < vm.savedColors.count {
                ColorPickerWheelView(
                    selectedColor: .constant(vm.savedColors[index].uiColor),
                    onDone: { newColor in
                        vm.replaceColor(at: index, with: newColor)
                        editingIndex = nil
                    }
                )
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func colorRow(for savedColor: SavedColor, at index: Int) -> some View {
        HStack(spacing: 12) {

            // Row number
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.40))
                .frame(width: 18, alignment: .trailing)

            // Color circle
            ZStack {
                Circle()
                    .fill(Color(savedColor.uiColor))
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
            .frame(width: 30, height: 30)
            .opacity(savedColor.isHidden ? 0.35 : 1)

            // Hex code
            Text("#\(savedColor.colorHex)")
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(savedColor.isHidden ? Color(white: 0.38) : Color(white: 0.90))

            Spacer()

            // Eye — toggle visibility
            Button {
                vm.toggleHideColor(at: index)
            } label: {
                Image(systemName: savedColor.isHidden ? "eye.slash" : "eye")
                    .font(.callout)
                    .foregroundStyle(savedColor.isHidden ? Color(white: 0.40) : Color(white: 0.65))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(savedColor.isHidden ? "Show color" : "Hide color")

            // "..." — context menu for Edit / Duplicate / Delete
            Menu {
                Button {
                    editingIndex = index
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    vm.duplicateColor(at: index)
                } label: {
                    Label("Duplicate", systemImage: "square.on.square")
                }

                Button(role: .destructive) {
                    withAnimation { vm.deleteColor(at: index) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.callout)
                    .foregroundStyle(Color(white: 0.65))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.vertical, 4)
    }
}
