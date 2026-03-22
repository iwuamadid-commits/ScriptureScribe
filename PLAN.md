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
- API.Bible rate limit: 5,000 queries/day; max 500 consecutive verses per request
- Disk caching: Translations (7-day TTL), books/chapters (30-day TTL) in Caches/BibleAPICache/
- Data persistence: User content (bookmarks, notes, habits, saved items) syncs to Firestore per-account. Preferences (theme, font, tool settings) are device-local only (UserDefaults). Annotations (.pkdrawing files) are device-local per-chapter.
- Sign-out behavior: Local data stays on device. Only account deletion clears everything.
- Bundle ID: `com.derrickiwuamadi.ScriptureScribe` (Firebase + Xcode + Apple Developer Portal aligned)

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
│   │   ├── Error+UserFriendly.swift  ← Maps Firebase/StoreKit/network errors to user-friendly messages
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
│   │   └── BibleAPIService.swift     ← API.Bible + disk cache (TTL) + HTML parsing
│   ├── Services/
│   │   ├── AdminManager.swift        ← Admin user detection (auto-premium)
│   │   ├── AnthropicService.swift    ← Claude API for TTS + devotional generation
│   │   ├── FirestoreService.swift    ← All Firestore reads/writes + syncData
│   │   ├── NetworkMonitor.swift     ← Real-time connectivity detection (NWPathMonitor)
│   │   ├── SubscriptionViewModel.swift ← StoreKit 2 premium management
│   │   ├── SubscriptionProduct.swift ← Product IDs (weekly/monthly/yearly/lifetime)
│   │   └── WalkthroughManager.swift  ← Interactive onboarding spotlight system
│   ├── Theme/
│   │   └── AppTheme.swift            ← Protocol + 8 themes (Ivory, Parchment, Midnight, etc.)
│   └── Utilities/
│       ├── BibleReferenceParser.swift ← Parse "John 3:16-18" etc.
│       └── PremiumGateModifier.swift  ← Reusable premium gate ViewModifier
├── Features/
│   ├── Admin/       (2 files)   ← Admin dashboard for content moderation (flagged content queue)
│   ├── Annotation/  (14 files)  ← PencilKit canvas, toolbar, color pickers, lasso, crop, guides
│   ├── Audio/       (5 files)   ← Streaming audio + TTS fallback with verse-by-verse sync
│   ├── Auth/        (3 files)   ← Firebase Auth + Google Sign-In + Sign in with Apple
│   ├── Bookmarks/   (5 files)   ← Verse bookmarks with 8 colors, emojis, groups/collections
│   ├── Community/   (22 files)  ← Posts, prayers, gratitude, daily Q&A with real-time listeners
│   ├── Daily/       (4 files)   ← AI-generated devotionals, calendar browsing, verse of the day
│   ├── Habits/      (6 files)   ← Habit tracking with goals, streaks, suggested plans
│   ├── Notes/       (4 files)   ← Draggable sticky notes on Bible text
│   ├── Onboarding/  (2 files)   ← First-launch slides + interactive walkthrough overlay
│   ├── Profile/     (1 file)    ← User profile, settings, premium info, admin link
│   ├── Reader/      (6 files)   ← Bible text, book/chapter nav, translation browser, offline downloads
│   ├── Saved/       (2 files)   ← Library tab (bookmarks, prayers, devotionals, affirmations)
│   ├── Search/      (4 files)   ← Text search, topic search, handwriting OCR search
│   ├── Sharing/     (4 files)   ← Verse image composer for social sharing
│   ├── Streaks/     (3 files)   ← Reading streak counter + calendar visualization
│   └── Subscription/ (1 file)   ← Paywall UI (4 pricing tiers)
```

---

## Key Frameworks

| Feature | Framework |
|---|---|
| Drawing / Annotation | `PencilKit` (PKCanvasView) |
| Color picker | Custom HSB wheel (Procreate-style) + compact preset picker |
| Handwriting OCR | `Vision` (VNRecognizeTextRequest) |
| Bible text | `API.Bible` REST API |
| Disk caching | FileManager Caches directory with TTL |
| Network detection | `Network` framework (NWPathMonitor) |
| Audio playback | `AVFoundation` (AVPlayer for streaming, AVSpeechSynthesizer for TTS) |
| Auth | `Firebase Auth` + `GoogleSignIn` + `Sign in with Apple` |
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
  ├── savedItems/{itemId} → { type, date, title, content, verseReference, createdAt }
  └── syncData/state → { lastBibleId, lastBookId, lastChapterId, myVersionIds[] }

posts/{postId} → { userId, displayName, text, verseRef, verseText, likeCount, commentCount, reportedBy[], adminReviewed }
  └── comments/{commentId} → { postId, userId, displayName, text, likeCount, parentCommentId, reportedBy[], createdAt }
prayerRequests/{id} → { userId, displayName, text, prayingCount, commentCount, reportedBy[], adminReviewed, createdAt }
gratitudePosts/{id} → { userId, displayName, text, imageBase64, likeCount, commentCount, reportedBy[], adminReviewed, createdAt }
dailyAnswers/{id} → { userId, displayName, text, date, devotionDay, likeCount, commentCount, reportedBy[], adminReviewed, createdAt }
daily_content/{YYYY-MM-DD} → { verseReference, verseId, prayer, devotion, reflectionQuestions[] }
```

