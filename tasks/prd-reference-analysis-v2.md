# PRD: Reference Analysis v2 — Head Bounds & Camera Tilt

**Product:** Boyfriend Camera (iOS 16+, SwiftUI, on-device only)  
**Status:** Ready for implementation  
**Priority:** Highest-leverage product change (Phase 1). Live face matching is Phase 2 (`tasks/prd-face-in-circle-framing.md`).

---

## 1. Introduction

When a user imports a reference photo, the app runs `VisionAnalyzer` once and stores a `ShotSpec`. Everything on the camera screen — **head circle**, **tilt guide**, **zoom recommendation**, **ghost overlay** — derives from that analysis.

**Today that analysis is too weak:**

| Output | Current method | User-visible problem |
|--------|----------------|----------------------|
| Head circle | Pose nose/neck/eyes + magic multipliers | Circle too small or misaligned vs actual head (forehead/chin not wrapped) |
| `targetPitch` | Heuristic: subject Y position, focal length guess | Tilt guide chases a fake target; doesn't match how reference was shot |
| `targetRoll` | `VNDetectHorizonRequest` scene angle | Often OK for roll, but conflated with image content tilt |
| Zoom | EXIF focal length or body fill % | Acceptable; keep and refine |

**This PRD** upgrades **import-time reference analysis** so stored targets are accurate. Live coaching (Phase 2) then compares the camera to trustworthy reference data.

**Principle:** Fix the target before fixing the tracker.

---

## 2. Goals

- **G1:** Head circle on camera **wraps the subject's full head** in the reference (forehead → chin), not just eyes/nose.
- **G2:** `targetPitch` reflects **how tilted the reference camera was** (up/down at subject), not only "subject is high in frame."
- **G3:** `targetRoll` remains meaningful for horizon alignment; clarify separation from pitch.
- **G4:** Analysis runs once on import (<3 s per photo on iPhone 12+); no network.
- **G5:** Re-import or schema bump invalidates old specs cleanly; `UIImage.upright()` preserved at import.
- **G6:** Phase 2 (live face-in-circle) can consume stored head bounds without recomputing geometry.

---

## 3. Non-Goals (this PRD)

- Live camera face tracking (see Phase 2 PRD).
- Multi-subject reference selection.
- ML model training or cloud inference.
- 3D pose / depth reconstruction.
- Automatic reference photo "straightening" or re-cropping.
- Changing tilt/roll **UI** behavior (guides already exist; this PRD fixes **targets**).

---

## 4. Current Architecture

### 4.1 Import pipeline

```
PhotosPicker → ReferencesViewModel.importPhotos
  → UIImage.upright()                    // Extensions/UIImage+Upright.swift
  → VisionAnalyzer.analyze(image:data:)    // async on background
  → ShotSpec stored on ReferencePhoto
```

### 4.2 Key files

| File | Role |
|------|------|
| `Services/VisionAnalyzer.swift` | All reference analysis today |
| `Models/ShotSpec.swift` | `headCircle(in:)` computed from landmarks at render time |
| `Screens/Camera/SubjectPlacementGuide.swift` | Draws circle from `spec.headCircle(in:)` |
| `Screens/Camera/TiltPitchGuide.swift` | Live pitch vs `targetPitch` |
| `Services/MotionService.swift` | Live `devicePitch` / `deviceRoll` (gravity-based) |
| `Extensions/AspectFillMapper.swift` | `ImageContentMapper` fit/fill mapping |

### 4.3 Current `headCircle` logic (to replace)

```swift
// ShotSpec.swift — heuristic from pose, not face bounds
eyeSpan * 0.82, forehead = eyeMid.y - eyeSpan * 0.38, chin = nose + neckLen * 0.52
```

Observed on device: circle sits on brows/nose; does not bound full head.

### 4.4 Current `targetPitch` logic (to replace)

```swift
// VisionAnalyzer.estimatePitch — NOT true camera pitch
// - ultrawide EXIF → -0.08
// - horizon angle * 0.6
// - else subject centerY buckets: high → +0.12, low → -0.10
```

Live `TiltPitchGuide` compares `devicePitch` to this value — weak correlation to reference shot tilt.

### 4.5 What already works (keep)

