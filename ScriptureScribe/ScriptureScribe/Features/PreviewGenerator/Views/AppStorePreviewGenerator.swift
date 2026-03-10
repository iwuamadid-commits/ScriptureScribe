//
//  AppStorePreviewGenerator.swift
//  ScriptureScribe
//
//  Generates App Store preview images for iPhone 6.7" and iPad 12.9".
//  Access via Profile → Developer Tools (DEBUG builds only).
//

import SwiftUI

// MARK: - Device Size

enum DeviceSizeOption: String, CaseIterable {
    case iPhone = "iPhone 6.7\""
    case iPad   = "iPad 12.9\""

    var canvasSize: CGSize {
        switch self {
        case .iPhone: return CGSize(width: 1290, height: 2796)
        case .iPad:   return CGSize(width: 2732, height: 2048) // landscape
        }
    }

    var frameSize: CGSize {
        switch self {
        case .iPhone: return CGSize(width: 1050, height: 2280)
        case .iPad:   return CGSize(width: 2200, height: 1600) // landscape
        }
    }

    var bezelRadius: CGFloat {
        switch self {
        case .iPhone: return 55
        case .iPad:   return 30
        }
    }

    var headlineFont: Font {
        switch self {
        case .iPhone: return .system(size: 86, weight: .bold, design: .rounded)
        case .iPad:   return .system(size: 78, weight: .bold, design: .rounded)
        }
    }

    var subheadlineFont: Font {
        switch self {
        case .iPhone: return .system(size: 40, weight: .medium, design: .rounded)
        case .iPad:   return .system(size: 36, weight: .medium, design: .rounded)
        }
    }

    /// Base font size for verse/body text inside mock screens.
    var bodySize: CGFloat {
        switch self {
        case .iPhone: return 32
        case .iPad:   return 28
        }
    }

    var verseNumSize: CGFloat {
        switch self {
        case .iPhone: return 28
        case .iPad:   return 24
        }
    }
}

// MARK: - Theme Colors (Ivory)

private let sagePrimary    = Color(hex: "#5C8A6B")
private let ivoryBg        = Color(hex: "#FAFAF8")
private let ivoryWhite     = Color(hex: "#FFFFFF")
private let ivoryText      = Color(hex: "#1A1A1A")
private let ivorySecondary = Color(hex: "#6B6B6B")
private let ivoryBorder    = Color(hex: "#E5E5E3")

// MARK: - Preview Config

private struct PreviewConfig: Identifiable {
    let id: Int
    let headline: String
    let subtitle: String
    let gradientTop: Color
    let gradientBottom: Color
    let mockScreen: AnyView
}

// MARK: - Main Generator View

struct AppStorePreviewGenerator: View {

    @State private var selectedDevice: DeviceSizeOption = .iPhone
    @State private var currentPage = 0
    @State private var isSaving = false
    @State private var saveProgress = 0
    @State private var saveComplete = false

