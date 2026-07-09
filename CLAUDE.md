# FrameShift — CLAUDE.md

iOS camera app that helps users recreate reference photos in real time. A user imports reference photos (from Photos — typically saved from Pinterest, Instagram, etc.), the app silently analyzes each one to extract a shot spec, and the live camera screen uses that spec to guide framing (head circle, level/tilt, zoom, coaching tips, optional match silhouette).

No backend. No account. Fully on-device. iOS 17+, iPhone-only.

App identity: product/target `FrameShift`, bundle ID `com.anirudhkamath.frameshift`.

---

## Framework Ownership

| Feature | Framework |
|---|---|
| Camera feed | AVFoundation — AVCaptureSession, AVCaptureVideoPreviewLayer |
| Subject detection on reference | Vision — human/face/pose/horizon batch in `VisionAnalyzer` |
| Live subject / silhouette | Vision — `LiveVisionAnalyzer`, `LiveSilhouetteExtractor`, `PersonSegmenter` |
| Level / pitch | CoreMotion — `MotionService` (roll + pitch) |
| Photo import | PhotosUI — `PhotosPicker` |
| Photo export / save | Photos — PHPhotoLibrary (add-only) |
| Export card rendering | CoreGraphics — `ExportService` |
| Haptics | UIKit — UIImpactFeedbackGenerator |
| UI | SwiftUI throughout |

Do not use third-party dependencies. All required frameworks ship with iOS 17.

---

## Data Models

`ShotSpec` (see `Models/ShotSpec.swift`) is the central object: subject/placement boxes, pose landmarks, head guide, target roll/pitch + confidence, recommended zoom, framing style, reference size. Specs are computed on import (and again on restore), kept in memory only — never serialized.

```swift
struct ReferencePhoto: Identifiable {
    let id: UUID
    let image: UIImage          // display-sized; full bytes stay on disk
    var spec: ShotSpec?
    var personCutout: UIImage?  // ghost overlay; memory only
    var analysisFailed: Bool    // no person/face found
    let importedAt: Date
}

struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage          // display-sized; full JPEG on disk
    let capturedAt: Date
    let referenceID: UUID?
    var isFavorite: Bool
}
```

Persistence: `ReferenceStore` keeps original import bytes + JSON manifest; `CapturedStore` keeps JPEG + manifest (favorites, referenceID). On launch, stores decode **downsampled** images into `AppState` (`UIImage+Downsample`). Full-resolution decode is only for Vision analysis and export.

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
        │   ├── LiveSilhouetteExtractor.swift
        │   ├── PersonSegmenter.swift       // reference ghost cutout
        │   ├── HeadBoundsEstimator.swift
        │   ├── PitchEstimator.swift
        │   ├── RollEstimator.swift         // EXIF attitude → horizon → level
        │   ├── ReferenceEXIF.swift         // analysis-only; never shown in UI
        │   ├── CompositionCoach.swift      // tips + CompositionProgress
        │   ├── CameraService.swift         // session, zoom, flash, front, capture crop
        │   ├── MotionService.swift
        │   ├── ReferenceStore.swift
        │   ├── CapturedStore.swift
        │   ├── PhotoLibrarySaver.swift     // add-only Photos writes
        │   └── ExportService.swift         // before/after card + share
        ├── Screens/
        │   ├── Root/RootTabView.swift      // shell → CameraView only
        │   ├── Onboarding/                 // mandatory first-launch carousel
        │   ├── References/
        │   ├── Camera/                     // viewfinder + overlays + tool drawer
        │   ├── Library/                    // GalleryPreviewView + CaptureInfoSheet
        │   └── Settings/                   // from References gear only
        ├── PrivacyInfo.xcprivacy
        └── Assets.xcassets
```

---

## App Shell & Navigation

- `RootTabView` is just `CameraView()` — the camera *is* the app.
- Mode switching is the bottom **REFERENCE · CAMERA** pill (not a system tab bar).
- Gallery opens from the bottom-left thumbnail → `GalleryPreviewView` fullScreenCover.
- Settings opens from the References toolbar gear only — not from the camera chrome.
- Camera `⋯` drawer toggles guides for the current session (LEVEL / GRID / CIRCLE / TIPS / MATCH); defaults live in Settings.

---

## Camera Capabilities (current)

`CameraService` is beyond the original minimal sketch:

- Multi-lens display zoom (back ~0.5×–6×; front 1×–3×)
- Tap-to-focus + vertical drag exposure bias (`FocusReticle`)
- Flash / screen flash, front/back flip
- Hold-to-burst on shutter
- Captures cropped to the visible preview region

Live coaching (when an active reference has a `ShotSpec`): head circle (`SubjectPlacementGuide`), tilt/pitch + level (`TiltPitchGuide` / `LevelIndicator`), tip banner, zoom recommendation, optional match silhouette. `BoundingBoxOverlay` exists but is unused — head circle replaced the static body box in the live UI.

---

## Key Flows

### Import → analyze
1. `PhotosPicker` → `ReferencesViewModel.importPhotos` / camera REFERENCE-mode picker
2. Photo appears immediately; `VisionAnalyzer.analyze` runs off main actor
3. Spec + person cutout update `AppState`; failures set `analysisFailed`

### Capture → persist
1. `CameraService.capturePhoto` → cropped `UIImage`
2. `AppState.addCapturedShot` inserts display-sized image, writes JPEG to `CapturedStore`, add-only save via `PhotoLibrarySaver`
3. Photos-denied → one-time non-blocking notice with Settings action

### Export card
- From gallery only (sliders icon) when the shot still has a resolvable `referenceID`
- `ExportService.generateCard` + `saveAndShare` (present from topmost VC)

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
| Live subject coaching / match silhouette (beyond static box) | `LiveVisionAnalyzer`, `CompositionCoach`, `MatchSilhouetteOverlay` |
| Post-shot recommendations screen | **Not shipped** — before/after export is gallery-only (`ExportService` via `GalleryPreviewView`) |

Deferred (explicitly post-v1): accounts / paid features — see `accounts-paid-features-prd.md`.

---

## Memory / Image Loading Rules

- Never keep a library of full-resolution `UIImage`s in `@Published` arrays for the app lifetime.
- Restore and in-memory gallery/reference images use `UIImage.downsampled` (ImageIO thumbnails).
- Full-resolution decode only for: Vision analysis (temporary), person cutout (then downsample for ghost), and export card generation (load from store by id).
- Burst makes this non-negotiable — a held shutter can create dozens of shots quickly.

---

## Spec Reference

Historical stitch/PRD docs live under `tasks/` and root `*-prd.md`. Prefer this file + the Swift sources over outdated build-order sketches. When product intent is unclear, check `appstore-readiness-prd.md` and `settings-menu-prd.md`.