Firebase Storage paths:
- `annotations/{uid}/{bibleId}/{chapterId}.pkdrawing`
- `profilePhotos/{uid}.jpg`

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
| **Bible Reader** | `ReaderView`, `BibleTextView`, `BookBrowserView`, `TranslationBrowserView` | 1,500+ translations, book/chapter nav, font/spacing settings, red-letter support, disk caching |
| **Annotation Engine** | `AnnotationCanvasView`, `AnnotationToolbarView`, `ColorPickerWheelView` | PencilKit overlay, pen/highlighter/eraser/lasso/hand tools, auto-shape detection, saved colors |
| **Audio Bible** | `AudioPlayerViewModel`, `AudioPlayerView`, `VoiceSelectorView` | Streaming via API.Bible + AVSpeechSynthesizer TTS fallback, verse-by-verse auto-scroll |
| **Bookmarks** | `BookmarksViewModel`, `BookmarkListView`, `BookmarkPickerView` | 8 ribbon colors, emojis, groups/collections, non-consecutive verse support |
| **Notes** | `NotesViewModel`, `NoteTileView`, `NoteEditorView` | Draggable sticky notes, 6 colors, position as fractions |
| **Habits** | `HabitsViewModel`, `HabitsView`, `CreateHabitView` | Goal/frequency tracking, ISO weekdays, streaks, suggested plans, 3 free limit |
| **Daily Devotionals** | `DailyViewModel`, `DailyView`, `CalendarSheetView` | Claude AI generation, Firestore cache, local JSON fallback, calendar browsing |
| **Community** | `FeedView`, `CommunityViewModel`, `PrayerViewModel`, `GratitudeViewModel`, `DailyQuestionViewModel` | 4 sub-tabs (reflections, prayers, gratitude, daily Q&A), real-time Firestore listeners |
| **Search** | `SearchViewModel`, `SearchView`, `HandwritingIndexService` | Text search, topic search, handwriting OCR (GoodNotes-style index) |
| **Streaks** | `StreakViewModel`, `StreakBadgeView`, `StreakDetailView` | Consecutive day counter, calendar visualization, @AppStorage |
| **Auth** | `AuthViewModel`, `AuthService`, `AuthView` | Firebase Auth + Google Sign-In + Sign in with Apple |
| **Premium** | `SubscriptionViewModel`, `PaywallView`, `PremiumLimits` | StoreKit 2, 4 tiers (weekly/monthly/yearly/lifetime), admin auto-premium |
| **Themes** | `AppTheme.swift` | 8 themes, dark/light auto, @AppStorage persistence |
| **Sharing** | `VerseImageComposerView`, `BackgroundPickerView`, `FontPickerBar` | Compose verse images with backgrounds/fonts for social sharing |
| **Onboarding** | `OnboardingView`, `WalkthroughOverlayView`, `WalkthroughManager` | First-launch slides + interactive spotlight tour with welcome card |
| **Library (Saved)** | `SavedView`, `SavedDevotionalsViewModel` | 4 sub-tabs: bookmarks, prayers, devotionals, affirmations |
| **Admin Dashboard** | `AdminView`, `AdminViewModel` | Flagged content queue, remove/dismiss actions, user count, admin-only in ProfileView |