    private var configs: [PreviewConfig] {
        [
            PreviewConfig(
                id: 1, headline: "Read. Reflect. Grow.",
                subtitle: "Multiple translations at your fingertips",
                gradientTop: Color(hex: "#FAFAF8"), gradientBottom: Color(hex: "#D4E6DA"),
                mockScreen: AnyView(MockReaderScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 2, headline: "Write in Your Bible",
                subtitle: "Draw, highlight, and take notes",
                gradientTop: Color(hex: "#E8F0EB"), gradientBottom: Color(hex: "#A8C6B0"),
                mockScreen: AnyView(MockAnnotationScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 3, headline: "Start Every Day Inspired",
                subtitle: "Daily verses, prayers, and devotions",
                gradientTop: Color(hex: "#F5F2EC"), gradientBottom: Color(hex: "#D4C9B8"),
                mockScreen: AnyView(MockDailyScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 4, headline: "Build Faithful Habits",
                subtitle: "Track your spiritual growth",
                gradientTop: Color(hex: "#EDF5F0"), gradientBottom: Color(hex: "#B8D4C2"),
                mockScreen: AnyView(MockHabitsScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 5, headline: "Grow Together in Faith",
                subtitle: "Share reflections and prayer requests",
                gradientTop: Color(hex: "#F0F4F2"), gradientBottom: Color(hex: "#C8DCD0"),
                mockScreen: AnyView(MockCommunityScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 6, headline: "Share Beautiful Verses",
                subtitle: "Create stunning verse images",
                gradientTop: Color(hex: "#F8F6F2"), gradientBottom: Color(hex: "#D8CDB8"),
                mockScreen: AnyView(MockSharingScreen(device: selectedDevice))
            ),
            PreviewConfig(
                id: 7, headline: "Your Verse Collection",
                subtitle: "Organize bookmarks and saved content",
                gradientTop: Color(hex: "#F2F6F3"), gradientBottom: Color(hex: "#B0CEB8"),
                mockScreen: AnyView(MockLibraryScreen(device: selectedDevice))
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Device", selection: $selectedDevice) {
                ForEach(DeviceSizeOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            TabView(selection: $currentPage) {
                ForEach(Array(configs.enumerated()), id: \.element.id) { index, config in
                    GeometryReader { geo in
                        let scale = min(
                            geo.size.width / selectedDevice.canvasSize.width,
                            geo.size.height / selectedDevice.canvasSize.height
                        ) * 0.95
                        PreviewSlide(config: config, device: selectedDevice)
                            .scaleEffect(scale)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Text("\(currentPage + 1) of \(configs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await saveAllImages() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.white)
                        Text("Saving \(saveProgress) of \(configs.count)...")
                    } else if saveComplete {
                        Image(systemName: "checkmark.circle.fill")
                        Text("All \(configs.count) images saved!")
                    } else {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save All to Photos")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(sagePrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSaving)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("App Store Previews")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func saveAllImages() async {
        isSaving = true
        saveProgress = 0
        saveComplete = false
        for config in configs {
            saveProgress += 1
            let slide = PreviewSlide(config: config, device: selectedDevice)
            let renderer = ImageRenderer(content: slide)
            renderer.proposedSize = .init(selectedDevice.canvasSize)
            renderer.scale = 1.0
            if let image = renderer.uiImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        isSaving = false
        saveComplete = true
    }
}

// MARK: - Preview Slide

private struct PreviewSlide: View {
    let config: PreviewConfig
    let device: DeviceSizeOption

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [config.gradientTop, config.gradientBottom],
                startPoint: .top, endPoint: .bottom
            )

            if device == .iPad {
                // iPad: landscape layout — headline left, device right
                HStack(spacing: 40) {
                    VStack(spacing: 16) {
                        Spacer()
                        Text(config.headline)
                            .font(device.headlineFont)
                            .foregroundStyle(ivoryText)
                            .multilineTextAlignment(.leading)
                        Text(config.subtitle)
                            .font(device.subheadlineFont)
                            .foregroundStyle(ivorySecondary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .frame(maxWidth: 800)
                    .padding(.leading, 80)

                    DeviceFrameView(device: device) { config.mockScreen }
                        .padding(.trailing, 40)

                    Spacer(minLength: 0)
                }
            } else {
                // iPhone: portrait layout — headline on top, device below
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    VStack(spacing: 14) {
                        Text(config.headline)
                            .font(device.headlineFont)
                            .foregroundStyle(ivoryText)
                            .multilineTextAlignment(.center)
                        Text(config.subtitle)
                            .font(device.subheadlineFont)
                            .foregroundStyle(ivorySecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 60)
                    Spacer(minLength: 40)
                    DeviceFrameView(device: device) { config.mockScreen }
                    Spacer(minLength: 20)
                }
            }
        }
        .frame(width: device.canvasSize.width, height: device.canvasSize.height)
    }
}

// MARK: - Device Frame

private struct DeviceFrameView<Content: View>: View {
    let device: DeviceSizeOption
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: device.bezelRadius + 4)
                .fill(.black.opacity(0.15))
                .frame(width: device.frameSize.width + 8, height: device.frameSize.height + 8)
                .offset(y: 6)
            RoundedRectangle(cornerRadius: device.bezelRadius + 4)
                .fill(Color(hex: "#1C1C1E"))
                .frame(width: device.frameSize.width + 16, height: device.frameSize.height + 16)
            ZStack {
                ivoryBg
                content()
            }
            .frame(width: device.frameSize.width, height: device.frameSize.height)
            .clipShape(RoundedRectangle(cornerRadius: device.bezelRadius))
        }
    }
}

// MARK: - Shared Tab Bar

private func mockTabBar(selected: String) -> some View {
    HStack {
        ForEach([
            ("book.fill", "Read"),
            ("sun.max.fill", "Daily"),
            ("checkmark.circle.fill", "Habits"),
            ("person.2.fill", "Community"),
            ("bookmark.fill", "Library"),
            ("person.circle.fill", "Profile"),
        ], id: \.0) { icon, label in
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.system(size: 15))
            }
            .foregroundStyle(icon == selected ? sagePrimary : ivorySecondary)
            Spacer()
        }
    }
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(ivoryWhite)
    .overlay(alignment: .top) { Divider() }
}

// MARK: - Mock Screen 1: Bible Reader (full chapter)

private struct MockReaderScreen: View {
    let device: DeviceSizeOption

    private let genesisVerses: [(String, String)] = [
        ("1", "In the beginning God created the heaven and the earth."),
        ("2", "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters."),
        ("3", "And God said, Let there be light: and there was light."),
        ("4", "And God saw the light, that it was good: and God divided the light from the darkness."),
        ("5", "And God called the light Day, and the darkness he called Night. And the evening and the morning were the first day."),
        ("6", "And God said, Let there be a firmament in the midst of the waters, and let it divide the waters from the waters."),
        ("7", "And God made the firmament, and divided the waters which were under the firmament from the waters which were above the firmament: and it was so."),
        ("8", "And God called the firmament Heaven. And the evening and the morning were the second day."),
        ("9", "And God said, Let the waters under the heaven be gathered together unto one place, and let the dry land appear: and it was so."),
        ("10", "And God called the dry land Earth; and the gathering together of the waters called he Seas: and God saw that it was good."),
        ("11", "And God said, Let the earth bring forth grass, the herb yielding seed, and the fruit tree yielding fruit after his kind, whose seed is in itself, upon the earth: and it was so."),
        ("12", "And the earth brought forth grass, and herb yielding seed after his kind, and the tree yielding fruit, whose seed was in itself, after his kind: and God saw that it was good."),
        ("13", "And the evening and the morning were the third day."),
        ("14", "And God said, Let there be lights in the firmament of the heaven to divide the day from the night; and let them be for signs, and for seasons, and for days, and years."),
        ("15", "And let them be for lights in the firmament of the heaven to give light upon the earth: and it was so."),
        ("16", "And God made two great lights; the greater light to rule the day, and the lesser light to rule the night: he made the stars also."),
        ("17", "And God set them in the firmament of the heaven to give light upon the earth,"),
        ("18", "And to rule over the day and over the night, and to divide the light from the darkness: and God saw that it was good."),
        ("19", "And the evening and the morning were the fourth day."),
        ("20", "And God said, Let the waters bring forth abundantly the moving creature that hath life, and fowl that may fly above the earth in the open firmament of heaven."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Genesis 1")

            // Book selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"], id: \.self) { book in
                        Text(book)
                            .font(.system(size: 22, weight: book == "Genesis" ? .bold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .foregroundStyle(book == "Genesis" ? .white : ivoryText)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(book == "Genesis" ? sagePrimary : .clear)
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ivoryBorder, lineWidth: book == "Genesis" ? 0 : 1)
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 6)

            // Chapter selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...20, id: \.self) { num in
                        Text("\(num)")
                            .font(.system(size: 20, weight: num == 1 ? .bold : .regular))
                            .frame(minWidth: 42)
                            .padding(.vertical, 8)
                            .foregroundStyle(num == 1 ? .white : ivoryText)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(num == 1 ? sagePrimary : .clear)
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ivoryBorder, lineWidth: num == 1 ? 0 : 1)
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)

            Divider()

            // Full chapter verses
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("GENESIS 1")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(ivorySecondary)
                        .tracking(2)
                        .padding(.top, 12)

                    ForEach(genesisVerses, id: \.0) { num, text in
                        HStack(alignment: .top, spacing: 10) {
                            Text(num)
                                .font(.system(size: device.verseNumSize, weight: .bold, design: .serif))
                                .foregroundStyle(sagePrimary)
                                .frame(width: 36, alignment: .trailing)
                            Text(text)
                                .font(.system(size: device.bodySize, design: .serif))
                                .foregroundStyle(ivoryText)
                                .lineSpacing(8)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            mockTabBar(selected: "book.fill")
        }
    }
}

// MARK: - Mock Screen 2: Annotation (realistic toolbar + handwriting)

private struct MockAnnotationScreen: View {
    let device: DeviceSizeOption

    private let psalmVerses: [(String, String)] = [
        ("1", "The Lord is my shepherd; I shall not want."),
        ("2", "He maketh me to lie down in green pastures: he leadeth me beside the still waters."),
        ("3", "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake."),
        ("4", "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me."),
        ("5", "Thou preparest a table before me in the presence of mine enemies: thou anointest my head with oil; my cup runneth over."),
        ("6", "Surely goodness and mercy shall follow me all the days of my life: and I will dwell in the house of the Lord for ever."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Psalm 23")

            Divider()

            // Verses with annotations
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PSALM 23")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(ivorySecondary)
                            .tracking(2)
                            .padding(.top, 12)

                        ForEach(psalmVerses, id: \.0) { num, text in
                            HStack(alignment: .top, spacing: 10) {
                                Text(num)
                                    .font(.system(size: device.verseNumSize, weight: .bold, design: .serif))
                                    .foregroundStyle(sagePrimary)
                                    .frame(width: 36, alignment: .trailing)

                                ZStack(alignment: .leading) {
                                    Text(text)
                                        .font(.system(size: device.bodySize, design: .serif))
                                        .foregroundStyle(ivoryText)
                                        .lineSpacing(8)

                                    // Highlight on verse 1
                                    if num == "1" {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(sagePrimary.opacity(0.2))
                                            .frame(height: 38)
                                    }
                                    // Underline on verse 3
                                    if num == "3" {
                                        VStack {
                                            Spacer()
                                            Rectangle()
                                                .fill(Color(hex: "#D65A8B").opacity(0.6))
                                                .frame(height: 4)
                                                .offset(y: -6)
                                        }
                                        .frame(width: 360)
                                    }
                                }
                            }
                        }

                        // Handwritten note
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What a beautiful promise!")
                                .font(.system(size: 26, weight: .regular, design: .rounded))
                                .foregroundStyle(sagePrimary.opacity(0.7))
                                .italic()
                                .rotationEffect(.degrees(-1.5))
                            Text("God is always with us 🙏")
                                .font(.system(size: 24, weight: .regular, design: .rounded))
                                .foregroundStyle(sagePrimary.opacity(0.6))
                                .italic()
                                .rotationEffect(.degrees(-1))
                        }
                        .padding(.top, 12)
                        .padding(.leading, 46)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }
            }

            Spacer(minLength: 0)

            // Realistic annotation toolbar
            annotationToolbar

            mockTabBar(selected: "book.fill")
        }
    }

    private var annotationToolbar: some View {
        HStack(spacing: 8) {
            // Tool buttons
            HStack(spacing: 6) {
                annotToolBtn(icon: "hand.raised.fill", selected: false)
                annotToolBtn(icon: "pencil", selected: true)
                annotToolBtn(icon: "highlighter", selected: false)
                annotToolBtn(icon: "eraser", selected: false)
                annotToolBtn(icon: "camera", selected: false)
            }

            Divider().frame(height: 28)

            // Color swatches
            HStack(spacing: 6) {
                colorSwatch(Color(hex: "#5C8A6B"), selected: true)
                colorSwatch(Color(hex: "#D65A8B"), selected: false)
                colorSwatch(Color(hex: "#5B7FA6"), selected: false)
                colorSwatch(Color(hex: "#D4A843"), selected: false)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(sagePrimary)
            }

            Spacer()

            // Undo/redo/settings
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22))
                    .foregroundStyle(ivorySecondary)
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 22))
                    .foregroundStyle(ivorySecondary)
                    .frame(width: 40, height: 40)
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .foregroundStyle(sagePrimary)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(ivoryWhite)
        .overlay(alignment: .top) { Divider() }
    }

    private func annotToolBtn(icon: String, selected: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 24))
            .frame(width: 42, height: 42)
            .foregroundStyle(selected ? sagePrimary : ivorySecondary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(sagePrimary.opacity(0.15))
                }
            }
    }

    private func colorSwatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay {
                Circle().stroke(selected ? sagePrimary : .white.opacity(0.3), lineWidth: selected ? 2.5 : 1.5)
            }
    }
}

