# Virtual Help — HLS Re-Architecture (v2)
> One Video Stream · 25 Audio Tracks · No Duplication · Netflix-Grade Delivery

---

## What Changed vs v1 (and Why)

| Dimension | v1 (Separate MP4 per lang) | v2 (HLS + Alternate Audio) |
|---|---|---|
| Storage per video | 70MB × 25 = 1,750MB | ~65MB video + 25 × ~3MB audio = ~140MB |
| 80 videos total | ~140 GB | ~11 GB |
| Video duplication | 25 identical visual copies | 1 visual copy, ever |
| Playback start | Download full file | Streaming from first segment (~6s chunk) |
| Language switch | Re-fetch different MP4 | Switch audio track, video keeps playing |
| CDN bandwidth | Full file on every play | Only segments actually watched stream |
| Flutter code change | Major | Minimal — `video_player` already handles HLS |
| New language addition | Re-encode full video per lang | Add one `.m4a` audio file + regenerate playlist |

---

## 1. Revised Folder Structure (CDN / Server)

```
/videos/
│
├── period/
│   ├── tips/
│   │   ├── 001/
│   │   │   ├── master.m3u8              ← HLS master playlist (entry point)
│   │   │   │
│   │   │   ├── video/
│   │   │   │   ├── stream.m3u8          ← video-only segment playlist
│   │   │   │   ├── seg_000.ts           ← 6-second video chunk
│   │   │   │   ├── seg_001.ts
│   │   │   │   ├── seg_002.ts
│   │   │   │   └── seg_00N.ts
│   │   │   │
│   │   │   ├── audio/
│   │   │   │   ├── en/
│   │   │   │   │   ├── stream.m3u8      ← audio-only segment playlist (English)
│   │   │   │   │   ├── seg_000.aac
│   │   │   │   │   ├── seg_001.aac
│   │   │   │   │   └── seg_00N.aac
│   │   │   │   ├── hi/
│   │   │   │   │   ├── stream.m3u8
│   │   │   │   │   └── seg_00N.aac
│   │   │   │   ├── gu/
│   │   │   │   ├── mr/
│   │   │   │   ├── ta/
│   │   │   │   ├── te/
│   │   │   │   └── ... (all 25 langs)
│   │   │   │
│   │   │   └── thumb.jpg                ← unchanged from v1
│   │   │
│   │   ├── 002/
│   │   └── 003/ ...
│   │
│   ├── awareness/
│   └── avoid/
│
└── pregnancy/
    ├── tips/
    ├── awareness/
    └── avoid/
```

### Key Rules

- `master.m3u8` is the only URL your Flutter app ever needs per video.
- `video/` folder: 1 copy of visual, no audio, always present.
- `audio/en/` always present — final fallback guarantee (same as v1).
- Audio langs are added independently — adding Punjabi later means adding `audio/pa/` only. No video re-encoding.
- `thumb.jpg` — unchanged, exactly as v1.

---

## 2. The HLS Files Explained

### master.m3u8 — What It Looks Like

```m3u8
#EXTM3U
#EXT-X-VERSION:6

# ── Audio tracks ─────────────────────────────────────────────────────
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="English",\
  DEFAULT=NO,AUTOSELECT=YES,URI="audio/en/stream.m3u8"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="hi",NAME="Hindi",\
  DEFAULT=YES,AUTOSELECT=YES,URI="audio/hi/stream.m3u8"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="gu",NAME="Gujarati",\
  DEFAULT=NO,AUTOSELECT=YES,URI="audio/gu/stream.m3u8"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="mr",NAME="Marathi",\
  DEFAULT=NO,AUTOSELECT=YES,URI="audio/mr/stream.m3u8"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="ta",NAME="Tamil",\
  DEFAULT=NO,AUTOSELECT=YES,URI="audio/ta/stream.m3u8"

# ... all 25 language entries ...

# ── Video stream (references audio group) ────────────────────────────
#EXT-X-STREAM-INF:BANDWIDTH=1200000,CODECS="avc1.64001f,mp4a.40.2",\
  AUDIO="audio",RESOLUTION=1080x1920
video/stream.m3u8
```

**`DEFAULT=YES` is set to the language the user has selected.**
This is not hardcoded — your server generates `master.m3u8` dynamically per language request (or you generate one per language variant). See Section 4 for how this works.

### video/stream.m3u8 — Video Segment Playlist

