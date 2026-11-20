# FrameShift — CLAUDE.md

iOS camera app that helps users recreate reference photos in real time. A user imports reference photos (from Photos — typically saved from Pinterest, Instagram, etc.), the app silently analyzes each one to extract a shot spec, and the live camera screen uses that spec to guide framing (head circle, level/tilt, zoom, coaching tips, reference ghost overlay).

No backend. No account. Fully on-device. iOS 17+, iPhone-only.

App identity: product/target `FrameShift`, bundle ID `com.anirudhkamath.frameshift`.

---

## Framework Ownership

| Feature | Framework |
|---|---|
| Camera feed | AVFoundation — AVCaptureSession, AVCaptureVideoPreviewLayer |
| Subject detection on reference | Vision — human/face/pose/horizon batch in `VisionAnalyzer` |
| Live subject / reference cutout | Vision — `LiveVisionAnalyzer`, `PersonSegmenter` |
| Level / pitch | CoreMotion — `MotionService` (roll + pitch) |
| Photo import | PhotosUI — `PhotosPicker` |
| Photo export / save | Photos — PHPhotoLibrary (add-only) |
| Haptics | UIKit — UIImpactFeedbackGenerator |
| UI | SwiftUI throughout |

Do not use third-party dependencies. All required frameworks ship with iOS 17.

---

## Data Models

`ShotSpec` (see `Models/ShotSpec.swift`) is the central object: subject/placement boxes, pose landmarks, head guide, target roll/pitch + confidence, recommended zoom, framing style, reference size. Specs are computed on import and **persisted** in `ReferenceStore` with `ShotSpec.analyzerVersion`. Cold launch loads cached specs/cutouts and **skips Vision** when the stored version matches; bump `analyzerVersion` to invalidate (reanalyze once, then save).

```swift
struct ReferencePhoto: Identifiable {
    let id: UUID
    let image: UIImage          // display-sized; full bytes stay on disk
    var spec: ShotSpec?         // persisted in references.json when analyzed
    var personCutout: UIImage?  // display-sized in RAM; PNG on disk
    var analysisFailed: Bool    // persisted with analyzerVersion
    var isFavorite: Bool        // persisted; leads quick-access row
    var useCount: Int           // persisted; bumped by AppState.useReference
    var lastUsedAt: Date?       // persisted; ranks "recent"
    let importedAt: Date
}

struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage          // display-sized; full JPEG in Photos + session temp cache
    let capturedAt: Date
    let referenceID: UUID?
    let burstID: UUID?          // shots from one shutter hold share this
    var isBurstBest: Bool       // user-picked cover of its burst group
}
```

Persistence: `ReferenceStore` keeps original import bytes + JSON manifest (per-entry `analyzerVersion`, `spec`, `analysisFailed`) + `{id}.cutout.png`; captures are **not** persisted in the app (D-25): `AppState.capturedShots` holds only the current session in memory, with full JPEGs + a session manifest in `SessionCaptureCache` (Caches dir). A session still open when iOS closes the app is restored on launch (last capture < 30 min); otherwise the cache is cleared. On launch, `ReferenceStore` decodes **downsampled** images into `AppState` (`UIImage+Downsample`). Full-resolution decode is only for Vision analysis (import / version-mismatch migrate) and full-size share / Add to References from the session cache.

---

## Project Structure