// MARK: - Mock Screen 3: Daily (full content)

private struct MockDailyScreen: View {
    let device: DeviceSizeOption

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Daily")

            // Week strip
            weekStrip

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    dailyCard(
                        icon: "book.fill", title: "Today's Verse",
                        content: "\"I can do all things through Christ which strengtheneth me.\"\n\n— Philippians 4:13 (KJV)"
                    )

                    dailyCard(
                        icon: "sparkles", title: "Affirmation",
                        content: "I am strengthened by God's grace. His power is made perfect in my weakness. Today I walk in the confidence that comes from knowing the Creator of the universe is on my side."
                    )

                    dailyCard(
                        icon: "heart.fill", title: "Prayer",
                        content: "Lord, thank You for Your strength that carries me through every challenge. Help me to rely on You in all things, to trust Your plan even when the path is unclear. Fill me with courage and peace as I walk through this day. Let my words and actions reflect Your love. In Jesus' name, Amen."
                    )

                    dailyCard(
                        icon: "text.book.closed.fill", title: "Devotion",
                        content: "Paul wrote these words from a prison cell, yet his faith remained unshakeable. True strength comes not from our circumstances but from our connection to Christ. When we feel weak, His power shines brightest through us. Today, let go of trying to do it all on your own. Instead, lean into the One who gives you strength for every moment."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            mockTabBar(selected: "sun.max.fill")
        }
    }

    private var weekStrip: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let nums = ["10", "11", "12", "13", "14", "15", "16"]
        return HStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                let isToday = i == 2
                VStack(spacing: 4) {
                    Text(days[i])
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isToday ? .white : ivorySecondary)
                    Text(nums[i])
                        .font(.system(size: 22, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : ivoryText)
                }
                .frame(width: 52, height: 62)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isToday ? sagePrimary : .clear)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func dailyCard(icon: String, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(sagePrimary)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ivoryText)
            }
            Text(content)
                .font(.system(size: device.bodySize, design: .serif))
                .foregroundStyle(ivoryText)
                .lineSpacing(7)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1)
        }
    }
}