```m3u8
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD

#EXTINF:6.000,
seg_000.ts
#EXTINF:6.000,
seg_001.ts
#EXTINF:6.000,
seg_002.ts
#EXTINF:4.217,
seg_003.ts

#EXT-X-ENDLIST
```

### audio/hi/stream.m3u8 — Audio Segment Playlist

```m3u8
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD

#EXTINF:6.000,
seg_000.aac
#EXTINF:6.000,
seg_001.aac
#EXTINF:6.000,
seg_002.aac
#EXTINF:4.217,
seg_003.aac

#EXT-X-ENDLIST
```

Segments are time-aligned. Video `seg_000.ts` (0–6s) plays perfectly in sync with audio `seg_000.aac` (0–6s).

---

## 3. FFmpeg — Complete Processing Script

Run this ONCE per video after SoniTranslate gives you your dubbed files.

### Input (what SoniTranslate gives you)

```
raw/period/tips/001/
  en.mp4    ← original English (video + audio)
  hi.mp4    ← dubbed Hindi (video + dubbed audio)
  gu.mp4    ← dubbed Gujarati (video + dubbed audio)
  ...
```

### `process_video.sh` — Full Script

```bash
#!/bin/bash
# Usage: ./process_video.sh period tips 001
# Processes one video folder completely.
# Run from /raw/ directory.
# Output goes to /cdn/ directory.

set -e

MODE=$1        # e.g. period
CATEGORY=$2    # e.g. tips
ID=$3          # e.g. 001

RAW_DIR="raw/$MODE/$CATEGORY/$ID"
OUT_DIR="cdn/videos/$MODE/$CATEGORY/$ID"
LANGS=("en" "hi" "gu" "mr" "ta" "te" "bn" "pa" "ur" "ar" "fr" "es" "de" "pt" "ru" "zh" "ja" "ko" "id" "tr" "sw" "vi" "fa" "am" "af")

echo "▶ Processing $MODE/$CATEGORY/$ID"
mkdir -p "$OUT_DIR/video"

# ── Step 1: Extract video-only from English master (strip audio) ──────
echo "  → Extracting video-only stream..."
ffmpeg -y -i "$RAW_DIR/en.mp4" \
  -an \
  -vcodec libx264 -crf 23 -preset fast \
  -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" \
  -hls_time 6 \
  -hls_playlist_type vod \
  -hls_segment_filename "$OUT_DIR/video/seg_%03d.ts" \
  "$OUT_DIR/video/stream.m3u8"

echo "  ✓ Video segments created"

# ── Step 2: Extract audio from each language ──────────────────────────
for LANG in "${LANGS[@]}"; do
  DUBBED_FILE="$RAW_DIR/$LANG.mp4"
  
  if [ ! -f "$DUBBED_FILE" ]; then
    echo "  ⚠ $LANG.mp4 not found — skipping (en fallback will be used)"
    continue
  fi

  mkdir -p "$OUT_DIR/audio/$LANG"
  
  echo "  → Extracting audio: $LANG..."
  ffmpeg -y -i "$DUBBED_FILE" \
    -vn \
    -acodec aac -b:a 96k -ac 2 -ar 44100 \
    -hls_time 6 \
    -hls_playlist_type vod \
    -hls_segment_filename "$OUT_DIR/audio/$LANG/seg_%03d.aac" \
    "$OUT_DIR/audio/$LANG/stream.m3u8"

  echo "  ✓ Audio $LANG done"
done

# ── Step 3: Copy thumbnail ────────────────────────────────────────────
if [ -f "$RAW_DIR/thumb.jpg" ]; then
  cp "$RAW_DIR/thumb.jpg" "$OUT_DIR/thumb.jpg"
  echo "  ✓ Thumbnail copied"
else
  echo "  ⚠ thumb.jpg not found! Please add it manually."
fi

# ── Step 4: Generate master.m3u8 per language variant ─────────────────
# See Section 4 — server generates this dynamically.
# We generate a "base" master.m3u8 with English as default here.
echo "  → Generating base master.m3u8..."

AUDIO_LINES=""
FIRST=true
for LANG in "${LANGS[@]}"; do
  if [ -d "$OUT_DIR/audio/$LANG" ]; then
    DEFAULT="NO"
    if $FIRST; then
      # en is first, set as default fallback
      # Actual per-user default is set by server dynamically
      DEFAULT="YES"
      FIRST=false
    fi
    LANG_NAME=$(echo "$LANG" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    AUDIO_LINES+="#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",LANGUAGE=\"$LANG\",NAME=\"$LANG_NAME\",DEFAULT=$DEFAULT,AUTOSELECT=YES,URI=\"audio/$LANG/stream.m3u8\"\n"
  fi
done

cat > "$OUT_DIR/master.m3u8" << EOF
#EXTM3U
#EXT-X-VERSION:6

$(echo -e "$AUDIO_LINES")
#EXT-X-STREAM-INF:BANDWIDTH=1200000,CODECS="avc1.64001f,mp4a.40.2",AUDIO="audio",RESOLUTION=1080x1920
video/stream.m3u8
EOF

echo "  ✓ master.m3u8 generated"
echo "▶ Done: $MODE/$CATEGORY/$ID"
echo "  Output: $OUT_DIR"
```