```
FrameShift/                                 // workspace root
├── CLAUDE.md
├── PRIVACY.md
├── appstore-readiness-prd.md
├── settings-menu-prd.md
├── accounts-paid-features-prd.md           // deferred post-v1
├── tasks/                                  // historical PRDs / stitch specs
└── Frameshift/
    ├── FrameShift.xcodeproj
    ├── FrameShiftTests/
    ├── FrameShiftUITests/
    └── FrameShift/
        ├── App/
        │   ├── FrameShiftApp.swift         // @main; restore on launch
        │   └── AppState.swift              // references, captures, persistence, notices
        ├── Models/
        │   ├── ReferencePhoto.swift
        │   ├── ShotSpec.swift
        │   └── CapturedPhoto.swift
        ├── Extensions/
        │   ├── AspectFillMapper.swift      // ImageContentMapper: normalized ↔ container
        │   ├── Color+Hex.swift
        │   ├── UIImage+Upright.swift       // bakes orientation into pixels
        │   └── UIImage+Downsample.swift    // ImageIO thumbnails for restore/display
        ├── Services/
        │   ├── VisionAnalyzer.swift        // import-time ShotSpec batch
        │   ├── LiveVisionAnalyzer.swift    // live-frame subject detection
        │   ├── PersonSegmenter.swift       // reference ghost cutout
        │   ├── HeadBoundsEstimator.swift
        │   ├── PitchEstimator.swift
        │   ├── RollEstimator.swift         // EXIF attitude → horizon → level
        │   ├── ReferenceEXIF.swift         // analysis-only; never shown in UI
        │   ├── CompositionCoach.swift      // tips + CompositionProgress
        │   ├── CameraService.swift         // session, zoom, flash, front, capture crop
        │   ├── MotionService.swift
        │   ├── SampleReferencePack.swift   // bundled starter refs (Gemini stills)
        │   ├── ReferenceStore.swift
        │   ├── SessionCaptureCache.swift   // temp full-res JPEGs for the open session only
        │   ├── PhotoLibrarySaver.swift     // add-only Photos writes
        ├── Screens/
        │   ├── Root/RootTabView.swift      // shell → CameraView only
        │   ├── Gallery/                    // GalleryHomeView (home: Explore/Yours), ReferencePreviewView
        │   ├── References/                 // ReferencesViewModel (import helper) only
        │   ├── Camera/                     // viewfinder, aids, CoachingPill, ReferencePickerSheet, permission/unavailable states
        │   ├── Session/                    // SessionGalleryView, SessionViewerView, BurstReviewView
        │   ├── Shared/FirstUseTour.swift   // spotlight tours (replace onboarding)
        │   └── Settings/                   // from gallery `⋯` only
        ├── PrivacyInfo.xcprivacy
        └── Assets.xcassets
```

---

## App Shell & Navigation

> **UI redesign in progress** (branch `ui-overhaul`). Source of truth: Paper file
> "FrameShift — UX Redesign" (approved artboards), the UX package in
> `docs/ux-redesign/`, and **`docs/design-decisions.md`** (decisions, rejected
> alternatives, precedence, open questions — read it before changing UI). Phases: 0 tokens/data model ✅ · 1 camera ✅ ·
> 2 gallery home ✅ · 3 session gallery/viewer ✅ · 4 first use & errors ✅ · 5 settings ✅ · 6 cleanup.

- `RootTabView` is just `CameraView()`. The gallery home (`GalleryHomeView`)
  renders inside `CameraView` when `selectedTab == .references`, layered over
  the camera — the camera stays mounted so `ViewfinderView` is never rebuilt
  (re-attaching the preview layer inside a layout pass hangs the main thread).
- Launch: always the gallery home; the camera session starts underneath so it's
  warm on Recreate / Resume Camera (D-2). An empty library seeds the bundled samples (Explore).
- Gallery home: header (Resume Camera, `+` import, `⋯` → Settings / How to Use),
  "Recents" quick row, Explore/Yours switch + chips (Women / Men toggle, then
  composition), 2-column grid with a heart (favorite) on every tile. Tap → full-bleed
  `ReferencePreviewView` → **Recreate** (→ camera). Import opens the preview
  with a "Preparing reference…" → "Added to Yours" pill.
- Light/dark: the app follows the system; `CameraView` forces dark only while
  the camera is showing. Modals from the camera use `.preferredColorScheme(.system)`.