// MARK: - Mock Screen 4: Habits + customization preview

private struct MockHabitsScreen: View {
    let device: DeviceSizeOption

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Habits")

            // Category pills
            HStack(spacing: 10) {
                catPill("All", selected: true)
                catPill("Spiritual", selected: false)
                catPill("Health", selected: false)
                catPill("Life", selected: false)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    habitRow(emoji: "🙏", name: "Morning Prayer", goal: "5 minutes", streak: 14, done: true, color: Color(hex: "#5C8A6B"))
                    habitRow(emoji: "📖", name: "Read 1 Chapter", goal: "1 chapter", streak: 7, done: true, color: Color(hex: "#5B7FA6"))
                    habitRow(emoji: "✍️", name: "Gratitude Journal", goal: "3 things", streak: 3, done: false, color: Color(hex: "#D65A8B"))
                    habitRow(emoji: "🏃", name: "Exercise", goal: "30 minutes", streak: 5, done: true, color: Color(hex: "#D4A843"))

                    // Habit customization preview inset
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Customize Your Habits")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ivoryText)

                        // Mini preview of customization
                        HStack(spacing: 14) {
                            miniCustomCard(emoji: "💧", name: "Drink Water", category: "Health", color: Color(hex: "#5B7FA6"))
                            miniCustomCard(emoji: "📿", name: "Pray Rosary", category: "Spiritual", color: Color(hex: "#5C8A6B"))
                            miniCustomCard(emoji: "🎯", name: "Set Goals", category: "Life", color: Color(hex: "#D4A843"))
                        }

                        HStack(spacing: 10) {
                            ForEach(["Emoji", "Goal", "Category", "Color"], id: \.self) { label in
                                HStack(spacing: 4) {
                                    Image(systemName: label == "Emoji" ? "face.smiling" : label == "Goal" ? "target" : label == "Category" ? "tag" : "paintpalette")
                                        .font(.system(size: 16))
                                    Text(label)
                                        .font(.system(size: 16))
                                }
                                .foregroundStyle(sagePrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(sagePrimary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    .padding(18)
                    .background(ivoryWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).stroke(sagePrimary.opacity(0.3), lineWidth: 1.5)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            mockTabBar(selected: "checkmark.circle.fill")
        }
    }

    private func catPill(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 20, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : ivoryText)
            .background {
                Capsule().fill(selected ? sagePrimary : .clear)
                Capsule().stroke(ivoryBorder, lineWidth: selected ? 0 : 1)
            }
    }

    private func habitRow(emoji: String, name: String, goal: String, streak: Int, done: Bool, color: Color) -> some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 38))
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: device.bodySize - 6, weight: .semibold))
                    .foregroundStyle(ivoryText)
                Text(goal)
                    .font(.system(size: 20))
                    .foregroundStyle(ivorySecondary)
            }
            Spacer()
            Text("🔥 \(streak)")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 34))
                .foregroundStyle(done ? color : ivoryBorder)
        }
        .padding(18)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }

    private func miniCustomCard(emoji: String, name: String, category: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 30))
            Text(name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ivoryText)
                .lineLimit(1)
            Text(category)
                .font(.system(size: 13))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Mock Screen 5: Community (all 4 tabs previewed)

