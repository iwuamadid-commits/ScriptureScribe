# Scripture Scribe — iOS App Build Plan

## Context
Derrick and Stephanie (brother and sister) are building a native iOS Bible annotation app called Scripture Scribe. They are not developers — Claude writes all code and walks them through every step. The app allows users to read the Bible in multiple translations, annotate directly on the text (drawing, highlighting, typed notes, bookmarks, images), search both Bible text and handwritten notes, listen to audio Bible, track spiritual habits, and engage in a faith community.

**Decisions made:**
- Platform: iOS (iPhone + iPad) — universal
- Language: Swift + SwiftUI
- Architecture: MVVM, offline-first with Firebase sync
- Bible content: API.Bible REST API (1,500+ translations)
- Backend: Firebase (Auth, Firestore, Storage)
- AI: Anthropic Claude API (daily devotional generation, TTS text reformatting)
- Monetization: StoreKit 2 (weekly/monthly/yearly/lifetime subscriptions)
- Offline Bibles: KJV, WEB, ASV downloadable from Firebase Storage
- API.Bible rate limit: 5,000 queries/day; max 500 consecutive verses per request

---

## Architecture Overview

```
ScriptureScribe/ScriptureScribe/ScriptureScribe/
├── ScriptureScribeApp.swift      ← @main entry, Firebase config, all VMs as StateObjects
├── AppNavigation.swift           ← Cross-tab navigation state (pendingChapterId, pendingVerseNumbers, etc.)
├── ContentView.swift             ← Tab bar (Reader, Daily, Habits, Community, Library, Profile)
├── Core/
│   ├── Config/
│   │   ├── AppConfig.swift           ← API keys from Secrets.xcconfig (gitignored)
│   │   └── PremiumLimits.swift       ← Free-tier limits (colors, collections, habits, versions)
│   ├── Extensions/
│   │   ├── Color+Hex.swift           ← Hex color parsing
│   │   ├── CoachMarkModifier.swift   ← Walkthrough spotlight system (.coachMark("id") modifier)
│   │   ├── WrappingHStack.swift      ← Flow layout for tags
│   │   └── ZoomScrollView.swift      ← Pinch-to-zoom container
│   ├── Models/
│   │   ├── AppUser.swift             ← User profile
│   │   ├── Comment.swift             ← Community comments
│   │   ├── DailyAnswer.swift         ← Daily Q&A responses
│   │   ├── GratitudePost.swift       ← Gratitude entries
│   │   ├── Post.swift                ← Community reflection posts
│   │   ├── PrayerRequest.swift       ← Prayer requests
│   │   └── SavedDevotionalItem.swift ← Saved prayers/devotionals/affirmations
│   ├── Network/
│   │   └── BibleAPIService.swift     ← API.Bible + in-memory cache + offline fallback
│   ├── Persistence/
│   │   ├── OfflineBibleManager.swift ← Download/delete offline translations (Firebase Storage)
│   │   ├── OfflineBibleStore.swift   ← Local disk read/write for offline chapters
│   │   └── OfflineTranslationConfig.swift ← KJV/WEB/ASV config mapping
│   ├── Services/
│   │   ├── AdminManager.swift        ← Admin user detection (auto-premium)
│   │   ├── AnthropicService.swift    ← Claude API for TTS + devotional generation
│   │   ├── FirestoreService.swift    ← All Firestore reads/writes
│   │   ├── SubscriptionViewModel.swift ← StoreKit 2 premium management
│   │   ├── SubscriptionProduct.swift ← Product IDs (weekly/monthly/yearly/lifetime)
│   │   └── WalkthroughManager.swift  ← Interactive onboarding spotlight system
│   ├── Theme/
│   │   └── AppTheme.swift            ← Protocol + 8 themes (Ivory, Parchment, Midnight, etc.)
│   └── Utilities/
│       ├── BibleReferenceParser.swift ← Parse "John 3:16-18" etc.
│       └── PremiumGateModifier.swift  ← Reusable premium gate ViewModifier
├── Features/
│   ├── Annotation/   (14 files)  ← PencilKit canvas, toolbar, color pickers, lasso, crop, guides
│   ├── Audio/        (5 files)   ← Streaming audio + TTS fallback with verse-by-verse sync
│   ├── Auth/         (3 files)   ← Firebase Auth + Google Sign-In
│   ├── Bookmarks/    (5 files)   ← Verse bookmarks with 8 colors, emojis, groups/collections
│   ├── Community/    (22 files)  ← Posts, prayers, gratitude, daily Q&A with real-time listeners
│   ├── Daily/        (4 files)   ← AI-generated devotionals, calendar browsing, verse of the day
│   ├── Habits/       (6 files)   ← Habit tracking with goals, streaks, suggested plans
│   ├── Notes/        (4 files)   ← Draggable sticky notes on Bible text
│   ├── Onboarding/   (2 files)   ← First-launch slides + interactive walkthrough overlay
│   ├── Profile/      (1 file)    ← User profile, settings, premium info
│   ├── Reader/       (6 files)   ← Bible text, book/chapter nav, translation browser, offline downloads
│   ├── Saved/        (2 files)   ← Library tab (bookmarks, prayers, devotionals, affirmations)
│   ├── Search/       (4 files)   ← Text search, topic search, handwriting OCR search
│   ├── Sharing/      (4 files)   ← Verse image composer for social sharing
│   ├── Streaks/      (3 files)   ← Reading streak counter + calendar visualization
│   └── Subscription/ (1 file)    ← Paywall UI (4 pricing tiers)
```

