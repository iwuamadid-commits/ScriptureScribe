# Scripture Scribe — iOS App Build Plan

## Context
Stephanie and her brother want to build a native iOS Bible annotation app called Scripture Scribe. They are not developers — Claude will write all code and walk them through every step. The app allows users to read the Bible in multiple translations, annotate directly on the text (drawing, highlighting, typed notes, bookmarks, images), search both Bible text and handwritten notes, and engage in a faith community. The repo is currently empty (only README + .gitignore).

**Decisions made:**
- Platform: iOS (iPhone/iPad) — native
- Language: Swift + SwiftUI
- Architecture: MVVM
- Bible content: API.Bible REST API (user is already subscribed)
- Translations: All available via subscription — 1,500–2,500+ translations in 1,600+ languages fetched dynamically from `GET /v1/bibles`; English translations (NIV, ESV, KJV, NLT, NKJV, NASB, AMP, MSG, NCV, CEB, WEB, ASV, GNT, ERV, etc.) featured prominently; full multilingual support
- Backend: Firebase (Auth, Firestore, Storage, Cloud Messaging)
- Mac: Available; Xcode not yet installed
- API.Bible rate limit: 5,000 queries/day; max 500 consecutive verses per request

---

## Architecture Overview

```
ScriptureScribe/
├── App/
│   ├── ScriptureScribeApp.swift     ← @main entry, Firebase config, env objects
│   ├── AppDelegate.swift
│   └── ContentView.swift            ← Tab bar (Reader, Daily, Search, Community, Profile)
├── Core/
│   ├── Config/AppConfig.swift       ← API key from Secrets.xcconfig (gitignored)
│   ├── Network/BibleAPIService.swift
│   ├── Firebase/AuthService.swift / FirestoreService.swift / StorageService.swift
│   ├── Persistence/CoreDataStack.swift  ← offline chapter caching
│   ├── Theme/AppTheme.swift / ThemeManager.swift / Typography.swift
│   └── Extensions/Color+Hex.swift
└── Features/
    ├── Reader/       ← Bible text, book/chapter nav, translation switcher, zoom
    ├── Annotation/   ← PencilKit canvas, toolbar, color picker, guide lines
    ├── Notes/        ← Floating typed note tiles anchored to passages
    ├── Bookmarks/    ← Long-press to add, color + emoji categories
    ├── Search/       ← Text search, topic search, handwriting OCR search
    ├── Daily/        ← Daily verse, prayer, devotion cards
    ├── Community/    ← Feed, posts, comments, likes
    ├── Auth/         ← Email + Sign in with Apple
    └── Streaks/      ← Daily usage streak counter
```

---

## Key Frameworks (No Third-Party Libraries Required)
| Feature | Framework |
|---|---|
| Drawing / Annotation | `PencilKit` (PKCanvasView) |
| Color picker | `UIColorPickerViewController` (UIKit, wrapped in SwiftUI) |
| Handwriting OCR | `VisionKit` (VNRecognizeTextRequest) |
| Offline caching | `Core Data` |
| Bible text | `API.Bible` REST API |
| Auth | `Firebase Auth` + `AuthenticationServices` (Sign in with Apple) |
| Community data | `Cloud Firestore` |
| Images/drawings | `Firebase Storage` |
| Push notifications | `Firebase Cloud Messaging` + `UserNotifications` |
| Photos attachment | `PhotosUI` (PHPickerViewController) |

---

## Firestore Schema
```
users/{uid}/
  ├── [profile fields, selectedTheme, selectedTranslation, isLeftHanded]
  ├── streak/current → { count, lastOpenedDate, longestStreak }
  ├── bookmarks/{bookmarkId} → { bibleId, bookId, chapterId, verseId, verseText, color, emoji, createdAt }
  └── notes/{noteId} → { bibleId, bookId, chapterId, verseId, text, positionX, positionY, createdAt }

posts/{postId} → { authorId, text, imageURL, verseReference, likedBy[], commentCount, reportedBy[] }
comments/{commentId} → { postId, authorId, text, createdAt }
daily_content/{YYYY-MM-DD} → { verseReference, verseId, prayer, devotion }
```

Firebase Storage paths:
- `annotations/{uid}/{bibleId}/{chapterId}.pkdrawing`
- `profile_images/{uid}/profile.jpg`
- `post_images/{postId}/image.jpg`

---

