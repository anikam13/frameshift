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
| Export card rendering | CoreGraphics — `ExportService` (dormant: no UI entry point since the gallery export button was removed) |
| Post-capture filters | CoreImage — `FilterService` presets, reference color match, custom presets from picked photos (`FilterPresetSheet` via gallery wand; persisted by `FilterPresetStore`) |
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
    let importedAt: Date
}

struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage          // display-sized; full JPEG on disk
    let capturedAt: Date
    let referenceID: UUID?
    var isFavorite: Bool
    let burstID: UUID?          // shots from one shutter hold share this
    var isBurstBest: Bool       // user-picked cover of its burst group
}
```

Persistence: `ReferenceStore` keeps original import bytes + JSON manifest (per-entry `analyzerVersion`, `spec`, `analysisFailed`) + `{id}.cutout.png`; `CapturedStore` keeps JPEG + manifest (favorites, referenceID). On launch, stores decode **downsampled** images into `AppState` (`UIImage+Downsample`). Full-resolution decode is only for Vision analysis (import / version-mismatch migrate) and export.

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
        │   ├── FrameShiftApp.swift         // @main; onboarding gate; restore on launch
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
        │   ├── CapturedStore.swift
        │   ├── PhotoLibrarySaver.swift     // add-only Photos writes
        │   └── ExportService.swift         // before/after card + share
        ├── Screens/
        │   ├── Root/RootTabView.swift      // shell → CameraView only
        │   ├── Onboarding/                 // mandatory first-launch carousel
        │   ├── References/
        │   ├── Camera/                     // viewfinder + overlays + tool drawer
        │   ├── Library/                    // GalleryPreviewView, GalleryLibraryView (grid), BurstPickerSheet, CaptureInfoSheet
        │   └── Settings/                   // from References gear only
        ├── PrivacyInfo.xcprivacy
        └── Assets.xcassets
```

---

## App Shell & Navigation

- `RootTabView` is just `CameraView()` — the camera *is* the app.
- Mode switching is the bottom **REFERENCE · CAMERA** pill (not a system tab bar).
- Gallery opens from the bottom-left thumbnail → `GalleryPreviewView` fullScreenCover; its top-right grid button opens the full `GalleryLibraryView` grid.
- Settings opens from the References toolbar gear only — not from the camera chrome.
- Camera `⋯` drawer toggles guides for the current session (LEVEL / GRID / CIRCLE / TIPS); defaults live in Settings. It also holds the aspect picker: 4:3 "POSTS" / 16:9 "STORIES" (session-only, no Settings default).

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
- Aspect modes from the tool drawer: 4:3 (full sensor, feed posts) and 16:9
  (9:16 story crop) — the viewfinder box ratio drives the capture crop

Live coaching (when an active reference has a `ShotSpec`): head circle (`SubjectPlacementGuide`), tilt/pitch + level (`TiltPitchGuide` / `LevelIndicator`), tip banner, zoom recommendation. The green "match" scan sweep (`MatchSilhouetteOverlay` / `LiveSilhouetteExtractor`) was removed — coaching signals are the guides + Ready pill + haptics only. `BoundingBoxOverlay` exists but is unused — head circle replaced the static body box in the live UI.

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
offline; the no-network rule holds. Onboarding carousel uses six of those.

### Capture → persist
1. `CameraService.capturePhoto` → cropped `UIImage`
2. `AppState.addCapturedShot` inserts display-sized image, writes JPEG to `CapturedStore`, add-only save via `PhotoLibrarySaver`
3. Photos-denied → one-time non-blocking notice with Settings action

### Export card (removed from UI)
- The gallery's sliders-icon export button was removed — it duplicated the
  share button. `ExportService` remains in the codebase with no entry point.

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

Typography: always `.system(size:weight:design:)` — never custom font names.

Shutter: outer ring 74pt / 2.5pt stroke; inner fill 62pt; 6pt gap.

---

## Permissions (generated Info.plist keys)

```
NSCameraUsageDescription — FrameShift needs camera access to help you recreate reference shots.
NSPhotoLibraryUsageDescription — FrameShift needs photo access to import reference photos.
NSPhotoLibraryAddUsageDescription — FrameShift saves your photos to your camera roll.
ITSAppUsesNonExemptEncryption — NO
```

Import uses the system photo picker (no broad library read). Saving uses add-only access.

---

## Hard Constraints — Do Not Build

- No Photo / Portrait / Video mode switcher
- No full Settings panel on the camera screen (tool drawer for guide toggles is OK; Settings stays on References)
- No EXIF data display in UI (`ReferenceEXIF` is analysis-only; `CaptureInfoSheet` shows date/dimensions/reference thumb only)
- No photo counter
- No account, login, or network calls of any kind
- No third-party dependencies
- No storyboards — SwiftUI only
- No gamification copy

### Documented reversals (supersede earlier “do not build” decisions)

| Reversal | Where |
|---|---|
| Mandatory first-launch onboarding carousel | `Screens/Onboarding/`, `@AppStorage("frameshift.hasCompletedOnboarding")` |
| Settings menu (defaults, storage, permissions, privacy, replay onboarding) | `Screens/Settings/`, entry from References gear |
| Zoom pills, flash, front camera, burst, exposure drag | `CameraService` + `CameraView` |
| Camera tool drawer (session guide toggles) | `CameraToolDrawer` |
| Burst count in shutter while holding (exception to "no photo counter") | `ShutterButton` |
| Live subject coaching (beyond static box) | `LiveVisionAnalyzer`, `CompositionCoach` — the green match-scan flourish was later removed |
| Post-shot recommendations screen | **Not shipped** — before/after export card was gallery-only, then its button was removed as redundant with share (`ExportService` is dormant) |

Deferred (explicitly post-v1): accounts / paid features — see `accounts-paid-features-prd.md`.

---

## Memory / Image Loading Rules

- Never keep a library of full-resolution `UIImage`s in `@Published` arrays for the app lifetime.
- Restore and in-memory gallery/reference images use `UIImage.downsampled` (ImageIO thumbnails).
- Full-resolution decode only for: Vision analysis on import / analyzerVersion migrate (temporary), person cutout (then downsample + persist PNG), and export card generation (load from store by id).
- Burst makes this non-negotiable — a held shutter can create dozens of shots quickly.

---

## Spec Reference

Historical stitch/PRD docs live under `tasks/` and root `*-prd.md`. Prefer this file + the Swift sources over outdated build-order sketches. When product intent is unclear, check `appstore-readiness-prd.md` and `settings-menu-prd.md`.