---

## Key Frameworks

| Feature | Framework |
|---|---|
| Drawing / Annotation | `PencilKit` (PKCanvasView) |
| Color picker | Custom HSB wheel (Procreate-style) + compact preset picker |
| Handwriting OCR | `Vision` (VNRecognizeTextRequest) |
| Offline Bibles | JSON files on disk (Documents/OfflineBibles/) |
| Bible text | `API.Bible` REST API |
| Audio playback | `AVFoundation` (AVPlayer for streaming, AVSpeechSynthesizer for TTS) |
| Auth | `Firebase Auth` + `GoogleSignIn` |
| Community data | `Cloud Firestore` (real-time listeners) |
| Images/drawings | `Firebase Storage` |
| AI content | `Anthropic Claude API` (daily devotionals, TTS formatting) |
| Premium | `StoreKit 2` |
| Photos | `PhotosUI` (PHPickerViewController) |

---

## Firestore Schema

```
users/{uid}/
  ├── [profile fields, selectedTheme, selectedTranslation, isLeftHanded]
  ├── bookmarks/{bookmarkId} → { bibleId, bookId, chapterId, verseNumbers[], verseText, color, emoji, groupId, createdAt }
  ├── notes/{noteId} → { bibleId, bookId, chapterId, verseId, text, xFraction, yFraction, width, height, color, createdAt }
  ├── habits/{habitId} → { name, goal, frequency, timeRange, taskDays[], createdAt }
  ├── habitLogs/{logId} → { habitId, date, value }
  └── savedItems/{itemId} → { type, date, title, content, verseReference, createdAt }

posts/{postId} → { authorId, authorName, text, imageURL, verseReference, likedBy[], commentCount, reportedBy[] }
comments/{commentId} → { postId, authorId, authorName, text, createdAt }
prayerRequests/{id} → { authorId, authorName, text, likedBy[], commentCount, createdAt }
gratitudePosts/{id} → { authorId, authorName, text, likedBy[], commentCount, createdAt }
dailyAnswers/{id} → { questionDate, authorId, authorName, text, likedBy[], commentCount, createdAt }
daily_content/{YYYY-MM-DD} → { verseReference, verseId, prayer, devotion, reflectionQuestions[] }
```

Firebase Storage paths:
- `annotations/{uid}/{bibleId}/{chapterId}.pkdrawing`
- `offline-bibles/KJV.json.gz`, `WEB.json.gz`, `ASV.json.gz`
- `profile_images/{uid}/profile.jpg`
- `post_images/{postId}/image.jpg`

---

## 8 Themes
1. **Ivory** — clean white, sage green accent (default for new users)
2. **Parchment** — warm cream, dark ink, old Bible paper feel
3. **Midnight** — deep navy, gold accents, dark mode premium
4. **Serene** — soft lavender and white, gentle pastels
5. **Forest** — deep green, warm tan, earthy
6. **Sunset** — warm oranges, peach gradients
7. **Sage** — cool grey-green, minimal modern
8. **Royal** — deep burgundy, gold, classical

All defined via `AppTheme` protocol; `ThemeManager` persists selection via `@AppStorage`.

---

## Feature Status