private struct MockCommunityScreen: View {
    let device: DeviceSizeOption

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Community")

            // Tab pills
            HStack(spacing: 8) {
                commTab("Insights", selected: true)
                commTab("Gratitude", selected: false)
                commTab("Prayer", selected: false)
                commTab("Daily", selected: false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Insights post
                    postCard(
                        tab: "Insights", name: "Grace M.", initials: "GM",
                        verse: "Romans 8:28", time: "2h ago",
                        text: "This verse reminded me that even in difficult seasons, God is working everything together for our good. What a comforting promise! 💛",
                        likes: 12, comments: 3
                    )

                    // Gratitude post
                    sectionLabel("From Gratitude")
                    postCard(
                        tab: "Gratitude", name: "David L.", initials: "DL",
                        verse: nil, time: "4h ago",
                        text: "Grateful for a peaceful morning and the chance to spend time in prayer. God's faithfulness never ceases to amaze me. 🌅",
                        likes: 8, comments: 2
                    )

                    // Prayer request
                    sectionLabel("From Prayer Requests")
                    prayerRequestCard(
                        name: "Sarah K.", initials: "SK", time: "Yesterday",
                        text: "Please pray for my family as we navigate a difficult season. We trust God's plan but need strength and peace.",
                        prayers: 24
                    )

                    // Daily question
                    sectionLabel("From Daily Question")
                    dailyQuestionCard(
                        question: "How has God shown His faithfulness to you this week?",
                        answers: 18
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            mockTabBar(selected: "person.2.fill")
        }
    }

    private func commTab(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 20, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : ivoryText)
            .background {
                Capsule().fill(selected ? sagePrimary : .clear)
                Capsule().stroke(ivoryBorder, lineWidth: selected ? 0 : 1)
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Rectangle().fill(sagePrimary.opacity(0.3)).frame(height: 1)
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(sagePrimary)
                .lineLimit(1)
            Rectangle().fill(sagePrimary.opacity(0.3)).frame(height: 1)
        }
    }

