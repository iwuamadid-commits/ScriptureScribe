# Scripture Scribe

A native iOS Bible annotation app built with SwiftUI. Read the Bible in 1,500+ translations, annotate directly on the text with Apple Pencil or finger, track spiritual habits, and connect with a faith community.

**Available on the App Store.**

---

## Features

### Bible Reader
- 1,500+ translations via API.Bible
- Book and chapter navigation with horizontal scrollable book selector
- Red-letter support (Words of Jesus)
- Font size, spacing, and theme customization
- Disk caching for instant loading and offline access
- Swipe to change chapters

### Annotation Engine
- PencilKit-powered drawing overlay (pen, highlighter, eraser)
- Lasso tool for selecting, moving, resizing, recoloring, and deleting strokes
- Auto-shape detection (lines, circles, rectangles)
- Photo insertion from camera or photo library
- Draggable sticky notes on Bible text
- Saved color palette (Procreate-style HSB color wheel)
- Unified undo/redo across all annotation tools

### Audio Bible
- Streaming audio via API.Bible
- Text-to-speech fallback with verse-by-verse auto-scroll
- AI-reformatted text for natural TTS narration

### Bookmarks
- 8 ribbon colors with emoji support
- Groups and collections
- Non-consecutive verse selection

### Daily Devotionals
- AI-generated prayers, devotionals, affirmations, and reflection questions (Claude API)
- Calendar browsing with local JSON fallback
- Verse of the day

### Habits & Streaks
- Custom habit tracking with goals and frequency
- Reading streak counter with calendar visualization
- Cross-device streak sync

### Community
- Scripture reflections, prayer requests, gratitude posts, daily Q&A
- Real-time Firestore listeners
- Content reporting and admin moderation dashboard

### Search
- Bible text search across translations
- Topic-based search
- Handwriting OCR search (GoodNotes-style index via Vision framework)

### Sharing
- Verse image composer with custom backgrounds and fonts for social sharing

### Premium (StoreKit 2)
- Monthly and yearly subscription tiers
- Free tier with generous limits (4 bookmark colors, 2 collections, 3 habits, 3 saved colors, 3 Bible versions)

### 8 Themes
Ivory (default), Parchment, Midnight, Serene, Forest, Blossom, Slate, Royal

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI + UIKit (PencilKit, gesture recognizers) |
| Architecture | MVVM, offline-first |
| Bible Content | [API.Bible](https://scripture.api.bible) REST API with disk caching |
| Auth | Firebase Auth + Google Sign-In + Sign in with Apple |
| Database | Cloud Firestore (real-time sync) |
| Storage | Firebase Storage (profile photos, annotations) |
| AI | Anthropic Claude API (devotionals, TTS formatting) |
| Drawing | PencilKit + Vision (OCR) |
| Audio | AVFoundation (AVPlayer + AVSpeechSynthesizer) |
| Monetization | StoreKit 2 |
| Packages | Firebase iOS SDK (v11.0+), GoogleSignIn-iOS (v9.1+) |

---

## Setup

### Prerequisites
- Xcode 15+
- iOS 17.0+ (iPhone and iPad)
- An [API.Bible](https://scripture.api.bible/profile) API key
- A Firebase project with Auth, Firestore, and Storage enabled
- (Optional) An [Anthropic](https://console.anthropic.com) API key for AI-generated devotionals

### 1. Clone the repo

```bash
git clone https://github.com/iwuamadid-commits/ScriptureScribe.git
cd ScriptureScribe
```

### 2. Configure secrets

Copy the secrets template and add your API keys:

```bash
# Edit Secrets.xcconfig (gitignored)
open Secrets.xcconfig
```

Set these values:
```
BIBLE_API_KEY = your_api_bible_key_here
ANTHROPIC_API_KEY = your_claude_api_key_here
```

### 3. Add Firebase config

Place your `GoogleService-Info.plist` in:
```
ScriptureScribe/ScriptureScribe/ScriptureScribe/GoogleService-Info.plist
```

### 4. Xcode configuration

1. Open `ScriptureScribe/ScriptureScribe.xcodeproj`
2. Go to **Project > Info > Configurations**
3. Set `Secrets.xcconfig` for both Debug and Release
4. Build and run on an iOS simulator or device

### Debug Launch Arguments

| Argument | Effect |
|---|---|
| `-isPremiumCached YES` | Forces premium on (skips StoreKit check in DEBUG) |
| `-hasSeenOnboarding NO` | Resets onboarding slides |
| `-hasCompletedWalkthrough NO` | Resets interactive walkthrough |

---

## Project Structure

```
ScriptureScribe/ScriptureScribe/ScriptureScribe/
├── ScriptureScribeApp.swift          # @main entry point
├── ContentView.swift                 # Tab bar (Reader, Daily, Habits, Community, Library, Profile)
├── Core/
│   ├── Config/                       # API keys, premium limits
│   ├── Extensions/                   # Color+Hex, ZoomScrollView, CoachMark, etc.
│   ├── Models/                       # Data models (AppUser, Post, Comment, etc.)
│   ├── Network/                      # BibleAPIService + disk cache
│   ├── Services/                     # Firebase, Anthropic, StoreKit, NetworkMonitor
│   ├── Theme/                        # 8 themes via AppTheme protocol
│   └── Utilities/                    # Bible reference parser, premium gate modifier
├── Features/
│   ├── Admin/                        # Content moderation dashboard
│   ├── Annotation/                   # PencilKit canvas, toolbar, color pickers, lasso
│   ├── Audio/                        # Streaming audio + TTS
│   ├── Auth/                         # Firebase Auth + Google + Apple sign-in
│   ├── Bookmarks/                    # Verse bookmarks with colors and collections
│   ├── Community/                    # Posts, prayers, gratitude, daily Q&A
│   ├── Daily/                        # AI devotionals + calendar
│   ├── Habits/                       # Habit tracking with streaks
│   ├── Notes/                        # Draggable sticky notes
│   ├── Onboarding/                   # First-launch slides + walkthrough
│   ├── Profile/                      # User settings
│   ├── Reader/                       # Bible text + navigation
│   ├── Saved/                        # Library (bookmarks, prayers, devotionals)
│   ├── Search/                       # Text, topic, and handwriting search
│   ├── Sharing/                      # Verse image composer
│   ├── Streaks/                      # Reading streak visualization
│   └── Subscription/                 # Paywall UI
```

---

## Architecture

### Offline-First
- Bible content cached to disk with TTL (translations 7 days, books/chapters 30 days)
- App works without login or internet using cached content
- User content (bookmarks, notes, habits) syncs to Firestore when signed in
- Preferences (theme, font, tool settings) are device-local only

### Cross-Device Sync
- Reading position, Bible versions, and streaks sync via Firestore `syncData/state`
- Saves on app background, restores on launch
- Merge strategies: union for dates, "keep higher" for streaks, no-duplicate for versions

### Content Moderation
- Users can report community content
- Reported content hidden from reporter immediately
- 5+ reports hides content from all non-admin users
- Admin dashboard for review, dismiss, or remove actions

---

## License

All rights reserved.
