# Virtual Help — Complete Final Architecture
> One App · Two Modes · Three Categories · Personalized Watch History · 25 Languages · No Auth · No Database

---

## Table of Contents

1. [Big Picture Overview](#1-big-picture-overview)
2. [Architecture Philosophy](#2-architecture-philosophy)
3. [Server Folder Structure](#3-server-folder-structure)
4. [The Two Config Files](#4-the-two-config-files)
5. [Language File System](#5-language-file-system)
6. [API Endpoint — Catalog Mode](#6-api-endpoint--catalog-mode)
7. [Response Body — Full Catalog](#7-response-body--full-catalog)
8. [Language Resolution Logic](#8-language-resolution-logic)
9. [Server Caching Strategy](#9-server-caching-strategy)
10. [Local State — Full Schema](#10-local-state--full-schema)
11. [Install ID Generation](#11-install-id-generation)
12. [Seeded Shuffle Algorithm](#12-seeded-shuffle-algorithm)
13. [Watch Progress Threshold](#13-watch-progress-threshold)
14. [Flutter App — Complete Flow](#14-flutter-app--complete-flow)
15. [Mode Handling](#15-mode-handling)
16. [Language Change Handling](#16-language-change-handling)
17. [New Video Sync — catalog_version System](#17-new-video-sync--catalog_version-system)
18. [Category Reset Rules](#18-category-reset-rules)
19. [Video Selection Algorithm (Per-Open Stability)](#19-video-selection-algorithm-per-open-stability)
20. [Flutter Packages](#20-flutter-packages)
21. [Adding a New Video — Full Workflow](#21-adding-a-new-video--full-workflow)
22. [Edge Cases — Every One Handled](#22-edge-cases--every-one-handled)
23. [Offline Behaviour](#23-offline-behaviour)
24. [Scale Reality Check](#24-scale-reality-check)
25. [What This Does NOT Handle (v2 Roadmap)](#25-what-this-does-not-handle-v2-roadmap)
26. [Final Summary](#26-final-summary)

---

## 1. Big Picture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          FLUTTER APP                                │
│                                                                     │
│  App opens → determines mode (period / pregnancy)                   │
│  Checks local catalog cache → catalog_version changed?              │
│  If yes: GET /api/catalog?mode=period&lang=hi                       │
│  If no:  use stored catalog, zero network call                      │
│                                                                     │
│  Apply local_state queue → pick next 2 unwatched per category       │
│  Render feed → user watches → mark watched → save state             │
└────────────────────────────┬────────────────────────────────────────┘
                             │ one request per catalog_version change
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          YOUR SERVER                                │
│                                                                     │
│  1. Read videos.json → get all video IDs for this mode              │
│  2. Load content.{lang}.json → resolve all titles + descs           │
│  3. Resolve all video URLs (with lang fallback)                     │
│  4. Return full catalog JSON                                        │
│  5. Cache result in memory keyed by mode+lang+catalog_version       │
└────────────────────────────┬────────────────────────────────────────┘
                             │ full catalog JSON (all videos, all text)
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                             CDN                                     │
│                                                                     │
│  Flutter streams .mp4 directly from CDN URL in catalog              │
│  Thumbnails also served from CDN                                    │
│  Server never touches video bytes                                   │
└─────────────────────────────────────────────────────────────────────┘
```

**No user accounts. No auth. No database. No user tracking.**
Personalization is 100% on-device using local_state. Server stays dumb.
Server serves a catalog. Client decides what to show.

---

## 2. Architecture Philosophy

### Broadcast Model (Old) vs. Personalized Queue Model (New)

| Dimension | Old (Date-Based Rotation) | New (Watch History Queue) |
|---|---|---|
| Who decides today's videos | Server (date math) | Client (watch history) |
| Same response for all users | Yes | No |
| State lives where | Nowhere (stateless) | On device (local) |
| Server complexity | Zero | Zero (stays same) |
| Works offline | Yes | Yes |
| Personalisation | None | Full per-device |
| Repeat prevention | 7-day min (if 7+ videos) | Never repeats until all watched |
| New video visibility | Next day | Next app open (via catalog_version sync) |

### Core Principle
The server is a **catalog server**, not a rotation engine. All intelligence — what to show, what is watched, what comes next — lives entirely in the Flutter app on the user's device. The server's only job is to hand over a complete, resolved catalog of all videos with text already translated and URLs already resolved.

---

## 3. Server Folder Structure

```
/server-root/
│
├── videos/
│   ├── period/
│   │   ├── tips/
│   │   │   ├── 001/
│   │   │   │   ├── en.mp4           ← always present (guaranteed fallback)
│   │   │   │   ├── hi.mp4
│   │   │   │   ├── af.mp4
│   │   │   │   ├── am.mp4
│   │   │   │   ├── ta.mp4
│   │   │   │   └── thumb.jpg        ← always present (guaranteed)
│   │   │   ├── 002/
│   │   │   │   ├── en.mp4
│   │   │   │   ├── hi.mp4
│   │   │   │   └── thumb.jpg
│   │   │   └── 003/ ...
│   │   │
│   │   ├── awareness/
│   │   │   ├── 001/
│   │   │   ├── 002/
│   │   │   └── 003/ ...
│   │   │
│   │   └── avoid/
│   │       ├── 001/
│   │       └── 002/ ...
│   │
│   └── pregnancy/
│       ├── tips/
│       │   ├── 001/
│       │   └── 002/ ...
│       ├── awareness/
│       │   └── 001/ ...
│       └── avoid/
│           └── 001/ ...
│
├── content/
│   ├── source/
│   │   └── content.en.json          ← YOU ONLY EVER EDIT THIS FILE
│   │
│   └── langs/
│       ├── content.af.json
│       ├── content.am.json
│       ├── content.ar.json
│       ├── content.bn.json
│       ├── content.de.json
│       ├── content.en.json
│       ├── content.es.json
│       ├── content.fa.json
│       ├── content.fr.json
│       ├── content.hi.json
│       ├── content.id.json
│       ├── content.it.json
│       ├── content.ja.json
│       ├── content.ko.json
│       ├── content.pa.json
│       ├── content.pt.json
│       ├── content.ru.json
│       ├── content.sw.json
│       ├── content.ta.json
│       ├── content.tl.json
│       ├── content.th.json
│       ├── content.tr.json
│       ├── content.ur.json
│       ├── content.vi.json
│       └── content.zh.json          ← all 25 langs, generated by jsontt
│
└── videos.json                      ← video ID registry, you edit this
```

**Naming rule:** Video folder name = ID used everywhere in the system.
Always numeric, zero-padded: `001`, `002`, `003` ... `099`, `100`.

**Guarantees per video folder:**
- `en.mp4` must always exist — it is the final fallback. No exceptions.
- `thumb.jpg` must always exist — it is not language-specific.

---

## 4. The Two Config Files

### videos.json — Video Registry (No Text, Just Structure)

```json
{
  "period": {
    "tips":      ["001", "002", "003", "004", "005", "006", "007"],
    "awareness": ["001", "002", "003", "004", "005"],
    "avoid":     ["001", "002", "003", "004", "005"]
  },
  "pregnancy": {
    "tips":      ["001", "002", "003", "004", "005", "006"],
    "awareness": ["001", "002", "003", "004"],
    "avoid":     ["001", "002", "003", "004"]
  }
}
```

**Rules:**
- Order in array has no special meaning (queue is shuffled per-user)
- Append new IDs to the end when adding a new video
- Server reads this to build the full catalog
- `catalog_version` is derived from this file's last-modified timestamp (see Section 17)
- Never remove an ID that users may have in their watched[] history — only append

---

### content/source/content.en.json — Master Text File

Flat key-value only. This is the file jsontt translates. Never edit translated files directly.

```json
{
  "period_tips_001_title": "Stay Hydrated",
  "period_tips_001_desc": "Drinking enough water reduces cramps and keeps your energy up during your period.",

  "period_tips_002_title": "Eat Iron Rich Foods",
  "period_tips_002_desc": "Your body loses iron during menstruation. Include spinach, lentils and nuts daily.",

  "period_tips_003_title": "Light Exercise Helps",
  "period_tips_003_desc": "Gentle walks or yoga can ease bloating and improve your mood during your cycle.",

  "period_awareness_001_title": "Track Your Cycle",
  "period_awareness_001_desc": "Knowing your cycle length helps you predict your next period accurately.",

  "period_awareness_002_title": "What Is PMS",
  "period_awareness_002_desc": "PMS symptoms appear 1–2 weeks before your period. Mood changes, bloating and fatigue are common.",

  "period_avoid_001_title": "Avoid Excess Caffeine",
  "period_avoid_001_desc": "Too much coffee or tea can worsen cramps and increase anxiety during your period.",

  "pregnancy_tips_001_title": "First Trimester Nutrition",
  "pregnancy_tips_001_desc": "Folic acid is critical in the first 12 weeks. Include leafy greens and fortified cereals.",

  "pregnancy_tips_002_title": "Stay Active Safely",
  "pregnancy_tips_002_desc": "Light walking for 30 minutes daily improves circulation and reduces pregnancy fatigue.",

  "pregnancy_awareness_001_title": "Understanding Trimesters",
  "pregnancy_awareness_001_desc": "Pregnancy has three trimesters of roughly 13 weeks each with different development milestones.",

  "pregnancy_avoid_001_title": "Foods to Avoid",
  "pregnancy_avoid_001_desc": "Raw fish, unpasteurised dairy and undercooked meat carry bacteria harmful to your baby."
}
```

**Key naming rule:** `{mode}_{category}_{id}_{field}`
Always lowercase, always underscores. jsontt translates values, never touches keys.

---

## 5. Language File System

### How jsontt Fits In

```
You edit:   content/source/content.en.json
Run:        jsontt --input content/source/content.en.json --langs hi,gu,mr,ta,te,...
Output:     content/langs/content.hi.json
            content/langs/content.gu.json
            content/langs/content.mr.json
            ... all 25 files generated automatically
```

### What a Generated content.hi.json Looks Like

```json
{
  "period_tips_001_title": "हाइड्रेटेड रहें",
  "period_tips_001_desc": "पर्याप्त पानी पीने से ऐंठन कम होती है और पीरियड के दौरान आपकी ऊर्जा बनी रहती है।",

  "period_tips_002_title": "आयरन युक्त खाद्य पदार्थ खाएं",
  "period_tips_002_desc": "मासिक धर्म के दौरान शरीर आयरन खोता है। रोज पालक, दाल और मेवे शामिल करें।",

  "period_awareness_001_title": "अपने चक्र को ट्रैक करें",
  "period_awareness_001_desc": "अपने चक्र की लंबाई जानने से आप अगले पीरियड का सटीक अनुमान लगा सकती हैं।"
}
```

Same keys. Translated values. Flat. Clean.

### Server Loads All 25 Files at Startup

```
Server boots
→ reads all content/langs/content.*.json into memory
→ stored as map: { "hi": {...all keys}, "gu": {...all keys}, ... }
→ never reads from disk again during runtime
→ total memory: under 1MB for all 25 files combined
```

### Video Language Fallback Chain

Not every video has all 25 language mp4 files. Server resolves this at catalog-build time:

```
User requests lang = "gu"
Video = period/tips/003/

Step 1: Check CDN/disk: videos/period/tips/003/gu.mp4 exists? → YES → use gu.mp4
Step 2: Does not exist → try hi.mp4 (regional Hindi fallback)
Step 3: Does not exist → use en.mp4 (guaranteed always exists)

Result: video_url in catalog is always a valid, playable URL.
Flutter never receives a broken link.
```

**Fallback chain for text (title / desc):**
```
content_map["gu"][key] exists? → use it
content_map["en"][key] exists? → use it (fallback)
```

---

## 6. API Endpoint — Catalog Mode

```
GET /api/catalog
```

### Query Parameters

| Parameter | Type | Required | Values | Example |
|---|---|---|---|---|
| mode | string | yes | `period` or `pregnancy` | `mode=period` |
| lang | string | yes | any of 25 lang codes | `lang=hi` |

**Note: No `date` parameter.** This is not a date-rotation system anymore. The catalog is the same for everyone. Date is only relevant on the device (for display), never sent to the server.

### Full Request

```
GET https://yourserver.com/api/catalog?mode=period&lang=hi
```

No headers. No auth token. No user ID. No date.

### When Flutter Calls This

Flutter calls `/api/catalog` only when:
1. First launch (no catalog stored locally)
2. `catalog_version` on server is newer than stored `catalog_version`
3. User changes language (old catalog is language-specific, must re-fetch)

All other app opens → zero API calls. Flutter uses stored catalog.

---

## 7. Response Body — Full Catalog

```json
{
  "mode": "period",
  "lang": "hi",
  "lang_resolved": "hi",
  "catalog_version": "2025-04-27-v3",
  "categories": {
    "tips": {
      "total": 7,
      "videos": [
        {
          "id": "001",
          "full_id": "period/tips/001",
          "title": "हाइड्रेटेड रहें",
          "description": "पर्याप्त पानी पीने से ऐंठन कम होती है और पीरियड के दौरान आपकी ऊर्जा बनी रहती है।",
          "duration_sec": 54,
          "video_url": "https://cdn.yourapp.com/videos/period/tips/001/hi.mp4",
          "thumbnail_url": "https://cdn.yourapp.com/videos/period/tips/001/thumb.jpg",
          "video_lang_resolved": "hi"
        },
        {
          "id": "002",
          "full_id": "period/tips/002",
          "title": "आयरन युक्त खाद्य पदार्थ खाएं",
          "description": "मासिक धर्म के दौरान शरीर आयरन खोता है। रोज पालक, दाल और मेवे शामिल करें।",
          "duration_sec": 58,
          "video_url": "https://cdn.yourapp.com/videos/period/tips/002/hi.mp4",
          "thumbnail_url": "https://cdn.yourapp.com/videos/period/tips/002/thumb.jpg",
          "video_lang_resolved": "hi"
        },
        {
          "id": "003",
          "full_id": "period/tips/003",
          "title": "हल्का व्यायाम मदद करता है",
          "description": "हल्की सैर या योग आपके चक्र के दौरान सूजन को कम कर सकते हैं।",
          "duration_sec": 71,
          "video_url": "https://cdn.yourapp.com/videos/period/tips/003/en.mp4",
          "thumbnail_url": "https://cdn.yourapp.com/videos/period/tips/003/thumb.jpg",
          "video_lang_resolved": "en"
        }
      ]
    },
    "awareness": {
      "total": 5,
      "videos": [ ... ]
    },
    "avoid": {
      "total": 5,
      "videos": [ ... ]
    }
  }
}
```

### Field Explanations

| Field | What It Is |
|---|---|
| `mode` | Echo of requested mode |
| `lang` | Requested language code |
| `lang_resolved` | Actual language used for text (may differ if fallback activated) |
| `catalog_version` | String Flutter stores and compares next time. Change this when videos.json changes. |
| `categories.{cat}.total` | Total count of videos in this category. Flutter uses this to detect new additions. |
| `id` | Short ID — used in local_state queues (e.g. `"001"`) |
| `full_id` | Full path-based ID — for human-readable logging only |
| `title` | Already translated server-side — Flutter displays directly |
| `description` | Already translated server-side — Flutter displays directly |
| `duration_sec` | Integer seconds — for displaying duration badge on card |
| `video_url` | Final, fully-resolved CDN URL — Flutter plays this directly |
| `thumbnail_url` | Final CDN URL — Flutter loads for card thumbnail |
| `video_lang_resolved` | Which language the actual video file is in — Flutter can show UI indicator if needed |

---

## 8. Language Resolution Logic

### Text Resolution (Server, at Catalog Build Time)

```
requested_lang = "gu"
key = "period_tips_001_title"

content_map["gu"][key] → exists? → use it    (lang_resolved = "gu")
content_map["en"][key] → fallback if not     (lang_resolved = "en")
```

Text resolution happens once at catalog build time. Flutter never handles translation keys or language fallback. It receives final display-ready strings.

### Video URL Resolution (Server, at Catalog Build Time)

```
requested_lang = "gu"
video_path = videos/period/tips/003/

Check: {cdn_base}/videos/period/tips/003/gu.mp4 → exists? → use it (video_lang_resolved = "gu")
       {cdn_base}/videos/period/tips/003/hi.mp4 → fallback 1  (video_lang_resolved = "hi")
       {cdn_base}/videos/period/tips/003/en.mp4 → fallback 2  (video_lang_resolved = "en")
```

The `video_lang_resolved` field in the response tells Flutter which language the video is actually in. Flutter can optionally show a small indicator ("Playing in Hindi") if the user's language is Gujarati but hi.mp4 was served.

### Flutter Receives

A fully resolved catalog. Zero language logic in Flutter. Zero broken links. Zero guessing.

---

## 9. Server Caching Strategy

### Cache Key

```
"{mode}:{lang}:{catalog_version}"

Examples:
  "period:hi:2025-04-27-v3"
  "pregnancy:gu:2025-04-27-v3"
  "period:en:2025-04-27-v3"
```

### Cache Lifecycle

```
Request arrives
    ↓
Cache key exists in memory?
    ├── YES → return cached catalog instantly (0 computation)
    └── NO  → build full catalog
                → resolve all URLs
                → resolve all text
                → store in memory cache
                → return catalog

When videos.json changes (new video added)
    → catalog_version string changes
    → new cache key → cache miss → full rebuild for that combo
    → old keys expire naturally (no cleanup needed)
```

### Maximum Cache Entries

```
2 modes × 25 languages = 50 unique entries
(only cached on demand — unused lang combos never built)
```

Server does at most 50 catalog builds ever (one per unique mode+lang combo), regardless of user count. After the first request for any combo, every subsequent request gets instant cached response.

### Startup Cache (Optional Optimization)

On server boot, pre-generate the most common combos (e.g., hi, gu, mr, en for both modes). First user always gets instant response.

---

## 10. Local State — Full Schema

This is the complete data structure stored on the user's device (in Isar-community).

```json
{
  "install_id": "a3f7b2c1-9e4d-4a8b-b3c2-1d5e6f7a8b9c",

  "period": {
    "tips": {
      "unwatched_queue": ["004", "007", "002", "005", "001", "006", "003"],
      "watched": ["003", "006"],
      "cycle": 1,
      "known_total": 7
    },
    "awareness": {
      "unwatched_queue": ["002", "005", "001", "003", "004"],
      "watched": [],
      "cycle": 1,
      "known_total": 5
    },
    "avoid": {
      "unwatched_queue": ["003", "001", "002", "004", "005"],
      "watched": [],
      "cycle": 1,
      "known_total": 5
    }
  },

  "pregnancy": {
    "tips": {
      "unwatched_queue": ["003", "006", "001", "004", "002", "005"],
      "watched": [],
      "cycle": 1,
      "known_total": 6
    },
    "awareness": {
      "unwatched_queue": ["002", "004", "001", "003"],
      "watched": [],
      "cycle": 1,
      "known_total": 4
    },
    "avoid": {
      "unwatched_queue": ["001", "003", "002", "004"],
      "watched": [],
      "cycle": 1,
      "known_total": 4
    }
  },

  "catalog_version_period": "2025-04-27-v3",
  "catalog_version_pregnancy": "2025-04-27-v2",

  "lang": "hi"
}
```

### Field Explanations

| Field | What It Is |
|---|---|
| `install_id` | UUID v4, generated once on first install, never changes, never sent to server |
| `{mode}.{cat}.unwatched_queue` | Shuffled list of IDs not yet watched in this cycle. Consumed from the front. |
| `{mode}.{cat}.watched` | IDs watched in this cycle. Moved here after 70% completion threshold. |
| `{mode}.{cat}.cycle` | Increments each time the category resets. Used as seed variation for reshuffle. |
| `{mode}.{cat}.known_total` | Last known total count for this category. Used to detect new videos added. |
| `catalog_version_period` | Last stored catalog_version for period mode. Compare on next fetch. |
| `catalog_version_pregnancy` | Last stored catalog_version for pregnancy mode. |
| `lang` | Currently active language. If this changes, re-fetch catalogs. |

---

## 11. Install ID Generation

```dart
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> getOrCreateInstallId() async {
  final prefs = await SharedPreferences.getInstance();
  String? id = prefs.getString('install_id');
  if (id == null) {
    id = const Uuid().v4();
    await prefs.setString('install_id', id);
  }
  return id;
}
```

**Rules:**
- Generated exactly once on first app launch
- Stored permanently in SharedPreferences — survives app restarts
- Lost only on full app uninstall (watch history also resets — acceptable for v1)
- Never sent to the server — purely for local seeding purposes
- Not a user account. Not a tracking ID. Pure local device identity for deterministic shuffling.

---

## 12. Seeded Shuffle Algorithm

The shuffle is deterministic: same install_id + same cycle = same order. Different devices = different order. This prevents the appearance of "random chaos" while still giving each user a unique sequence.

```dart
import 'dart:math';

List<String> generateShuffledQueue({
  required List<String> videoIds,
  required String installId,
  required int cycle,
}) {
  // Combine installId hash and cycle number as seed
  final seed = installId.hashCode ^ cycle.hashCode;
  final rng = Random(seed);
  final shuffled = List<String>.from(videoIds);
  
  // Fisher-Yates shuffle
  for (int i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final temp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = temp;
  }
  
  return shuffled;
}
```

**Usage:**
```dart
// First time initializing a category
final queue = generateShuffledQueue(
  videoIds: ["001", "002", "003", "004", "005", "006", "007"],
  installId: installId,
  cycle: 1,
);
// → e.g. ["004", "007", "002", "005", "001", "006", "003"]

// After full reset (cycle increments)
final freshQueue = generateShuffledQueue(
  videoIds: allIds,
  installId: installId,
  cycle: 2,           // different cycle = different order
);
// → e.g. ["002", "005", "003", "007", "001", "004", "006"]
```

**Why this matters:** Cycle 2 never starts with the same video as cycle 1. The second cycle feels fresh even though it's the same library. Users do not experience obvious repetition pattern.

---

## 13. Watch Progress Threshold

A video is considered "watched" at 70% completion. This is the standard streaming industry threshold.

```dart
VideoPlayerController controller; // from video_player package

controller.addListener(() {
  final position = controller.value.position.inSeconds;
  final duration = controller.value.duration.inSeconds;
  
  if (duration > 0 && !alreadyMarkedWatched) {
    final progress = position / duration;
    if (progress >= 0.70) {
      alreadyMarkedWatched = true;
      markVideoWatched(videoId);
    }
  }
});
```

### markVideoWatched()

```dart
void markVideoWatched(String videoId, String mode, String category) {
  final state = localState[mode][category];
  
  // Already in watched? Do nothing (safety check for re-entry)
  if (state.watched.contains(videoId)) return;
  
  // Move from queue to watched
  state.unwatchedQueue.remove(videoId);
  state.watched.add(videoId);
  
  // Save to persistent storage
  saveLocalState();
  
  // Check if category needs reset
  if (state.unwatchedQueue.isEmpty) {
    resetCategory(mode, category);
  }
}
```

**Rules:**
- Below 70% = not watched. Video stays at front of queue. User sees it again next open.
- At or above 70% = watched. Move to watched[]. Never show again this cycle.
- `alreadyMarkedWatched` flag per session prevents duplicate triggers from listener.
- If user closes app mid-video below 70%, video is NOT marked watched. It reappears next open. This is correct behaviour.

---

## 14. Flutter App — Complete Flow

### First Install

```
App launches for first time
    ↓
Generate installId → store permanently
Initialize empty local_state structure
    ↓
Determine user's mode (period or pregnancy) — from onboarding
Determine user's language — from device locale or onboarding selection
    ↓
Call GET /api/catalog?mode=period&lang=hi
Store full catalog JSON locally
Store catalog_version from response
    ↓
For each category (tips, awareness, avoid):
    Extract all video IDs from catalog
    Generate shuffled queue using installId + cycle=1
    Store queue in local_state
    known_total = catalog.categories.{cat}.total
    ↓
Display feed: show first 2 IDs from each queue
(user has not watched anything yet, all are unwatched)
```

### Every Subsequent App Open

```
App opens
    ↓
Load local_state from Isar-community
Load stored catalog from Isar-community
    ↓
Check: stored catalog_version == server's catalog_version?
    │
    │  To check catalog_version WITHOUT fetching full catalog:
    │  GET /api/catalog_version?mode=period
    │  Returns: { "catalog_version": "2025-04-27-v3" }
    │  (lightweight endpoint, just the version string)
    │
    ├── SAME → use stored catalog, zero additional network call
    └── CHANGED → fetch full catalog, update stored catalog,
                  sync new videos into queue (see Section 17),
                  update stored catalog_version
    ↓
For each category:
    today_videos = first 2 from unwatched_queue
    (these are the same 2 as yesterday until user watches them)
    ↓
Render feed
```

### Lightweight Version-Check Endpoint

```
GET /api/catalog_version?mode=period

Response:
{
  "mode": "period",
  "catalog_version": "2025-04-27-v3"
}
```

This is a tiny call Flutter makes on every app open to check if a full catalog re-fetch is needed. The full catalog is only fetched when version has changed.

### Rendering the Feed

```
Response / stored catalog available
    ↓
Default tab = Tips
    ↓
Render horizontal strip: 2 video cards
    card 1 = unwatched_queue[0]    (first unwatched)
    card 2 = unwatched_queue[1]    (second unwatched)
    (see Section 19 for edge cases when queue has 0 or 1 items)
    ↓
User taps category pill (Awareness / Avoid)
    → NO API call
    → swap category's videos from already-loaded catalog + queue
    → instant render
    ↓
User taps video card
    → Open fullscreen player
    → Stream video_url directly from CDN
    → Show title + description + duration from catalog
    → Track progress → at 70% → markVideoWatched()
```

### Video Pre-Initialization

```
When Tips strip renders:
    → Pre-initialize video controller for queue[0] of Tips (slot 1 only)
    → Silent, background, buffer starts loading
    → User taps → player opens → starts near-instantly

Do NOT pre-initialize:
    → queue[1] of Tips
    → Any Awareness or Avoid videos
    → Reason: unnecessary data usage, wasted memory
```

---

## 15. Mode Handling

Two modes (`period` and `pregnancy`) are completely independent. They never interfere.

### Local Storage Layout

```
Isar-community boxes:

  catalog_period_hi         → full catalog JSON for period mode, Hindi
  catalog_period_gu         → full catalog JSON for period mode, Gujarati
  catalog_pregnancy_hi      → full catalog JSON for pregnancy mode, Hindi
  local_state               → single JSON object containing both modes' state
  install_id                → UUID string, never changes
```

### Switching Modes

```
User was on period mode
User taps "Switch to Pregnancy Mode"
    ↓
Do NOT clear period local_state
Do NOT clear period catalog
    ↓
Load pregnancy local_state (already exists or initialize fresh)
    ↓
Pregnancy catalog stored locally?
    ├── YES (same catalog_version) → use it, zero API call, instant
    └── NO → fetch GET /api/catalog?mode=pregnancy&lang=hi
              store catalog locally
              initialize pregnancy queues from catalog
    ↓
Render pregnancy feed

User switches back to period mode
    ↓
Period state exactly where they left it
Period catalog still stored
Instant render, zero API call
```

**Both modes live side by side on device simultaneously.**
Switching modes is instant after each mode's first catalog fetch.

---

## 16. Language Change Handling

### On Language Switch

```
User was on Hindi
User switches settings to Gujarati
    ↓
Update lang in local_state → save
    ↓
Delete stored catalog for period mode (Hindi version is now stale)
Delete stored catalog for pregnancy mode (Hindi version is now stale)
    ↓
Immediately fetch:
    GET /api/catalog?mode={current_mode}&lang=gu
    Store as catalog_{current_mode}_gu
    ↓
Pregnancy catalog (other mode) → fetch lazily:
    Only when user visits pregnancy mode tab for first time in new language
    ↓
Watch history (local_state queues + watched[]) → PRESERVED
    Reason: watched[] tracks IDs like "001", "002" — language-agnostic
    The content changes (Gujarati text now), but progress does not reset
```

### Why Preserve Watch History on Language Change

The `watched[]` and `unwatched_queue[]` arrays store video IDs (`"001"`, `"002"`, etc.) — they have nothing to do with language. Language only affects which catalog JSON is loaded for titles, descriptions, and video URLs. The user's progress through the video library is independent of language. A video watched in Hindi is still watched in Gujarati — they saw it already.

**Exception: Video URLs may change on language switch.** A user who watched a video in Hindi (hi.mp4) might now get gu.mp4 for the same ID if it exists. The video is already in `watched[]` so it won't appear in their queue again regardless.

---

## 17. New Video Sync — catalog_version System

### How catalog_version Works

`catalog_version` is a string generated from `videos.json` last-modified timestamp + a manual version suffix.

```
Format: "YYYY-MM-DD-vN"
Example: "2025-04-27-v1"
         "2025-04-27-v2"   (if videos.json changed twice same day)
         "2025-04-28-v1"   (new day, new video added)
```

You manually increment the `-vN` suffix (or just let date change) when you edit `videos.json`.

### Sync Flow When New Video Detected

```
App opens
    ↓
GET /api/catalog_version?mode=period
Response: { "catalog_version": "2025-04-28-v1" }
Stored version: "2025-04-27-v3"
    → MISMATCH → fetch full catalog
    ↓
GET /api/catalog?mode=period&lang=hi
    ↓
New catalog has 8 tips videos (was 7)
New video ID: "008"
    ↓
Sync algorithm runs:

For each category:
    newIds = catalog.categories[cat].videos.map(v => v.id)
    alreadyKnown = unwatchedQueue + watched[]

    for each id in newIds:
        if id NOT in alreadyKnown:
            → append to END of unwatchedQueue
            → update known_total

local_state after sync:
    unwatched_queue: ["004", "007", "002", "005", "001", "006", "003", "008"]
                                                                      ↑ new
    watched: []
    known_total: 8 (was 7)
```

**Result:** New video is immediately in queue. User sees it next time their queue reaches that position. No disruption to current playback sequence.

### Important: Never Remove IDs from videos.json

If a video ID is in a user's `watched[]` array and you remove it from `videos.json`, the sync will try to add it back to the queue (it's not in the catalog but is in watched[]). To handle retired videos gracefully, keep them in `videos.json` but remove their files from CDN and mark them with `"active": false` in the response. Flutter skips `"active": false` videos when building display list.

```json
{
  "id": "004",
  "full_id": "period/tips/004",
  "active": false
}
```

If `active` field is absent, treat as `true`. This is backward compatible.

---

## 18. Category Reset Rules

### Reset Trigger

When `unwatched_queue` for a category reaches 0 (all videos watched), that category resets.

```dart
void resetCategory(String mode, String category) {
  final state = localState[mode][category];
  final allIds = catalog[mode][category].map((v) => v.id).toList();
  
  // Increment cycle → different shuffle seed next round
  state.cycle += 1;
  
  // Move all watched back to a fresh shuffled queue
  state.unwatchedQueue = generateShuffledQueue(
    videoIds: allIds,
    installId: installId,
    cycle: state.cycle,
  );
  state.watched = [];
  
  saveLocalState();
}
```

### Per-Category Reset (Not Per-Mode)

Each category resets independently. Tips can reset while Awareness is halfway through. This is intentional and correct — categories are independent content lanes. A user who binge-watches Tips gets a fresh Tips cycle without waiting for Awareness to finish.

### Reset Does NOT Mean Same Order

The new cycle uses `cycle: 2` as seed variation → different shuffle result → second cycle feels fresh. The user does not see `"001"` first just because it was first in some original list.

### Reset Boundary Guarantee

After a reset, the first video shown will never be the same as the last video shown in the previous cycle. This is statistically guaranteed by the seeded shuffle because the seed changes (cycle increments), making a different video land at position 0.

> ⚠️ **Note:** This guarantee is probabilistic, not absolute. In rare cases with very small libraries (3 or fewer videos), the new shuffle might start with the same video as the old cycle ended. Mitigation: maintain at least 5 videos per category bucket.

---

## 19. Video Selection Algorithm (Per-Open Stability)

### The Selection Rule

```
today_slot_1 = unwatched_queue[0]    // first unwatched
today_slot_2 = unwatched_queue[1]    // second unwatched (if exists)
```

These are the same two videos every time the user opens the app — until they watch one.

Watching `today_slot_1` (past 70%) → it moves to `watched[]` → queue shifts → `today_slot_1` is now what was `today_slot_2`. `today_slot_2` is now `unwatched_queue[1]` (the next unseen).

### Edge Cases for Selection

| Situation | What to Show |
|---|---|
| unwatched_queue.length ≥ 2 | Show queue[0] and queue[1] — normal case |
| unwatched_queue.length == 1 | Show queue[0] (only unwatched) + queue[1] from `watched[]` (oldest watched, as "rewatch") — mark it with a "Rewatch" badge |
| unwatched_queue.length == 0 | Category reset just triggered. Show new queue[0] and queue[1]. |
| category has only 1 video total | Always show that 1 video. Never show 2 cards. Hide slot 2 entirely. |

### Rewatch Badge Logic

```dart
Widget buildVideoCard(String videoId, bool isRewatch) {
  return VideoCard(
    video: catalogLookup(videoId),
    badge: isRewatch ? "Rewatch" : null,
  );
}
```

User tapping a "Rewatch" card opens the player normally. Progress tracking still runs. If they watch past 70% again — no action (it's already in watched[]). This is a no-op duplicate guard inside `markVideoWatched()`.

---

## 20. Flutter Packages

| Package | Version (as of writing) | Purpose |
|---|---|---|
| `video_player` | ^2.8.x | Core video streaming from URL |
| `chewie` | ^1.7.x | Player UI (controls, fullscreen, progress bar) — saves build time |
| `cached_network_image` | ^3.3.x | Thumbnail image caching for smooth scroll |
| `isar-community` + `isar-flutter-libs` | ^3.x | ✅ **Primary database**
| `uuid` | ^4.x | Generating installId (UUID v4) |
| `connectivity_plus` | ^5.x | Detecting online/offline state for graceful offline handling |
| `http` | ^1.2.x | Simple HTTP client for catalog API calls |

**Recommended storage strategy:**
- Use `isar` for catalog JSON (potentially large, needs fast read)
- Use `shared_preferences` for local_state (simpler schema, smaller size)
- Use `shared_preferences` for installId and catalog_version strings

---

## 21. Adding a New Video — Full Workflow

### Step-by-Step

```
1. Record video in English
   Export as 1080×1920 (vertical 9:16), under 90 seconds
   Recommended: under 60 seconds for best completion rates

2. Dub in priority languages
   Mandatory: en.mp4
   High priority: hi.mp4, gu.mp4, mr.mp4, ta.mp4, te.mp4
   Export each as {lang}.mp4

3. Generate thumbnail
   Screenshot at 2–3 second mark (after intro movement settles)
   Save as thumb.jpg
   Recommended: compress to under 100KB

4. Create folder on CDN / server
   videos/period/tips/008/
   Upload: en.mp4, hi.mp4, (other langs), thumb.jpg
   Verify CDN URLs resolve correctly before next step

5. Add video ID to videos.json
   "period" → "tips" → append "008" to end of array
   Increment catalog_version suffix (e.g., v3 → v4) or let date change handle it
   Save videos.json and deploy to server

6. Add text to content/source/content.en.json
   Add exactly two lines:
   "period_tips_008_title": "Your English Title Here",
   "period_tips_008_desc": "Your English description, one to two clear sentences."

7. Run jsontt to translate
   jsontt --input content/source/content.en.json --langs hi,gu,mr,ta,te,bn,kn,ml,pa,ur,or,as,ar,fr,es,de,pt,ru,zh,ja,ko,id,tr,sw
   All 25 content.{lang}.json files updated automatically

8. Deploy updated content/langs/ directory to server
   Server reloads language files (restart or hot-reload endpoint)

9. Verify
   Hit GET /api/catalog?mode=period&lang=hi in browser/Postman
   Confirm "008" appears in tips.videos[] with correct title, description, and URL

10. Done
    Next time any user opens their app:
    → catalog_version check detects change
    → full catalog re-fetched
    → "008" added to end of each user's unwatched_queue
    → Video enters rotation automatically
    → No app update required
    → No code change required
```

---

## 22. Edge Cases — Every One Handled

| Scenario | What Happens | Solution |
|---|---|---|
| Language mp4 doesn't exist for requested lang | Server falls back: gu → hi → en. Flutter receives valid URL always. | Fallback chain in Section 5 |
| Category has only 1 video | Queue cycles that 1 video forever. Show only 1 card. | Selection algorithm handles 1-video case (Section 19) |
| Category queue at 1 remaining | Show 1 unwatched + 1 rewatch card from watched[] | Rewatch badge logic (Section 19) |
| Category queue at 0 (all watched) | Trigger reset, increment cycle, generate new shuffled queue | resetCategory() in Section 18 |
| User changes language mid-day | Delete old catalog. Re-fetch new language catalog. Watch history preserved. | Section 16 |
| User switches mode | Both mode states coexist. Switching is instant after first fetch per mode. | Section 15 |
| New video added to library | catalog_version changes. Sync on next app open. New ID appended to queue end. | Section 17 |
| Internet offline on app open | Use stored catalog + local_state. Show feed from cache. Videos play when internet returns. | Section 23 |
| Internet offline first launch | Show empty state / onboarding screen. Cannot initialize without catalog. | Section 23 |
| App reinstall (uninstall + reinstall) | installId regenerated. local_state cleared. Starts fresh from cycle 1. Expected behaviour for v1. | Documented known limitation |
| Server restart | In-memory catalog cache cleared. First request rebuilds it. No data loss (no DB). | Stateless server design |
| videos.json has typo or missing ID | Server logs warning, skips that ID, returns remaining valid videos. App still works. | Server validation at startup |
| content key missing in translated file | Server falls back to English value for that key. Never crashes. | Text resolution fallback (Section 8) |
| catalog_version check fails (network) | Use stored catalog. Same as offline. | Section 23 |
| Two queue slots are same ID | Cannot happen — queue contains each ID once, shuffled without replacement. Fisher-Yates guarantees uniqueness. | Algorithm design |
| User watches < 70% and closes app | Not marked watched. Reappears at front of queue next open. Correct. | 70% threshold (Section 13) |
| User watches same video twice (rewatch slot) | Second 70% trigger hits duplicate guard in markVideoWatched(). No-op. State unchanged. | Duplicate guard in Section 14 |
| Very small library (< 5 videos per category) | Rotation still works. Reset cycle more frequently. First video of new cycle may rarely match last of old. | Document minimum recommended: 5 videos per bucket |
| `active: false` video in catalog | Flutter skips it in display. ID stays in watched[] if previously seen. Never shown again until manually re-activated. | active flag (Section 17) |
| User in different timezone | Device locale used everywhere. Server never sees a date. No timezone conflict. | No date param in API |
| Content update mid-session | catalog_version check only on app open. Mid-session, always uses stored catalog. No disruption. | By design |
| catalog JSON gets corrupted in storage | Catch parse error, delete stored catalog, re-fetch on next open. | Error handling in fetch/load |

---

## 23. Offline Behaviour

### Scenario A — Online on First Launch (Normal)

```
App opens → online
Fetch catalog → store locally
Generate queues → store local_state
Render feed
User watches videos → marks watched → saves local_state
App closes
```

### Scenario B — Offline After First Launch (Normal Case)

```
App opens → offline (or connectivity_plus detects no internet)
    ↓
Load stored catalog from Isar-community → success
Load stored local_state → success
    ↓
Render feed using stored data
    ↓
User taps video card
    → video_player tries to stream CDN URL
    → CDN unreachable → show buffering spinner → timeout → show error
    → "No internet connection. Please connect to watch videos."
    → Thumbnail and text still visible. Only playback fails.
    ↓
User reconnects internet
    → Tap video again → plays immediately
    ↓
App background check on reconnect (optional):
    → connectivity_plus stream fires connected event
    → Run catalog_version check
    → If changed → fetch new catalog silently
```

### Scenario C — Offline on First Launch (Edge Case)

```
App opens for first time → offline
No stored catalog, no stored local_state
    ↓
Show onboarding / language selection screen normally
When reaching feed screen:
    → Show offline state UI
    → "Connect to internet to load your content"
    → Retry button
    ↓
User connects → tap Retry → fetch catalog → normal flow continues
```

### Scenario D — Catalog Fetch Fails Mid-Session

```
App opens → online → catalog_version check says changed
→ Try full catalog fetch → fails (timeout / server error)
    ↓
Use stored catalog (old version)
Continue with existing local_state
    ↓
Retry catalog fetch on next app open
```

---

## 24. Scale Reality Check

### What This Architecture Handles

| Metric | Value |
|---|---|
| API computations ever (catalog builds) | 50 max (2 modes × 25 langs, then cached forever until catalog_version changes) |
| API calls per user per day | 1 (version check) + 0 or 1 (full catalog if version changed) |
| Version check response size | ~100 bytes |
| Full catalog response size | ~15–30KB JSON (compressed) |
| Server memory for all lang files | Under 1MB |
| Video bandwidth per user | Served by CDN, not your server |
| Users supported on tiny server | Effectively unlimited for API layer |
| DB queries per request | Zero (no database) |
| Files you manage | 2 config files + video folders on CDN |
| Personalization per user | Full, unique queue per device, zero server involvement |

### What This Architecture Does NOT Handle

| Feature | Why Not Now | When to Add |
|---|---|---|
| Cross-device watch history sync | Requires user accounts | When you add auth/login |
| Per-user analytics (who watched what) | No user identity on server | When you add auth |
| Video bookmarks / saves | Requires persistent user identity | When you add auth |
| Admin panel for video management | Manual JSON editing sufficient for small library | When library > 100 videos |
| A/B testing different content | No user segments right now | When you add analytics |
| Push notifications for new videos | No user identity to push to | When you add auth |
| Watch history backup on reinstall | No server-side storage | When you add auth |

All of these are addable later without changing the current architecture foundation.

---

## 25. What This Does NOT Handle (v2 Roadmap)

### v2 — After Adding User Accounts

When you add authentication (Google/Apple sign-in), the following become possible:

```
local_state → migrated to server (Firestore / PostgreSQL)
install_id  → replaced with user_id
watched[]   → syncs across devices
New device  → logs in → downloads watch history → continues from where left off
```

The catalog endpoint stays unchanged. Only the state management layer changes from local to cloud. The server catalog API needs zero modification.

### v2 Addons

```
GET /api/user/state?mode=period         → fetch watch state from server
POST /api/user/state/watched            → sync a watched event
GET /api/user/bookmarks                 → fetch saved videos
POST /api/user/bookmarks                → save a video
```

These are additive. They do not break the current architecture.

---

## 26. Final Summary

```
You manage:       content.en.json + videos.json + video files on CDN
jsontt handles:   25 language translations automatically
Server does:      catalog build + lang resolution + URL resolution + cache → returns full JSON
CDN does:         all video streaming (server never touches video bytes)
Flutter does:     version check on open → catalog fetch if needed → queue management →
                  render → track progress → mark watched → reset cycle
Users get:        unique personal video queue, no repeats until all watched,
                  matched to their language, works offline, instant app opens
```

### Architecture Contract

| Layer | Responsibility | Does NOT Do |
|---|---|---|
| Server | Serve full translated catalog with resolved URLs | Date math, user state, rotation decisions |
| Flutter | Queue management, watch tracking, selection logic | Any translation, any language fallback |
| CDN | Video delivery | Anything else |
| Device storage | Local state + catalog cache | Server communication |

### Key Invariants (Never Violate These)

1. `en.mp4` must always exist for every video folder — it is the final URL fallback guarantee
2. `thumb.jpg` must always exist for every video folder — thumbnails are not language-specific
3. `install_id` is never sent to the server — it is a local device seed only
4. `catalog_version` must change every time `videos.json` changes — this is what triggers client sync
5. Video IDs in `videos.json` are never deleted — only append new ones
6. `watched[]` checks always run before adding to queue on sync — prevents duplicates
7. The `markVideoWatched()` function always checks for existing entry before acting — prevents double-marking

> No database. No auth. No user tracking. No CMS required.
> Add a video in 15 minutes. Goes live on next app open. Works in 25 languages.
> Every user gets a unique, personalized, non-repeating queue — with zero server-side state.