    private func postCard(tab: String, name: String, initials: String, verse: String?, time: String, text: String, likes: Int, comments: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sagePrimary.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay { Text(initials).font(.system(size: 17, weight: .bold)).foregroundStyle(sagePrimary) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 22, weight: .semibold)).foregroundStyle(ivoryText)
                    Text(time).font(.system(size: 17)).foregroundStyle(ivorySecondary)
                }
                Spacer()
                if let verse {
                    Text(verse)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(sagePrimary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(sagePrimary.opacity(0.1), in: Capsule())
                }
            }
            Text(text)
                .font(.system(size: device.bodySize - 6))
                .foregroundStyle(ivoryText)
                .lineSpacing(4)
            HStack(spacing: 20) {
                Label("\(likes)", systemImage: "heart.fill").foregroundStyle(sagePrimary)
                Label("\(comments)", systemImage: "bubble.left").foregroundStyle(ivorySecondary)
                Spacer()
            }
            .font(.system(size: 19))
        }
        .padding(18)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }

    private func prayerRequestCard(name: String, initials: String, time: String, text: String, prayers: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sagePrimary.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay { Text(initials).font(.system(size: 17, weight: .bold)).foregroundStyle(sagePrimary) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 22, weight: .semibold)).foregroundStyle(ivoryText)
                    Text(time).font(.system(size: 17)).foregroundStyle(ivorySecondary)
                }
                Spacer()
            }
            Text(text)
                .font(.system(size: device.bodySize - 6))
                .foregroundStyle(ivoryText)
                .lineSpacing(4)
            HStack {
                Label("\(prayers) praying", systemImage: "hands.sparkles.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(sagePrimary)
                Spacer()
            }
        }
        .padding(18)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }

    private func dailyQuestionCard(question: String, answers: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(sagePrimary)
                Text("Daily Question")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ivoryText)
            }
            Text(question)
                .font(.system(size: device.bodySize - 4, design: .serif))
                .foregroundStyle(ivoryText)
                .italic()
                .lineSpacing(4)
            HStack {
                Label("\(answers) answers", systemImage: "text.bubble.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(sagePrimary)
                Spacer()
            }
        }
        .padding(18)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }
}