### Fully Built
| Feature | Key Files | Notes |
|---|---|---|
| **Bible Reader** | `ReaderView`, `BibleTextView`, `BookBrowserView`, `TranslationBrowserView` | 1,500+ translations, book/chapter nav, font/spacing settings, red-letter support |
| **Offline Bibles** | `OfflineBibleManager`, `OfflineBibleStore`, `OfflineTranslationConfig` | KJV/WEB/ASV downloadable (~4-6 MB each), transparent fallback in BibleAPIService |
| **Annotation Engine** | `AnnotationCanvasView`, `AnnotationToolbarView`, `ColorPickerWheelView` | PencilKit overlay, pen/highlighter/eraser/lasso/hand tools, auto-shape detection, saved colors |
| **Audio Bible** | `AudioPlayerViewModel`, `AudioPlayerView`, `VoiceSelectorView` | Streaming via API.Bible + AVSpeechSynthesizer TTS fallback, verse-by-verse auto-scroll |
| **Bookmarks** | `BookmarksViewModel`, `BookmarkListView`, `BookmarkPickerView` | 8 ribbon colors, emojis, groups/collections, non-consecutive verse support |
| **Notes** | `NotesViewModel`, `NoteTileView`, `NoteEditorView` | Draggable sticky notes, 6 colors, position as fractions |
| **Habits** | `HabitsViewModel`, `HabitsView`, `CreateHabitView` | Goal/frequency tracking, ISO weekdays, streaks, suggested plans, 3 free limit |
| **Daily Devotionals** | `DailyViewModel`, `DailyView`, `CalendarSheetView` | Claude AI generation → Firestore cache → local JSON fallback, calendar browsing |
| **Community** | `FeedView`, `CommunityViewModel`, `PrayerViewModel`, `GratitudeViewModel`, `DailyQuestionViewModel` | 4 sub-tabs (reflections, prayers, gratitude, daily Q&A), real-time Firestore listeners |
| **Search** | `SearchViewModel`, `SearchView`, `HandwritingIndexService` | Text search, topic search, handwriting OCR (GoodNotes-style index) |
| **Streaks** | `StreakViewModel`, `StreakBadgeView`, `StreakDetailView` | Consecutive day counter, calendar visualization, @AppStorage |
| **Auth** | `AuthViewModel`, `AuthService`, `AuthView` | Firebase Auth + Google Sign-In |
| **Premium** | `SubscriptionViewModel`, `PaywallView`, `PremiumLimits` | StoreKit 2, 4 tiers (weekly/monthly/yearly/lifetime), admin auto-premium |
| **Themes** | `AppTheme.swift` | 8 themes, dark/light auto, @AppStorage persistence |
| **Sharing** | `VerseImageComposerView`, `BackgroundPickerView`, `FontPickerBar` | Compose verse images with backgrounds/fonts for social sharing |
| **Onboarding** | `OnboardingView`, `WalkthroughOverlayView`, `WalkthroughManager` | First-launch slides + interactive spotlight tour with welcome card |
| **Library (Saved)** | `SavedView`, `SavedDevotionalsViewModel` | 4 sub-tabs: bookmarks, prayers, devotionals, affirmations |

### Partially Built
| Feature | Status | What's Missing |
|---|---|---|
| **Profile** | Basic UI | Settings page exists; could be expanded with more user stats |
| **Lasso Color Picker** | Broken | `LassoOverlayView.swift` — sheet may not open, `recolorLassoSelection` needs debugging |

---

## Premium Limits (Free Tier)

| Feature | Free | Premium |
|---|---|---|
| Bookmark colors | 4 of 8 (Gold, Red, Green, Blue) | All 8 |
| Bookmark collections | 2 | Unlimited |
| Habits | 3 | Unlimited |
| Saved annotation colors | 3 | Unlimited |
| Bible versions (My Versions) | 3 | Unlimited |

---

## Key Architecture Patterns

### Offline-First + Firebase Sync
- UserDefaults stores data locally first (bookmarks, notes, habits, streaks)
- On sign-in, `syncOnSignIn(userId:)` merges local + Firestore
- App works entirely offline without login
- Every mutation mirrored to Firestore when signed in

### Premium Gating
```swift
@State private var showPaywall = false
// Never use subscriptionVM.showPaywall — always local @State
if !subscriptionVM.isPremium && count >= PremiumLimits.maxFree* {
    showPaywall = true
}
```

### Cross-Tab Navigation (AppNavigation)
- `pendingChapterId` → Reader jumps to chapter
- `pendingVerseNumbers` → Reader scrolls to + flashes verses
- `pendingCommunityTab` → Community opens specific sub-tab
- `pendingSavedTab` → Library opens specific sub-tab
- `pendingDailyDate` → Daily tab loads specific date

### Real-Time Firestore Listeners
- Community posts, prayers, gratitude, daily answers use `addSnapshotListener`
- Listeners registered on appear, cleaned up on disappear

### CoachMark Walkthrough System
- `.coachMark("id")` modifier reports frame via `CoachMarkFrameKey` preference
- `WalkthroughManager` tracks steps with spotlight coordinates
- `WalkthroughOverlayView` renders dimmed overlay with spotlight cutout + tooltip

---

## Critical Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Translation copyright — strict rules per translation | **Critical** | `copyrightStatement` displayed as footer on every chapter |
| PencilKit canvas blocks ScrollView touch | **High** | Annotation Mode toggle — canvas only active in drawing mode |
| API.Bible rate limits (5,000/day) | **High** | In-memory cache + offline Bible downloads for KJV/WEB/ASV |
| Firebase costs at scale | **Medium** | Offline-first reduces reads; local caching; Firestore rules |
| Lasso color picker broken | **Medium** | Needs debugging — sheet may not open or color not applied |

---

## Remaining Work (Pre-App Store)

1. **Fix lasso color picker** — debug sheet presentation and color application
2. **Sign in with Apple** — required by App Store (currently only Google Sign-In)
3. **Push notifications** — Firebase Cloud Messaging for daily reminders
4. **Accessibility audit** — VoiceOver labels on all interactive elements
5. **App Store assets** — icons, screenshots, metadata
6. **Apple Developer Program enrollment** ($99/year)
7. **TestFlight beta testing**
8. **Archive + submit for review**

---

## File Statistics

- **Total Swift files:** ~167
- **Core infrastructure:** ~29 files
- **Feature modules:** ~134 files
- **Largest modules:** Community (22), Annotation (14), Habits (6), Reader (6)