### Recently Added (March 2026)
| Feature | Key Files | Notes |
|---|---|---|
| **Disk Caching** | `BibleAPIService.swift` | Translations (7d TTL), books/chapters (30d TTL) — instant load on subsequent launches |
| **Offline Banner** | `NetworkMonitor.swift`, `ContentView.swift` | NWPathMonitor detects connectivity; banner above tab bar when offline |
| **Camera Permissions** | `AnnotationToolbarView.swift`, `Info.plist` | Checks AVCaptureDevice auth, "Open Settings" alert if denied |
| **Cross-Device Sync** | `ReaderViewModel.swift`, `StreakViewModel.swift`, `FirestoreService.swift` | Reading position, My Versions, streaks sync to Firestore `syncData/state` |
| **Chapter Transitions** | `ReaderViewModel.swift` | Separated state updates with 250ms delay for smooth fade-out before content swap |

### Partially Built
| Feature | Status | What's Missing |
|---|---|---|
| **Profile** | Basic UI | Settings page exists; could be expanded with more user stats |
| **Lasso Color Picker** | Broken | `LassoOverlayView.swift` — sheet may not open, `recolorLassoSelection` needs debugging |

### App Store Compliance (DONE)
| Feature | Status |
|---|---|
| **Account Deletion** | Done — `AuthService.deleteAccount()`, ProfileView button with re-auth handling |
| **Privacy Policy / ToS** | Done — Links in ProfileView + AuthView, hosted on Notion |
| **Content Reporting** | Done — `reportedBy[]` on all community models, context menu report buttons, real-time feed filtering |
| **Content Moderation** | Done — Admin dashboard with flagged queue, remove/dismiss with `adminReviewed` flag |
| **Privacy Manifest** | Done — `PrivacyInfo.xcprivacy` with UserDefaults API declaration |
| **Sign in with Apple** | Done — Entitlements, capability, Firebase bundle ID aligned |

### Bug Fixes (March 20, 2026)
| Fix | Details |
|---|---|
| **Apple Sign-In** | Added entitlement, aligned Firebase bundle ID (`com.derrickiwuamadi.ScriptureScribe`) |
| **Google Sign-In freeze** | Updated reversed client ID URL scheme in Info.plist to match new GoogleService-Info.plist |
| **Cancellation errors shown to users** | Filtered Apple/Google sign-in cancellations, StoreKit cancellations, task cancellations in Search/Reader |
| **User-friendly error messages** | `Error+UserFriendly.swift` maps Firebase Auth/Firestore/Storage/StoreKit/network errors to clean messages. Raw errors logged to console for developers. |
| **Force unwrap crashes** | Fixed `points.first!`/`.min()!` crashes in AnnotationCanvasView shape recognition |
| **Auth race condition** | `isSignedIn` now set AFTER `currentUser` in auth state listener |
| **Premium leak between accounts** | `checkEntitlement()` called on user switch for non-admins; `isPremiumCached` cleared on sign-out |
| **Base64 image re-decoded every render** | GratitudeCardView now caches decoded UIImage in @State |
| **Camera permission typo** | "phots" to "photos" in NSCameraUsageDescription |
| **Report doesn't hide post** | Real-time feed listeners now filter by `reportedBy` (reporter's posts hidden, 5+ hidden from all) |
| **Preferences sync removed** | Deleted PreferencesManager.swift entirely. Preferences are device-local only. |
| **Debug premium override** | `-isPremiumCached YES` scheme argument no longer overridden by `checkEntitlement()` |

### Bug Fixes (March 21, 2026)
| Fix | Details |
|---|---|
| **Slow Bible loading** | Added disk caching — translations, books, chapters cached to Caches/ with TTL |
| **Premium cache overridden** | `#if DEBUG` guard in `checkEntitlement()` prevents StoreKit from clearing debug flag |
| **Choppy chapter transitions** | Separated `selectedChapter` and `chapterContent` updates with 250ms delay |
| **App loading deadlock** | `isLoadingTranslations` initial value reverted to false; fallback view shows spinner |
| **Psalm 119 heading dots** | Strip leading dots/colons from heading buffer in HTML parser |
| **Calendar duplicate month/year** | Removed `.navigationTitle(monthTitle)` from CalendarSheetView |
| **Offline Bible download removed** | All references removed from TranslationBrowserView (offlineBibleManager, download UI) |

---

## Content Moderation System

### How Reporting Works
1. User taps report on any community content (post, prayer, gratitude, daily answer)
2. Their user ID is added to the `reportedBy` array in Firestore
3. Real-time listener filter hides the content from the reporter immediately
4. Content with 5+ reports is hidden from ALL non-admin users
5. Admins see everything unfiltered in both the feeds and the Admin Dashboard