- Body pose landmarks for ghost alignment context.
- `recommendedZoom` from EXIF + body fill (tune, don't rewrite).
- `VNDetectHorizonRequest` for scene roll (refine, don't remove).
- `referenceSize` + aspect-fit mapping for overlay.

---

## 5. User Stories — Phase 1 (Reference Analysis v2)

### US-101: Face-based head bounds on reference import
**Description:** As a user, I want the head circle to match the subject's actual head in my reference photo so I know exactly where to place my face.

**Acceptance Criteria:**
- [ ] On import, run `VNDetectFaceRectanglesRequest` on reference (after `upright()`).
- [ ] If face found: compute head circle from face rect + padding (see FR-1).
- [ ] If no face: fall back to improved pose-based circle (FR-2), then upper-body box fallback.
- [ ] Store **`headCenterX`**, **`headCenterY`**, **`headRadius`** in `ShotSpec` (normalized 0–1, UIKit origin) — authoritative at import time.
- [ ] `SubjectPlacementGuide` uses stored head fields; `headCircle(in:)` becomes mapper-only (no heuristic radius math).
- [ ] Visual check: circle wraps forehead and chin on 3 test references (close-up, medium, slight profile).
- [ ] Build passes; iOS 16+; no third-party deps.

---

### US-102: Optional face landmarks for tighter bounds
**Description:** As a user, I want the tightest accurate head circle when the reference face is clearly visible.

**Acceptance Criteria:**
- [ ] When `VNDetectFaceLandmarksRequest` succeeds, refine circle using contour or medianLine (forehead/chin extremes).
- [ ] Landmark path preferred over raw face rect when confidence > threshold.
- [ ] Profile/partial face falls back to face rect + asymmetric padding (FR-3).
- [ ] Document which Vision requests run in single `handler.perform([...])` batch for performance.

---

### US-103: Reference camera pitch (`targetPitch`) inference
**Description:** As a user, I want the tilt guide to match the up/down angle of the reference shot so I tilt my phone the same way the original photo was taken.

**Acceptance Criteria:**
- [ ] Replace `estimatePitch` heuristic with **tiered pitch pipeline** (FR-4).
- [ ] `targetPitch` is in **radians**, same sign convention as `MotionService.pitch` (positive = camera tilted up / top of phone toward user in portrait).
- [ ] On 3 reference photos with obvious tilt (shooting up at subject, straight-on, shooting down), tilt guide direction matches intuitive re-shoot angle.
- [ ] Store optional `pitchConfidence: Double` (0–1) in `ShotSpec`; if low, `targetPitch` defaults to `0` and tilt guide hidden or relaxed (FR-8).

---

### US-104: Reference roll (`targetRoll`) refinement
**Description:** As a user, I want horizon/roll coaching to reflect the reference photo's level, not confuse scene tilt with phone roll.

**Acceptance Criteria:**
- [ ] Keep `VNDetectHorizonRequest` as primary roll signal.
- [ ] When horizon confidence low or |angle| < noise floor, `targetRoll = 0`.
- [ ] Document: `targetRoll` is **in-image scene roll**; user matches by rotating phone so live roll equals `targetRoll` (existing `LevelIndicator` behavior).
- [ ] Do not mix pitch into roll.

---

### US-105: EXIF enrichment for zoom and tilt hints
**Description:** As a developer, I want EXIF metadata to inform zoom and pitch when available.

**Acceptance Criteria:**
- [ ] Parse EXIF: focal length (35mm equiv), orientation, image dimensions (existing partial impl).
- [ ] Add parsing for **`kCGImagePropertyTIFFOrientation`** alignment with `upright()` — post-upright EXIF is always `.up`.
- [ ] If Apple maker note / auxiliary EXIF fields exist for capture angle, read them (graceful nil if absent).
- [ ] EXIF ultrawide (`focal < 20`) sets pitch prior, not hard-coded only.
- [ ] Log (debug only) which tier set `targetPitch` for tuning.

---

### US-106: ShotSpec schema migration
**Description:** As a developer, I need a clear schema so old references re-analyze correctly.

**Acceptance Criteria:**
- [ ] Add fields: `headCenterX`, `headCenterY`, `headRadius`, `pitchConfidence`, optional `headBoundsSource: enum { face, landmarks, pose, fallback }`.
- [ ] Existing references without new fields: re-run `VisionAnalyzer` on next app launch or on first camera open (pick one; document).
- [ ] `ShotSpec` remains `Equatable`; update any switch exhaustiveness.
- [ ] No persistence to disk in v1 — in-memory re-analysis on missing fields is sufficient.

---

### US-107: Device verification — reference analysis
**Description:** As QA, verify import analysis before Phase 2 live work.

**Acceptance Criteria:**
- [ ] Import reference from camera roll; open camera; head circle matches ghost subject head.
- [ ] Import low-angle reference; tilt guide indicates tilt up to match (lines/chevrons directionally correct).
- [ ] Import high-angle reference; opposite tilt behavior.
- [ ] Import photo with no detectable face; app still usable with fallback circle (no crash).
- [ ] Re-import same photo replaces spec; circle updates.

---

## 6. Functional Requirements

### 6.1 Head bounds

- **FR-1 (face rect):** From `VNDetectFaceObservation.boundingBox` (Vision bottom-left → UIKit top-left).  
  - `paddingTop = height * 0.35` (forehead/hair)  
  - `paddingBottom = height * 0.18` (chin)  
  - `paddingHorizontal = width * 0.12`  
  - Circle: center = padded rect center; radius = `max(paddedWidth, paddedHeight) / 2`  
  - Constants named; tunable in one struct `HeadBoundsEstimator`.

- **FR-2 (pose fallback):** If no face: use nose + ears/eyes from `VNDetectHumanBodyPoseRequest` with **wider** multipliers than today (forehead 1.2× eye-to-nose, chin 0.65× nose-to-neck). Prefer pose over body box.

- **FR-3 (profile):** If face rect aspect ratio > 1.4 (wide), increase radius on narrow side by 15%.

- **FR-4 (stored authority):** `ShotSpec.headCircle(in: containerSize)` maps stored normalized center/radius via `ImageContentMapper` only — **no runtime heuristic recompute**.

### 6.2 Pitch inference (tiered pipeline)

Evaluate in order; first tier with sufficient confidence wins:

| Tier | Source | `targetPitch` | Min confidence |
|------|--------|---------------|----------------|
| T1 | EXIF / maker notes capture angle | Direct radians if field exists | Field present |
| T2 | Shoulder line slope + horizon | `atan2(shoulderDy, shoulderDx)` combined with subject vertical offset | Pose shoulders conf > 0.5, horizon optional |
| T3 | Subject vertical position in frame | Map `centerY` linearly: top third → `+0.12`, bottom third → `-0.10`, interpolate | Always (low conf 0.3) |
| T4 | Ultrawide focal < 20mm | `-0.06` to `-0.10` | EXIF only |

- **FR-5:** Shoulder slope: angle of line `(leftShoulder → rightShoulder)` relative to horizontal in **upright image**. Positive pitch prior when shoulders slope such that camera was above subject (derive sign on device once, document in code).

- **FR-6:** Combine T2 signals:  
  `pitch = w1 * shoulderPitch + w2 * verticalOffsetPitch` with `w1 + w2 = 1`; default `w1 = 0.6`.

- **FR-7:** `pitchConfidence`: T1=0.95, T2=0.75, T3=0.35, T4=0.5.

- **FR-8:** If `pitchConfidence < 0.4`, set `targetPitch = 0` and `CameraView` hides tilt pitch lines (roll leveler still shown). Prevents chasing noise.

### 6.3 Roll

- **FR-9:** `targetRoll = horizon.angle` when `|angle| > 0.015` rad; else `0`.
- **FR-10:** Store `rollConfidence` from Vision observation if available; else binary from threshold.

### 6.4 Zoom (minor refinement)

- **FR-11:** Keep existing `inferZoom`; optionally bias using face-to-frame ratio when face bounds available (face height / image height).

### 6.5 Performance

- **FR-12:** Single `VNImageRequestHandler.perform` batch per import: body, upper body, horizon, pose, **face rect**, **face landmarks** (landmarks optional if face rect fails).
- **FR-13:** Target < 2 s analysis on iPhone 12 for 12MP image.

### 6.6 Coordinate space

- **FR-14:** All stored normalized values are in **upright image space** (after `UIImage.upright()`), UIKit top-left origin, matching existing landmark convention.
- **FR-15:** `referenceSize` = upright `image.size`.

---

## 7. Phase 2 — Live Matching (separate PRD)

After Phase 1 ships, implement `tasks/prd-face-in-circle-framing.md`:

- Live `VNDetectFaceRectanglesRequest` on camera frames.
- Compare live head to **stored** `ShotSpec` head center/radius in viewfinder-normalized space.
- `framingOK`, Move closer/back, Step left/right use head — not body rect.

**Dependency:** Phase 2 requires Phase 1 stored head bounds; do not ship Phase 2 without US-101.

---

## 8. Design Considerations

- Head circle visual unchanged (white stroke, yellow when locked/satisfied).
- Ghost overlay stays aspect-fit; head circle uses same mapping.
- Tilt guide (`TiltPitchGuide`) unchanged UI — only `targetPitch` input improves.
- No new colors or copy required for Phase 1.

---

## 9. Technical Sketch

### 9.1 `ShotSpec` additions

```swift
struct ShotSpec: Equatable {
    // ... existing fields ...

    // Authoritative head guide (normalized upright image, UIKit origin)
    let headCenterX: CGFloat
    let headCenterY: CGFloat
    let headRadius: CGFloat
    let headBoundsSource: HeadBoundsSource

    let targetPitch: Double?      // existing, semantics improved
    let pitchConfidence: Double // 0–1

    enum HeadBoundsSource: String, Equatable {
        case faceRect, faceLandmarks, pose, fallback
    }
}
```

### 9.2 New helper

```swift
enum HeadBoundsEstimator {
    static func estimate(
        face: VNFaceObservation?,
        landmarks: VNFaceLandmarks2D?,
        pose: VNHumanBodyPoseObservation?,
        upperBody: CGRect
    ) -> (center: CGPoint, radius: CGFloat, source: ShotSpec.HeadBoundsSource)
}
```

### 9.3 `VisionAnalyzer.analyze` outline

```swift
try handler.perform([
    bodyRequest, upperRequest, horizonRequest, poseRequest,
    faceRectRequest, faceLandmarksRequest
])
let head = HeadBoundsEstimator.estimate(...)
let pitch = PitchEstimator.estimate(
    exif: props, horizon: horizon, pose: pose, body: body, head: head
)
```

Extract `PitchEstimator` to own file if `VisionAnalyzer` grows.

---

## 10. Success Metrics

- **SM-1:** In blind review of 10 reference imports, head circle rated "wraps full head" ≥ 8/10.
- **SM-2:** Tilt guide direction matches reference intent ≥ 8/10 on 6 references with obvious up/down shoot angles.
- **SM-3:** Analysis time p95 < 2.5 s on iPhone 12.
- **SM-4:** Zero crashes on face-less reference imports.
- **SM-5:** Phase 2 framing tips agree with circle in ≥ 8/10 live setups (measured after Phase 2).

---

## 11. Test References (build a small set)

| ID | Description | Expected head | Expected pitch |
|----|-------------|---------------|----------------|
| R1 | Close-up selfie, face centered | Tight circle on full head | ~0 |
| R2 | Low angle, subject against sky | Circle on head | Positive (tilt up to match) |
| R3 | High angle, looking down at subject | Circle on head | Negative |
| R4 | Medium shot, person at door (user's test scene) | Circle includes hair + chin | Slight per geometry |
| R5 | Pinterest crop, no EXIF | Fallback tiers; no crash |
| R6 | Ultrawide 0.5× look | Circle OK; pitch prior negative |

---

## 12. Open Questions

| # | Question | Default |
|---|----------|---------|
| OQ-1 | Re-analyze all references on app upgrade? | Yes, on first access if `headRadius` missing |
| OQ-2 | Hide tilt guide when `pitchConfidence` low? | Yes (FR-8) |
| OQ-3 | `VNDetectFaceLandmarksRequest` on every import? | Yes when face rect succeeds |
| OQ-4 | Keep computed `headCircle(in:)` for backward compat? | Delegate to stored fields only |
| OQ-5 | Pitch sign validation | Calibrate once on device; document in `PitchEstimator` |

---

## 13. Implementation Order

1. Extend `ShotSpec` + `HeadBoundsEstimator` + face requests in `VisionAnalyzer`.
2. Update `SubjectPlacementGuide` / `headCircle(in:)` to use stored bounds.
3. Extract `PitchEstimator`; replace `estimatePitch`.
4. Add `pitchConfidence`; wire `TiltPitchGuide` hide when low confidence.
5. Re-analysis path for legacy references missing new fields.
6. Device QA with test set R1–R6.
7. **Then** start Phase 2 live PRD.

---

## 14. Definition of Done

- US-101 through US-107 acceptance criteria met.
- FR-1 through FR-15 implemented or deferred with code comment.
- No third-party dependencies.
- Phase 2 PRD referenced but not implemented in this scope.

---

## 15. Agent prompt stub

> Implement **PRD: Reference Analysis v2** (`tasks/prd-reference-analysis-v2.md`).  
> Phase 1 only. Read `VisionAnalyzer.swift`, `ShotSpec.swift`, `SubjectPlacementGuide.swift`, `TiltPitchGuide.swift`, `UIImage+Upright.swift`.  
> Add face-based head bounds at import; replace pitch heuristic with tiered `PitchEstimator`; store `headCenterX/Y`, `headRadius`, `pitchConfidence` on `ShotSpec`.  
> Do not implement live face tracking (Phase 2). Verify on device with references R1–R4.