- Camera top row: back chevron (→ references), reference thumbnail + chevron
  (one control: tap → picker sheet, hold → peek), **Overlay** and **Guides**
  mode buttons, one-tap flash (off/on), `⋯` menu (Grid, inline 4:3 Posts /
  16:9 Stories aspect; an Equatable subview so camera updates don't break it).
- `ReferencePickerSheet`: compact detent (favorites & recent) → large
  (Explore / Yours + composition chips). Choosing a reference calls
  `AppState.useReference` and never resets the capture session.
- Session thumbnail (bottom-left) → `SessionGalleryView`: this session's shots
  only (already in Photos), bursts collapse to one tile → `BurstReviewView`
  (Set as Cover); singles → `SessionViewerView` (hold or Compare toggles the
  reference; bottom bar Share · Compare · Delete, `⋯` Save as Reference).
  Select (tap or sideways drag across tiles) → Add to References / Share / Delete.
- First use: `WelcomeView` (one screen, press the shutter to start, D-34), then no
  onboarding carousel — `FirstUseTour` spotlight cards — Explore
  (2 steps) on the gallery, Camera (4 steps) once camera access is granted.
  Settings → Replay Tutorial resets both.
- Camera access: `CameraAccessExplanationView` before the system prompt
  (Not Now → gallery); denied → `CameraPermissionDeniedView`. Failed analysis →
  `ReferenceUnavailableCard`; failed Photos save → Try Again / Discard alert.
- Settings opens from the gallery header `⋯` only — not from the camera chrome.

---

## Camera Capabilities (current)

`CameraService` is beyond the original minimal sketch:

- Multi-lens display zoom (back ~0.5×–6×; front 1×–3×)
- Tap-to-focus + vertical drag exposure bias (`FocusReticle`)
- Flash / screen flash, front/back flip
- Hold-to-burst on shutter: 0.1s cadence with overlapping `.speed` captures
  (flash off), per-shot viewfinder blink, live count inside the shutter button
- Bursts share a `burstID` and appear as one gallery item; the burst badge
  opens `BurstPickerSheet` (pick best = cover, or "Keep Only This Photo")
- Captures cropped to the visible preview region
- Aspect modes from the `⋯` menu: 4:3 (full sensor, feed posts) and 16:9
  (9:16 story crop) — the viewfinder box ratio drives the capture crop

### Visual-aid state machine (`CameraViewModel.AidMode`)
- **Adaptive** starts at Overlay; after `stableDetectionDelay` (1.5s) of
  continuous person detection it moves once to Guides and stays there.
- Overlay / Guides buttons select **Manual** modes (yellow highlight, only for
  manual). Re-tapping the active one → **Manual Clean**, never back to Adaptive.
- Reference switch or re-entering the camera restarts Adaptive. Camera flip
  keeps the mode.
- Overlay: person cutout at fixed `referenceOverlayOpacity` (35%), no slider.
- Guides: one fixed head-target circle (`SubjectPlacementGuide`, white → yellow
  when aligned) + contextual level (`TiltPitchGuide`, fades once level).
- `CoachingPill` is independent of the mode (also in Clean): one instruction,
  "Looking for subject", brief "Looking good" then a yellow check; tap collapses
  it (session-scoped).
- Alignment: one light haptic + confirmation per alignment, re-armed only by
  real misalignment (coach hysteresis).

### Capture session
`AppState.sessionShotIDs` counts captures **confirmed saved to Photos**; it
drives the white count badge on the bottom-left thumbnail. A session ends after
`sessionInactivityLimit` (30 min, provisional) without a capture; reference
switches never reset it. Deleting a shot removes it from the count.

Delete (session gallery selection bar, viewer `⋯`) removes the shot from the
camera roll via its stored `photosAssetID` (`PhotoLibrarySaver.deleteAssets`).
Read/write Photos access is requested only at the first Delete; iOS confirms
and keeps the photo in Recently Deleted.

Zoom fine-adjust: drag sideways on the zoom row (left = in), haptic tick per lens; VoiceOver adjustable.

### Coaching eval (debug builds only)
Camera `⋯` → **Coaching Eval** shows live coach signals and event counts
(`Screens/Camera/CoachEval.swift`). Protocol and pass bar:
`docs/coaching-eval.md` (resolves O-5 / O-6).

---

## Key Flows

### Import → analyze → persist
1. `PhotosPicker` / sample pack → `AppState.importReference`
2. Photo appears immediately; `VisionAnalyzer.analyze` runs off main actor
3. Spec + person cutout update `AppState` and `ReferenceStore` (`analyzerVersion`,
   JSON spec / `analysisFailed`, `{id}.cutout.png`); failures set `analysisFailed`

### Cold launch restore
1. `ReferenceStore.loadAll` decodes display images + cached specs/cutouts
2. Matching `ShotSpec.analyzerVersion` → **no Vision**; coaching ready immediately
3. Missing / stale version (or pre-persistence manifests) → serial reanalyze
   (active first, yield for camera, then persist) — same queue as imports

Cold start empty state: "Try sample references" runs 9 bundled Gemini
(Nano Banana) stills (`Assets.xcassets/SampleRef*`, listed in
`Services/SampleReferencePack.swift`) through the import pipeline. Fully
offline; the no-network rule holds.

### Capture → save
1. `CameraService.capturePhoto` → cropped `UIImage`
2. `AppState.addCapturedShot` inserts display-sized image, writes a temporary JPEG to `SessionCaptureCache`, add-only save via `PhotoLibrarySaver` (failure → Try Again / Discard)
3. Photos-denied → one-time non-blocking notice with Settings action

### Recreate
Preview → **Recreate** sets the reference, switches to the (mounted) camera,
and morphs the photo onto `AppState.viewfinderFrame`, fading into the overlay
(D-29). Reduce Motion → cross-fade. The preview cover uses a clear
presentation background so the camera shows through.

---

## Design Tokens

```swift
extension Color {
    static let cameraYellow = Color(hex: "#FFD60A")
    static let systemBlue   = Color(hex: "#007AFF")
    static let gridLine     = Color.white.opacity(0.25)
    static let boxIdle      = Color.white.opacity(0.80)
    static let boxLocked    = Color(hex: "#FFD60A")
    static let levelNeutral = Color.white.opacity(0.40)
    static let levelLocked  = Color(hex: "#FFD60A")
}
```

Typography: SF only, never custom font names. Text uses text styles (`.system(.body, weight: .semibold)`) so it follows Dynamic Type (D-32); screens cap at `.xxxLarge` where fixed-height controls would clip (Settings is uncapped). Fixed `.system(size:)` only for camera chrome and glyphs, like the system Camera.

Shutter: outer ring 78pt / 3pt white stroke; inner fill 66pt.

Redesign tokens: `cameraControl` #242424 (zoom selection, flip),
`cameraAccentTint` #332B00 (behind yellow glyph on a selected control),
`coachPill` black 72%, `guideIdle` white 90%.

---

## Permissions (generated Info.plist keys)

```
NSCameraUsageDescription — FrameShift needs camera access to help you recreate reference shots.
NSPhotoLibraryUsageDescription — FrameShift needs this access only to delete photos you took with FrameShift when you choose Delete. It never reads the rest of your library.
NSPhotoLibraryAddUsageDescription — FrameShift saves your photos to your camera roll.
ITSAppUsesNonExemptEncryption — NO
```

Import uses the system photo picker (no broad library read). Saving uses add-only access; read/write is requested only when the user deletes a capture.

---

## Hard Constraints — Do Not Build

- No Photo / Portrait / Video mode switcher
- No full Settings panel on the camera screen (tool drawer for guide toggles is OK; Settings stays on References)
- No EXIF data display in UI (`ReferenceEXIF` is analysis-only; `CaptureInfoSheet` shows date/dimensions/reference thumb only)
- No photo counter — except the session count badge (reversal, see below)
- No account, login, or network calls of any kind
- No third-party dependencies
- No storyboards — SwiftUI only
- No gamification copy

### Documented reversals (supersede earlier “do not build” decisions)

| Reversal | Where |
|---|---|
| First-use guidance — now in-context spotlight tours (onboarding carousel removed) | `Screens/Shared/FirstUseTour.swift` |
| Settings menu (permissions, help, storage, privacy, about) | `Screens/Settings/`, entry from gallery `⋯` |
| Zoom pills, flash, front camera, burst, exposure drag | `CameraService` + `CameraView` |
| Burst count in shutter while holding (exception to "no photo counter") | `ShutterButton` |
| Session saved-photo count badge on the camera thumbnail (UX redesign) | `CameraView.sessionThumbnail`, `AppState.sessionShotIDs` |
| Camera tool drawer replaced by Overlay/Guides mode buttons + `⋯` menu | `CameraView`, `CameraViewModel.AidMode` |
| Live subject coaching (beyond static box) | `LiveVisionAnalyzer`, `CompositionCoach` — the green match-scan flourish was later removed |
| Post-shot recommendations screen | **Not shipped** — the before/after export card and `ExportService` were removed |

Deferred (explicitly post-v1): accounts / paid features — see `accounts-paid-features-prd.md`.

---

## Memory / Image Loading Rules

- Never keep a library of full-resolution `UIImage`s in `@Published` arrays for the app lifetime.
- Restore and in-memory gallery/reference images use `UIImage.downsampled` (ImageIO thumbnails).
- Full-resolution decode only for: Vision analysis on import / analyzerVersion migrate (temporary), person cutout (then downsample + persist PNG), and full-size share / Add to References (from `SessionCaptureCache`).
- Burst makes this non-negotiable — a held shutter can create dozens of shots quickly.

---

## Spec Reference

Historical stitch/PRD docs live under `tasks/` and root `*-prd.md`. Prefer this file + the Swift sources over outdated build-order sketches. When product intent is unclear, check `appstore-readiness-prd.md` and `settings-menu-prd.md`.