### Admin Dashboard (Profile > Admin Dashboard)
- Only visible to users in `AdminManager.adminUserIDs`
- Shows all content with 1+ reports (excluding admin-reviewed items under 5 reports)
- Stats bar: flagged count, auto-hidden count (5+), total users
- **Remove**: Permanently deletes the content from Firestore (with confirmation)
- **Dismiss**: Sets `adminReviewed = true`. Content leaves the admin queue but stays hidden for reporters. If reports later reach 5+, it re-surfaces in the queue.

### Visibility Rules
| Reports | Reporter sees it? | Everyone else? | In admin queue? |
|---------|-------------------|---------------|----------------|
| 1-4 (not reviewed) | No (permanently) | Yes | Yes |
| 1-4 (admin dismissed) | No (permanently) | Yes | No |
| 5+ | No | No | Yes (even if previously dismissed) |
| Admin removed | Gone | Gone | Gone |

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
- App works entirely offline without login (disk-cached Bible content)
- Every mutation mirrored to Firestore when signed in
- Cross-device sync: reading position, My Versions, streaks via `syncData/state`
- Preferences (theme, font, tool settings) stay device-local, never synced
- Offline banner shown via `NetworkMonitor` when connectivity lost

### Premium Gating
```swift
@State private var showPaywall = false
// Never use subscriptionVM.showPaywall — always local @State
if !subscriptionVM.isPremium && count >= PremiumLimits.maxFree* {
    showPaywall = true
}
```

### Cross-Tab Navigation (AppNavigation)
- `pendingChapterId` -> Reader jumps to chapter
- `pendingVerseNumbers` -> Reader scrolls to + flashes verses
- `pendingCommunityTab` -> Community opens specific sub-tab
- `pendingSavedTab` -> Library opens specific sub-tab
- `pendingDailyDate` -> Daily tab loads specific date

### Real-Time Firestore Listeners
- Community posts, prayers, gratitude, daily answers use `addSnapshotListener`
- Listeners registered on appear, cleaned up on disappear
- All listener callbacks filter `reportedBy` for content moderation

### CoachMark Walkthrough System
- `.coachMark("id")` modifier reports frame via `CoachMarkFrameKey` preference
- `WalkthroughManager` tracks steps with spotlight coordinates
- `WalkthroughOverlayView` renders dimmed overlay with spotlight cutout + tooltip

### Error Handling
- All user-facing errors go through `Error.userMessage` (Error+UserFriendly.swift)
- Maps Firebase Auth/Firestore/Storage error codes to clean messages
- Cancellation errors (user dismissed sheet, task cancelled) are silently ignored
- Raw errors logged to console via `print("[Error] ...")` for developer debugging

---

## Critical Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Translation copyright — strict rules per translation | **Critical** | `copyrightStatement` displayed as footer on every chapter |
| PencilKit canvas blocks ScrollView touch | **High** | Annotation Mode toggle — canvas only active in drawing mode |
| API.Bible rate limits (5,000/day) | **High** | Disk cache with TTL reduces API calls significantly |
| Firebase costs at scale | **Medium** | Offline-first reduces reads; local caching; Firestore rules |
| Lasso color picker broken | **Medium** | Needs debugging — sheet may not open or color not applied |

---

## Remaining Work (Pre-App Store)

1. **Fix lasso color picker** — debug sheet presentation and color application
2. **App Store assets** — icons, screenshots, metadata
3. **App Store Connect setup** — create app listing, in-app purchases, pricing
4. **TestFlight beta testing**
5. **Archive + submit for review**

### Completed POVs (no longer needed)
- ~~Offline experience~~ — DONE (NetworkMonitor + offline banner + disk cache)
- ~~Permissions denied~~ — DONE (camera permission alert with "Open Settings")
- ~~Reinstall / new device~~ — DONE (cross-device sync for reading position, My Versions, streaks)
- ~~Slow network~~ — Skipped (disk cache handles most cases)
- ~~Accessibility~~ — Deferred (not essential for v1)
- ~~Child/family device~~ — Deferred (not essential for v1)

---

## Debug Scheme Arguments

| Argument | Effect |
|---|---|
| `-isPremiumCached YES` | Forces premium on for any account (skips StoreKit check in DEBUG) |
| `-hasSeenOnboarding NO` | Resets onboarding flow (shows first-launch slides) |
| `-hasCompletedWalkthrough NO` | Resets walkthrough (shows interactive spotlight tour) |

---

## File Statistics

- **Total Swift files:** ~170
- **Core infrastructure:** ~30 files
- **Feature modules:** ~136 files
- **Largest modules:** Community (22), Annotation (14), Habits (6), Reader (6)