## 8 Themes
1. **Ivory** — clean white, sage green accent (default)
2. **Parchment** — warm cream, dark ink, feels like old Bible paper
3. **Midnight** — deep navy, gold accents, dark mode premium
4. **Serene** — soft lavender and white, gentle pastels
5. **Forest** — deep green, warm tan, earthy
6. **Sunrise** — warm oranges, peach gradients
7. **Slate** — cool grey-blue, minimal modern
8. **Royal** — deep burgundy, gold, classical

All defined via `AppTheme` protocol; `ThemeManager` persists selection via `@AppStorage`.

---

## Build Phases

### Phase 0 — Environment Setup *(Do this first)*
1. Install Xcode from Mac App Store (free, ~15GB download)
2. Create new Xcode project: iOS App, SwiftUI, Swift, bundle ID `com.[yourname].ScriptureScribe`
3. Replace existing `.gitignore` with Swift/Xcode template
4. Create `Secrets.xcconfig` (gitignored) → add API key
5. Add Firebase SDK via Swift Package Manager (FirebaseAuth, Firestore, Storage, Messaging)
6. Download `GoogleService-Info.plist` from Firebase Console → add to project
7. Create the full folder structure above as empty groups in Xcode

### Phase 1 — Bible Reader Core
- `BibleAPIService.swift`: `fetchAllBibles()` → `GET /v1/bibles`, `fetchBooks(bibleId:)`, `fetchChapters(bibleId:bookId:)`, `fetchChapter(bibleId:chapterId:)`, `search(bibleId:query:)`
- `BibleTranslation.swift` model: `id`, `name`, `abbreviation`, `language`, `copyrightStatement` (from API response)
- `ReaderViewModel.swift`: published state for `availableTranslations`, `currentBibleId`, books, chapters, verses, loading
- `BibleTextView.swift`: verse rendering with `AttributedString` for red letter support; `copyrightStatement` footer below each chapter (required by API.Bible licensing)
- `BookSelectorRow.swift` + `ChapterSelectorRow.swift`: horizontal swipeable rows, alphabetical/chronological sort toggle
- `TranslationBrowserView.swift`: searchable, scrollable list of all translations grouped by language; English translations pinned to top; search by name or abbreviation; displays language name + translation name + abbreviation chip
- Translation list cached to Core Data on first fetch (avoids re-fetching 1,500+ entries on every launch)
- `MagnificationGesture` for pinch-to-zoom
- Core Data caching of fetched chapters (offline reading)
- Font selection, font size, line spacing settings

### Phase 2 — Annotation Engine
- `AnnotationCanvasView.swift`: `UIViewRepresentable` wrapping `PKCanvasView`
- **Annotation Mode toggle**: canvas hidden (non-interactive) when OFF, active when ON — resolves scroll conflict
- `AnnotationToolbarView.swift`: Pen, Highlighter, Eraser, Lasso, Undo, Redo
- `ColorPickerWheelView.swift`: `UIColorPickerViewController` + hex `TextField` (bidirectional)
- `StrokeSizeSliderView.swift`
- `GuideLineOverlayView.swift`: right-side guide lines, wide/medium/narrow spacing
- Left/right-handed mode (toolbar + guide lines swap sides)
- Finger writing toggle (`PKCanvasView.drawingPolicy`)
- Save/load: serialize `PKDrawing` → `Data` → Firebase Storage

### Phase 3 — Notes, Bookmarks, and Streaks
- **Notes**: floating `NotesTileView` with `DragGesture` for repositioning; `NoteEditorView` sheet; `NoteIndicatorView` badge; Firestore persistence
- **Bookmarks**: `LongPressGesture` on verse rows; color + emoji picker (`EmojiPickerView`); `BookmarkListView` grouped by color; Firestore persistence
- **Streaks**: `StreakViewModel` compares today vs `lastOpenedDate`, increments or resets; displayed as flame badge with count; Firestore sync

### Phase 4 — Search
- `SearchView.swift` with 3 mode tabs
- Bible text search via `API.Bible /search` endpoint
- Topic search: `BibleTopics.json` (love, anxiety, hope, fear, etc.) → keyword → API search
- Handwriting OCR search: mini `PKCanvasView` → render to `UIImage` → `VNRecognizeTextRequest` → show recognized text for confirmation → Bible search
- Tapping result navigates to correct passage in Reader

### Phase 5 — Themes and Daily Content
- Define `AppTheme` protocol + all 8 theme structs
- `ThemeManager` as `@StateObject` with `@AppStorage` persistence
- Inject via `.environmentObject()` from app root
- `ThemePickerView.swift` in Settings (grid of 8 preview cards)
- `DailyContent.json` (365 entries: verseId, prayer, devotion — start with 30, cycle with modulo)
- `DailyViewModel.swift` + `DailyView.swift` + `DailyVerseCard.swift`
- Firebase Cloud Messaging: daily reminder notification