### `process_all.sh` — Batch Process Everything

```bash
#!/bin/bash
# Processes every video in every mode/category

MODES=("period" "pregnancy")
CATEGORIES=("tips" "awareness" "avoid")

for MODE in "${MODES[@]}"; do
  for CATEGORY in "${CATEGORIES[@]}"; do
    RAW_PATH="raw/$MODE/$CATEGORY"
    if [ -d "$RAW_PATH" ]; then
      for ID_DIR in "$RAW_PATH"/*/; do
        ID=$(basename "$ID_DIR")
        ./process_video.sh "$MODE" "$CATEGORY" "$ID"
      done
    fi
  done
done

echo "✅ All videos processed."
```

---

## 4. Server Changes — Catalog API

### What Changes

The server no longer resolves `video_url` to a language-specific `.mp4`. Instead it returns **one `stream_url`** (the `master.m3u8`) and the `preferred_audio_lang` separately. The Flutter player handles audio track selection.

### Updated API Response

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
          "description": "पर्याप्त पानी पीने से ऐंठन कम होती है...",
          "duration_sec": 54,
          "stream_url": "https://cdn.yourapp.com/videos/period/tips/001/master.m3u8",
          "thumbnail_url": "https://cdn.yourapp.com/videos/period/tips/001/thumb.jpg",
          "preferred_audio_lang": "hi",
          "available_audio_langs": ["en", "hi", "gu", "mr", "ta"],
          "video_lang_resolved": "hi"
        }
      ]
    }
  }
}
```

### Field Changes

| Old Field | New Field | Notes |
|---|---|---|
| `video_url` (lang-specific .mp4) | `stream_url` (master.m3u8) | Same URL for all users of same video |
| — | `preferred_audio_lang` | Server tells Flutter which audio track to prefer |
| — | `available_audio_langs` | Flutter can show a language picker in player UI |
| `video_lang_resolved` | `video_lang_resolved` | Unchanged — now refers to audio track resolved |

### Server — Audio Language Resolution Logic

The resolution logic moves from "which `.mp4` exists?" to "which audio track exists?":

```javascript
// Node.js example (same logic applies to any server language)

function resolveAudioLang(mode, category, id, requestedLang) {
  const audioBase = path.join(videoRoot, mode, category, id, 'audio');
  
  // Fallback chain: requested → hi (regional) → en (guaranteed)
  const fallbackChain = [requestedLang, 'hi', 'en'];
  
  for (const lang of fallbackChain) {
    if (fs.existsSync(path.join(audioBase, lang, 'stream.m3u8'))) {
      return lang;
    }
  }
  
  throw new Error(`No audio found for ${mode}/${category}/${id} — en must always exist`);
}