// MARK: - Mock Screen 6: Verse Sharing

private struct MockSharingScreen: View {
    let device: DeviceSizeOption

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ivoryText)
                Spacer()
                Text("Share Verse")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(ivoryText)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 26))
                    .foregroundStyle(sagePrimary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            Spacer()

            // Verse image card
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#1A2E1A"), Color(hex: "#2A4A2A")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(spacing: 28) {
                    Spacer()
                    Text("FOR GOD SO\nLOVED THE WORLD,\nTHAT HE GAVE\nHIS ONLY\nBEGOTTEN SON")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(10)
                    Text("JOHN 3:16")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .tracking(3)
                    Spacer()
                }
                .padding(44)
            }
            .frame(width: 650, height: 650)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 6)

            Spacer()

            // Font picker
            VStack(spacing: 10) {
                Text("Font")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ivorySecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    ForEach(["Serif", "Sans", "Rounded", "Didot"], id: \.self) { font in
                        Text(font)
                            .font(.system(size: 20, weight: font == "Serif" ? .semibold : .regular))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .foregroundStyle(font == "Serif" ? .white : ivoryText)
                            .background {
                                Capsule().fill(font == "Serif" ? sagePrimary : .clear)
                                Capsule().stroke(ivoryBorder, lineWidth: font == "Serif" ? 0 : 1)
                            }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            // Background thumbnails
            VStack(spacing: 10) {
                Text("Background")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ivorySecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach([
                        ("Ivory", Color(hex: "#FAFAF8"), Color(hex: "#E5E5E3")),
                        ("Forest", Color(hex: "#1A2E1A"), Color(hex: "#2A4A2A")),
                        ("Midnight", Color(hex: "#0D1B2A"), Color(hex: "#1A2D42")),
                        ("Blossom", Color(hex: "#FFF0F5"), Color(hex: "#FFD6E5")),
                        ("Royal", Color(hex: "#1A0A14"), Color(hex: "#3A1A28")),
                    ], id: \.0) { name, c1, c2 in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    if name == "Forest" {
                                        RoundedRectangle(cornerRadius: 8).stroke(sagePrimary, lineWidth: 3)
                                    }
                                }
                            Text(name)
                                .font(.system(size: 15))
                                .foregroundStyle(ivorySecondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            mockTabBar(selected: "book.fill")
        }
    }
}

// MARK: - Mock Screen 7: Library / Bookmarks

private struct MockLibraryScreen: View {
    let device: DeviceSizeOption

    var body: some View {
        VStack(spacing: 0) {
            mockNavBar(title: "Library")

            // Tab pills
            HStack(spacing: 8) {
                libTab("Bookmarks", selected: true)
                libTab("Prayers", selected: false)
                libTab("Devotionals", selected: false)
                libTab("Affirmations", selected: false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    collTile(name: "Favorites", count: 12, emoji: "❤️", color: Color(hex: "#D65A8B"))
                    collTile(name: "Promises", count: 8, emoji: "⭐", color: Color(hex: "#D4A843"))
                    collTile(name: "Comfort", count: 5, emoji: "🤲", color: Color(hex: "#5B7FA6"))
                    collTile(name: "Wisdom", count: 3, emoji: "💡", color: Color(hex: "#5C8A6B"))
                    bmCard(verse: "Philippians 4:13", text: "I can do all things through Christ which strengtheneth me.", color: .red)
                    bmCard(verse: "Jeremiah 29:11", text: "For I know the plans I have for you, declares the Lord, plans to prosper you...", color: Color(hex: "#D4A843"))
                    bmCard(verse: "Psalm 23:1", text: "The Lord is my shepherd; I shall not want.", color: Color(hex: "#5C8A6B"))
                    bmCard(verse: "Romans 8:28", text: "And we know that all things work together for good to them that love God...", color: Color(hex: "#5B7FA6"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
            mockTabBar(selected: "bookmark.fill")
        }
    }

    private func libTab(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 20, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : ivoryText)
            .background {
                Capsule().fill(selected ? sagePrimary : .clear)
                Capsule().stroke(ivoryBorder, lineWidth: selected ? 0 : 1)
            }
    }

    private func collTile(name: String, count: Int, emoji: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 42))
            Text(name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ivoryText)
            Text("\(count) verses")
                .font(.system(size: 18))
                .foregroundStyle(ivorySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }

    private func bmCard(verse: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bookmark.fill").foregroundStyle(color)
                Text(verse)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ivoryText)
            }
            Text(text)
                .font(.system(size: 18, design: .serif))
                .foregroundStyle(ivorySecondary)
                .lineLimit(3)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ivoryWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ivoryBorder, lineWidth: 1) }
    }
}

// MARK: - Shared Nav Bar

private func mockNavBar(title: String) -> some View {
    HStack {
        Text("🔥 7")
            .font(.system(size: 24, weight: .bold))
        Spacer()
        Text(title)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(ivoryText)
        Spacer()
        Image(systemName: "magnifyingglass")
            .font(.system(size: 26))
            .foregroundStyle(sagePrimary)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 18)
}