### Phase 6 — Auth and Community
- `AuthService.swift`: email sign-in/up + Sign in with Apple (mandatory per App Store guideline 4.8)
- `FeedView.swift`: real-time Firestore listener, paginated with `limit(to: 20)` + `start(afterDocument:)`
- `CreatePostView.swift`: text + optional photo (`PhotosUI`) + optional verse tag
- Likes via `FieldValue.arrayUnion` transaction
- Moderation: `reportedBy[]` array; Firestore rule hides posts where `reportedBy.size() > 5`
- `ProfileView.swift`: user posts, streak, join date

### Phase 7 — Polish and App Store Submission
- Accessibility audit: `.accessibilityLabel()` / `.accessibilityHint()` on all interactive elements
- iPad layout: `NavigationSplitView` for Reader
- Offline mode: ensure Core Data degraded-but-functional experience
- Unit tests: ReaderViewModel, AnnotationViewModel, StreakViewModel, AuthViewModel
- UI tests: sign-up → open Bible → draw annotation → save (critical path)
- Enroll in Apple Developer Program ($99/year)
- App Store Connect: create record, configure capabilities (Push Notifications, Sign in with Apple)
- App icons, screenshots, metadata
- Archive → validate → submit for review

---

## First 3 Files to Create (After Xcode Setup)
1. **`AppTheme.swift`** — theme protocol + IvoryTheme default; must exist before any view so no colors get hardcoded
2. **`AppConfig.swift`** — API key pattern via Secrets.xcconfig; establishes secure secrets handling
3. **`ScriptureScribeApp.swift`** — entry point wiring Firebase + ThemeManager + AuthViewModel as environment objects

---

## Critical Risks to Know About

| Risk | Severity | Mitigation |
|---|---|---|
| Translation copyright — NIV/ESV/NKJV/NASB/etc. have strict rules: max 500 consecutive verses, attribution string required, non-commercial free tier only | **Critical** | (1) Display `copyrightStatement` from the API response as a footer on every chapter — it's included automatically in each Bible object. (2) If the app is ever monetized, a commercial license per translation is required (starts ~$10/month per translation) — confirm your current subscription covers commercial use. |
| PencilKit canvas blocks ScrollView touch events | **High** | Annotation Mode toggle — canvas only active when user switches to drawing mode |
| API.Bible rate limits when rapidly swiping chapters | **High** | Core Data caching mandatory; pre-fetch N±1 chapters; exponential backoff on 429 |
| Sign in with Apple is mandatory (App Store rule 4.8) | **High** | Built into Phase 6 — cannot be deferred or skipped |
| Firebase Storage costs for large .pkdrawing files | **Medium** | Save on explicit user action only; local-first via Core Data; warn on large files |
| VisionKit OCR accuracy for cursive handwriting | **Low-Medium** | Show recognized text for user confirmation before searching |
| Daily content requires 365 devotion entries (content, not code) | **Low** | Start with 30 entries, use `index % 30` lookup until full set is written |

---

## Verification / How to Test End-to-End
1. **Phase 0**: App launches on iOS Simulator without crash
2. **Phase 1**: App fetches and displays all available translations on first launch (1,500+); search for "Spanish" in translation browser → Spanish translations appear; select a translation → tap a book → tap a chapter → Bible text loads with copyright footer; pinch to zoom works; close app → reopen → cached chapter loads without network call; translation list loads instantly from cache (no API call)
3. **Phase 2**: Tap annotation mode → draw a stroke → switch to highlighter → draw highlight; undo removes last stroke; close and reopen chapter → annotation reappears exactly as drawn
4. **Phase 3**: Long-press a verse → bookmark sheet appears → pick color + emoji → bookmark saved; add a note tile → drag to reposition → close app → note is in same position on return; open app on consecutive days → streak count increases
5. **Phase 4**: Search "love" → results appear; search a handwritten word → OCR recognizes it → Bible search fires → result tapped → Reader opens to correct verse
6. **Phase 5**: Switch theme in Settings → all screens update immediately; open Daily tab → correct verse for today's date displays
7. **Phase 6**: Sign up with email → sign out → sign in with Apple → profile shows correct name; create a post → it appears in community feed; like a post → like count increments
8. **Phase 7**: VoiceOver reads all buttons correctly; archive builds without errors in Xcode Organizer