function getAvailableAudioLangs(mode, category, id) {
  const audioBase = path.join(videoRoot, mode, category, id, 'audio');
  if (!fs.existsSync(audioBase)) return ['en'];
  return fs.readdirSync(audioBase).filter(lang =>
    fs.existsSync(path.join(audioBase, lang, 'stream.m3u8'))
  );
}
```

### Server — master.m3u8 Generation (Dynamic, Per-Request)

The server can serve `master.m3u8` in two ways:

**Option A — Static file, Flutter overrides via preferred_audio_lang (Simpler)**

Keep the static `master.m3u8` generated by the bash script. The catalog response tells Flutter `preferred_audio_lang: "hi"`. Flutter uses the HLS API to select the matching audio track by language code. The `DEFAULT=YES` in the playlist is irrelevant — Flutter overrides it programmatically.

**Option B — Dynamic master.m3u8 endpoint (Cleaner)**

Server generates `master.m3u8` on the fly with the correct `DEFAULT=YES` for the user's language:

```
GET /hls/period/tips/001/master.m3u8?lang=hi
```

Returns a playlist with `DEFAULT=YES` on the `hi` audio track. Flutter plays it, player auto-selects the default audio. No Flutter code needed to override tracks.

**Recommendation: Use Option A.** Static files on CDN are faster, cheaper, and simpler. Flutter programmatic track selection is 3 lines of code.

---

## 5. Flutter — Changes Required

### 5.1 Package Update

Replace `video_player` with `better_player` which has full HLS audio track API:

```yaml
# pubspec.yaml
dependencies:
  better_player: ^0.0.84        # HLS + audio track switching
  cached_network_image: ^3.3.x  # unchanged
  isar_community: ^3.x          # unchanged
  uuid: ^4.x                    # unchanged
  connectivity_plus: ^5.x       # unchanged
  http: ^1.2.x                  # unchanged
```

> **Why `better_player` over `video_player`?**
> `video_player` (official Flutter package) plays HLS but has NO API to programmatically select audio tracks. `better_player` wraps ExoPlayer (Android) and AVPlayer (iOS) and exposes full HLS track selection. This is the only Flutter package that supports this properly.

### 5.2 Updated Local State Schema

Minimal change — `video_lang_resolved` is now `audio_lang_resolved`. Everything else identical:

```json
{
  "install_id": "a3f7b2c1-...",

  "period": {
    "tips": {
      "unwatched_queue": ["004", "007", "002", "005", "001", "006", "003"],
      "watched": ["003", "006"],
      "cycle": 1,
      "known_total": 7
    },
    "awareness": { ... },
    "avoid": { ... }
  },

  "pregnancy": { ... },

  "catalog_version_period": "2025-04-27-v3",
  "catalog_version_pregnancy": "2025-04-27-v2",

  "lang": "hi"
}
```

No structural change to local_state at all. The queue, watched[], cycle, known_total — all identical. Language change handling — identical. Catalog version sync — identical. All existing logic is preserved 100%.

### 5.3 Video Player Widget — Complete Implementation

```dart
import 'package:better_player/better_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final CatalogVideo video;       // from your catalog model
  final String preferredLang;     // from local_state.lang

  const VideoPlayerScreen({
    required this.video,
    required this.preferredLang,
    super.key,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late BetterPlayerController _controller;
  bool _watchedMarked = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    // ── Data source: HLS master playlist ─────────────────────────────
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.video.streamUrl,           // master.m3u8 URL
      videoFormat: BetterPlayerVideoFormat.hls,
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: true,
        maxCacheSize: 100 * 1024 * 1024,     // 100MB total cache
        maxCacheFileSize: 20 * 1024 * 1024,  // 20MB per video
        // Caches segments on disk — user rewatching skips network
      ),
    );

    // ── Player configuration ──────────────────────────────────────────
    final config = BetterPlayerConfiguration(
      aspectRatio: 9 / 16,              // vertical video
      fit: BoxFit.cover,
      autoPlay: true,
      looping: false,
      fullScreenByDefault: true,
      allowedScreenSleep: false,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControlsOnInitialize: false,
        enableFullscreen: true,
        enableProgressBar: true,
        enableSkips: false,             // health videos — no skipping
        enableMute: true,
        enablePlaybackSpeed: false,     // keep it simple for health content
        progressBarPlayedColor: Colors.pinkAccent,
        progressBarBufferedColor: Colors.pink.withOpacity(0.3),
        controlBarColor: Colors.black54,
      ),
    );

    _controller = BetterPlayerController(config);
    _controller.setupDataSource(dataSource);

    // ── Select correct audio track after player initializes ───────────
    _controller.addEventsListener(_onPlayerEvent);
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {

      // ── Video initialized: select audio track ──────────────────────
      case BetterPlayerEventType.initialized:
        _selectAudioTrack();
        break;

      // ── Track progress for watch threshold ────────────────────────
      case BetterPlayerEventType.progress:
        _checkWatchProgress();
        break;

      // ── Video finished: mark watched (safety net) ─────────────────
      case BetterPlayerEventType.finished:
        if (!_watchedMarked) {
          _markWatched();
        }
        break;

      default:
        break;
    }
  }

  /// Selects the audio track matching preferred language.
  /// Falls back gracefully if track not found.
  void _selectAudioTrack() {
    final tracks = _controller.betterPlayerAudioTracks;
    if (tracks == null || tracks.isEmpty) return;

    // Try to find exact language match
    BetterPlayerAudioTrack? match;

    // 1. Try preferred language (e.g. "hi")
    match = tracks.firstWhereOrNull(
      (t) => t.language?.toLowerCase() == widget.preferredLang.toLowerCase()
    );

    // 2. Try regional fallback (Hindi for Indian languages)
    match ??= tracks.firstWhereOrNull(
      (t) => t.language?.toLowerCase() == 'hi'
    );

    // 3. Try English (always exists)
    match ??= tracks.firstWhereOrNull(
      (t) => t.language?.toLowerCase() == 'en'
    );

    // 4. Just use whatever is first
    match ??= tracks.first;

    if (match != null) {
      _controller.setAudioTrack(match);
    }
  }

  void _checkWatchProgress() {
    if (_watchedMarked) return;

    final position = _controller.videoPlayerController?.value.position;
    final duration = _controller.videoPlayerController?.value.duration;

    if (position == null || duration == null) return;
    if (duration.inSeconds == 0) return;

    final progress = position.inSeconds / duration.inSeconds;

    if (progress >= 0.70) {
      _watchedMarked = true;
      _markWatched();
    }
  }

  void _markWatched() {
    // Same markVideoWatched() logic as v1 — completely unchanged
    context.read<QueueCubit>().markVideoWatched(
      videoId: widget.video.id,
      mode: widget.video.mode,
      category: widget.video.category,
    );
  }

  @override
  void dispose() {
    _controller.removeEventsListener(_onPlayerEvent);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Player ───────────────────────────────────────────────
            Expanded(
              child: BetterPlayer(controller: _controller),
            ),

            // ── Title + Description ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.video.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.video.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),

                  // ── Audio language indicator ───────────────────────
                  if (widget.video.videoLangResolved != widget.preferredLang)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _AudioFallbackBadge(
                        requestedLang: widget.preferredLang,
                        resolvedLang: widget.video.videoLangResolved,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small UI badge shown when audio fell back to another language ─────
class _AudioFallbackBadge extends StatelessWidget {
  final String requestedLang;
  final String resolvedLang;

  const _AudioFallbackBadge({
    required this.requestedLang,
    required this.resolvedLang,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Text(
        'Playing in ${_langName(resolvedLang)} (${_langName(requestedLang)} coming soon)',
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    );
  }

  String _langName(String code) {
    const names = {
      'en': 'English', 'hi': 'Hindi', 'gu': 'Gujarati',
      'mr': 'Marathi', 'ta': 'Tamil', 'te': 'Telugu',
      // add all 25...
    };
    return names[code] ?? code.toUpperCase();
  }
}
```

### 5.4 Pre-Initialization (Unchanged Logic, Updated Package)

```dart
// Pre-initialize first video of Tips category on feed load
// Same logic as v1, just using BetterPlayerController now

void _preInitFirstVideo(CatalogVideo video, String lang) {
  final dataSource = BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    video.streamUrl,
    videoFormat: BetterPlayerVideoFormat.hls,
    cacheConfiguration: BetterPlayerCacheConfiguration(useCache: true),
  );

  final preloadController = BetterPlayerController(
    const BetterPlayerConfiguration(autoPlay: false),
  );
  preloadController.setupDataSource(dataSource);

  // Store reference — pass to VideoPlayerScreen when user taps
  _preloadedController = preloadController;
}
```

### 5.5 Catalog Model Update

```dart
// models/catalog_video.dart

class CatalogVideo {
  final String id;
  final String fullId;
  final String title;
  final String description;
  final int durationSec;
  final String streamUrl;           // NEW: was video_url, now master.m3u8
  final String thumbnailUrl;
  final String preferredAudioLang;  // NEW: which audio track to select
  final List<String> availableAudioLangs; // NEW: for optional picker UI
  final String videoLangResolved;   // same as before
  final String mode;
  final String category;
  final bool active;

  CatalogVideo.fromJson(Map<String, dynamic> json, String mode, String category)
    : id = json['id'],
      fullId = json['full_id'],
      title = json['title'],
      description = json['description'],
      durationSec = json['duration_sec'],
      streamUrl = json['stream_url'],           // field name changed
      thumbnailUrl = json['thumbnail_url'],
      preferredAudioLang = json['preferred_audio_lang'],
      availableAudioLangs = List<String>.from(json['available_audio_langs'] ?? ['en']),
      videoLangResolved = json['video_lang_resolved'],
      mode = mode,
      category = category,
      active = json['active'] ?? true;
}
```

---

## 6. Language Change Handling — Updated

Behavior is BETTER in v2. In v1, changing language required deleting and re-fetching the entire catalog because `video_url` was language-specific. In v2:

```
User switches Hindi → Gujarati
    ↓
Update lang in local_state → save (same as v1)
    ↓
Fetch new catalog for lang=gu (same as v1)
    → server returns same stream_url (master.m3u8 is language-agnostic)
    → server returns preferred_audio_lang: "gu"
    → server returns video_lang_resolved: "gu" (or "hi" if gu audio missing)
    ↓
Next video open:
    → same master.m3u8 URL plays
    → Flutter calls _selectAudioTrack() with new preferredLang
    → ExoPlayer/AVPlayer switches to gu audio track
    → video visuals never rebuffer — only audio track switches
    ↓
Watch history: completely unchanged (same as v1)
```

**Key improvement:** The `stream_url` is the same for all languages (it's always `master.m3u8`). So if the catalog has already been fetched and cached, Flutter can switch audio track immediately — zero network call. The catalog re-fetch is only needed because titles and descriptions need to be in the new language.

---

## 7. CDN Configuration — Critical Requirements

Your CDN MUST serve HLS files with these headers or playback will fail:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
Content-Type: application/vnd.apple.mpegurl    (for .m3u8 files)
Content-Type: video/MP2T                       (for .ts files)
Content-Type: audio/aac                        (for .aac files)
Cache-Control: public, max-age=31536000        (for segment files — immutable)
Cache-Control: public, max-age=60              (for .m3u8 playlists — short TTL)
```

**Why short TTL for .m3u8?** Segment files never change (immutable content). Playlist files could be regenerated when you add a language. Cache playlists briefly, cache segments forever.

### Cloudflare (Recommended CDN)

If using Cloudflare:
1. Enable "Cache Everything" page rule for `/videos/*`
2. Set Edge TTL: 1 year for `.ts` and `.aac`, 1 minute for `.m3u8`
3. Enable Brotli compression (helps .m3u8 text files)
4. Enable HTTP/2 (parallel segment downloads = faster start)

---

## 8. Adding a New Video — Updated Workflow

```
1. Record video in English
   Export as 1080×1920, under 90 seconds

2. Dub using SoniTranslate
   Output: raw/period/tips/008/en.mp4, hi.mp4, gu.mp4, mr.mp4, ta.mp4...
   (same as v1 — SoniTranslate output unchanged)

3. Run processing script
   ./process_video.sh period tips 008
   → Generates cdn/videos/period/tips/008/ with full HLS structure
   → Extracts video-only stream
   → Extracts audio per language
   → Generates master.m3u8

4. Upload cdn/videos/period/tips/008/ to CDN
   (same as v1 — just a folder upload)

5. Add to videos.json (identical to v1)
   Append "008" to period.tips array
   Increment catalog_version

6. Add text to content.en.json (identical to v1)
   "period_tips_008_title": "...",
   "period_tips_008_desc": "...",

7. Run jsontt (identical to v1)
8. Deploy content/langs/ to server (identical to v1)
9. Verify
   GET /api/catalog?mode=period&lang=hi
   Check stream_url resolves, master.m3u8 is reachable

Done. New video live on next user app open.
```

Steps 1, 5, 6, 7, 8, 9 are **100% identical to v1**. Only step 3 (FFmpeg processing) replaces the old "export language variants" step.

---

## 9. Adding a New Language to Existing Videos

This is where v2 truly shines over v1. In v1, adding a new language meant re-exporting 80 full videos. In v2:

```
1. Run SoniTranslate on all English masters → get {new_lang}.mp4 per video
   Input: raw/period/tips/001/en.mp4
   Output: raw/period/tips/001/sw.mp4  (Swahili example)

2. Extract audio only and generate HLS audio segments
   Run for each video:
   ./add_audio_lang.sh sw
   (script below)

3. Regenerate master.m3u8 for each video (adds new EXTX-MEDIA entry)
   ./regenerate_playlists.sh

4. Upload only the new audio/ folders to CDN
   cdn/videos/period/tips/001/audio/sw/
   cdn/videos/period/tips/002/audio/sw/
   ... (audio files only — video unchanged)

5. Catalog version bump — server now returns sw in available_audio_langs
```

`add_audio_lang.sh`:

```bash
#!/bin/bash
# Usage: ./add_audio_lang.sh sw
# Adds a new language audio to ALL existing videos

NEW_LANG=$1
MODES=("period" "pregnancy")
CATEGORIES=("tips" "awareness" "avoid")

for MODE in "${MODES[@]}"; do
  for CATEGORY in "${CATEGORIES[@]}"; do
    for ID_DIR in raw/$MODE/$CATEGORY/*/; do
      ID=$(basename "$ID_DIR")
      INPUT="raw/$MODE/$CATEGORY/$ID/$NEW_LANG.mp4"
      OUT_DIR="cdn/videos/$MODE/$CATEGORY/$ID/audio/$NEW_LANG"

      if [ ! -f "$INPUT" ]; then
        echo "⚠ Skipping $MODE/$CATEGORY/$ID — $NEW_LANG.mp4 not found"
        continue
      fi

      mkdir -p "$OUT_DIR"
      ffmpeg -y -i "$INPUT" \
        -vn -acodec aac -b:a 96k -ac 2 -ar 44100 \
        -hls_time 6 -hls_playlist_type vod \
        -hls_segment_filename "$OUT_DIR/seg_%03d.aac" \
        "$OUT_DIR/stream.m3u8"

      echo "✓ $MODE/$CATEGORY/$ID — $NEW_LANG audio done"
    done
  done
done
echo "✅ Language $NEW_LANG added to all videos."
```

**Video files on CDN: never touched. Zero re-upload of visual content.**

---

## 10. Storage Reality Check — v1 vs v2

### Per Video (70MB full video, 60s duration)

| Item | v1 | v2 |
|---|---|---|
| Video storage | 70MB × 25 langs = 1,750MB | ~65MB (video-only segments) |
| Audio per lang | (bundled in video) | ~3MB per lang × 25 = ~75MB |
| Thumbnail | ~0.1MB | ~0.1MB (unchanged) |
| **Total per video** | **~1,750MB** | **~140MB** |
| **Savings** | — | **92% smaller** |

### Full Library (80 videos)

| | v1 | v2 |
|---|---|---|
| Total CDN storage | ~140 GB | ~11.2 GB |
| Adding 1 new language | +5.6 GB (full videos) | +240 MB (audio only) |
| Adding 1 new video | +1,750 MB | +140 MB |

### Bandwidth Per Play (60s video, user watches 100%)

| | v1 | v2 |
|---|---|---|
| Data transferred | ~70MB (full file) | ~8MB (video segs watched + audio) |
| Savings | — | ~89% less bandwidth |

HLS only streams segments the user actually watches. A user who watches 30 of 60 seconds downloads half the segments. v1 often pre-fetches the entire file.

---

## 11. Edge Cases — All Handled

| Scenario | v1 Handling | v2 Handling |
|---|---|---|
| Audio not available in user's language | Return different .mp4 URL | `_selectAudioTrack()` falls back hi → en |
| User loses internet mid-video | Stops playing | Already-downloaded segments still play; buffer continues from reconnect |
| Language switch mid-session | Catalog re-fetch required (different video_url) | Same stream_url; only audio track switches; no re-fetch needed for player |
| New language added to library | Add 80 new .mp4 files (full videos) | Add 80 audio folders only; zero video re-upload |
| Video has only English audio | master.m3u8 has only en entry; fallback works | Same — `_selectAudioTrack()` uses en |
| master.m3u8 unreachable (CDN down) | .mp4 unreachable (same failure mode) | Show error, retry on reconnect |
| App offline first launch | Show offline state | Identical to v1 |
| Segment download fails mid-stream | N/A | ExoPlayer/AVPlayer auto-retries segment; seamless recovery |
| User skips through video | N/A in v1 | Segments download from seek position; unwatched segments skipped entirely |
| `active: false` video | Skip in display | Identical — active flag logic unchanged |
| catalog JSON corrupted | Re-fetch | Identical to v1 |
| Two devices same user | Independent local_state | Identical to v1 |
| App reinstall | Fresh state | Identical to v1 |

---

## 12. What Stays 100% Unchanged from v1

This is important — the entire intelligence layer of your app is untouched:

- `local_state` schema — unchanged
- `install_id` generation — unchanged
- Seeded shuffle algorithm — unchanged
- Watch progress 70% threshold — unchanged
- `markVideoWatched()` logic — unchanged
- `resetCategory()` logic — unchanged
- Category reset rules — unchanged
- Video selection algorithm (per-open stability) — unchanged
- New video sync via `catalog_version` — unchanged
- Language change handling logic — unchanged (catalog re-fetch, watch history preserved)
- Mode switching logic — unchanged
- Offline behaviour — unchanged
- `videos.json` format — unchanged
- `content.en.json` format — unchanged
- jsontt translation workflow — unchanged
- Server caching strategy — unchanged (same cache key formula)
- Server language file loading — unchanged

**The ONLY things that change:**

1. Folder structure on CDN (add `video/`, `audio/` subdirs; remove lang-specific .mp4)
2. FFmpeg processing step (new script instead of direct export)
3. `video_url` → `stream_url` in API response + two new fields
4. `video_player` → `better_player` in Flutter
5. `VideoPlayerScreen` widget (audio track selection, 20 new lines)
6. `CatalogVideo` model (3 new fields)

---

## 13. Migration Plan (v1 → v2, Zero Downtime)

Since your app is live, here's how to migrate without breaking existing users:

```
Phase 1 — Parallel processing (no user impact)
  Process all existing videos through new FFmpeg script
  Upload HLS structure to CDN alongside existing .mp4 files
  Do NOT remove .mp4 files yet
  Do NOT update server API yet

Phase 2 — Server API update
  Add stream_url field to catalog response (alongside old video_url)
  Bump catalog_version

Phase 3 — Flutter app update
  Release new Flutter build with better_player
  App checks: if stream_url exists → use HLS; else → fall back to video_url
  This handles users on old app version gracefully

Phase 4 — Cleanup (2-4 weeks after Flutter update)
  Once >95% users are on new version
  Remove old video_url field from API
  Delete .mp4 files from CDN (keep audio/ and video/ HLS structure)
  Save ~90% CDN storage costs
```

Backward compatibility snippet in Flutter (Phase 3):

```dart
// Temporary migration bridge
String getPlaybackUrl(CatalogVideo video) {
  // New HLS path
  if (video.streamUrl.isNotEmpty) return video.streamUrl;
  // Old v1 fallback (for users who haven't updated yet)
  return video.videoUrl;
}
```

---

## 14. Final Architecture Contract (Updated)

| Layer | Responsibility | Does NOT Do |
|---|---|---|
| Server | Serve full translated catalog with resolved stream_url and preferred_audio_lang | Date math, user state, rotation, video encoding |
| CDN | Serve HLS segments (.ts, .aac) and playlists (.m3u8) | Anything else |
| Flutter | Queue management, watch tracking, audio track selection, selection logic | Translation, language fallback |
| Device storage | Local state + catalog cache | Server communication |
| FFmpeg (build time) | Convert dubbed videos to HLS segments | Runtime involvement |

### Key Invariants (Updated)

1. `audio/en/stream.m3u8` must exist for every video — final audio fallback guarantee
2. `video/stream.m3u8` must exist for every video — one visual copy, always
3. `thumb.jpg` must exist — unchanged
4. `install_id` never sent to server — unchanged
5. `catalog_version` must change when `videos.json` changes — unchanged
6. Video IDs in `videos.json` are never deleted — unchanged
7. `watched[]` check before sync — unchanged
8. `markVideoWatched()` duplicate guard — unchanged
9. **NEW:** `master.m3u8` must list all available audio languages for that video
10. **NEW:** Audio segment count must match video segment count — or sync issues occur at last segment

---

## 15. Summary

```
You manage:       content.en.json + videos.json + dubbed .mp4 from SoniTranslate
FFmpeg handles:   Strip video/audio, segment into HLS, generate playlists
jsontt handles:   25 language text translations (unchanged)
CDN serves:       master.m3u8 + video segments + audio segments (per-lang)
Server does:      Catalog build + text resolution + preferred_audio_lang logic
Flutter does:     HLS playback + audio track selection + all queue logic (unchanged)
Users get:        Same personalised queue + instant language switching +
                  faster start (streaming not download) + 89% less data usage
Storage:          92% smaller than v1
```
