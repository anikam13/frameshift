# PRD: Face-in-Circle Framing Coaching

**Product:** Boyfriend Camera (iOS 16+, SwiftUI, on-device only)  
**Status:** Ready for implementation  
**Author context:** Core camera coaching loop is working. This PRD closes the largest remaining mismatch between what the user **sees** (head circle overlay) and what the coach **measures** (full-body Vision rect).

---

## 1. Introduction

Boyfriend Camera helps users recreate reference photos in real time. On import, Vision analyzes the reference and produces a `ShotSpec` with pose landmarks. The camera screen draws a **head circle** (`SubjectPlacementGuide`) showing where the subject's face should sit.

Today, live framing coaching — **"Move closer"**, **"Move back"**, **"Step left/right"**, and **`framingOK`** (which dismisses the head circle) — is driven by **`VNDetectHumanRectanglesRequest`** (full-body bounding box). That box often disagrees with the head circle the user is actually trying to match.

**This feature** replaces body-rect framing logic with **head/face-aligned** comparison: the live detected face/head is compared to the reference head circle in **shared viewfinder coordinates**, so tips and guide dismissal match the overlay.

---

## 2. Goals

- **G1:** `framingOK` and distance/horizontal tips reflect **head position and size** vs the reference head circle, not full-body height.
- **G2:** When the user's face is inside the reference head circle (within tolerance), the head circle **fades out** and stays out (with hysteresis).
- **G3:** Coaching tips (**Move closer/back**, **Step left/right**) feel correct on a physical device in portrait, back camera, with a single subject.
- **G4:** No regression to zoom, tilt, roll, or lighting coaching (unchanged).
- **G5:** Remain fully on-device; no new dependencies; ~1 fps live analysis budget preserved.

---

## 3. Background — Current Architecture

### 3.1 Key files (read these first)

| File | Role |
|------|------|
| `BoyfriendCamera/Services/LiveVisionAnalyzer.swift` | Live `VNDetectHumanRectanglesRequest` @ ~1 fps |
| `BoyfriendCamera/Services/CompositionCoach.swift` | `framingOK`, tips, hysteresis thresholds |
| `BoyfriendCamera/Screens/Camera/CameraViewModel.swift` | Wires live analysis → coach; maps coords via `ImageContentMapper` |
| `BoyfriendCamera/Models/ShotSpec.swift` | Reference landmarks; `headCircle(in:)` for overlay |
| `BoyfriendCamera/Screens/Camera/SubjectPlacementGuide.swift` | Draws head circle; reads `isSatisfied: framingOK` |
| `BoyfriendCamera/Extensions/AspectFillMapper.swift` | `ImageContentMapper` — aspect-fit/fill coordinate mapping |
| `BoyfriendCamera/Services/VisionAnalyzer.swift` | Reference analysis on import (body pose + landmarks) |

### 3.2 Coordinate pipelines (already implemented)

**Reference head circle** (overlay target):
- Landmarks normalized 0–1 in reference image space (UIKit origin).
- Mapped to viewfinder with **aspect-fit** (`ImageContentMapper.mode = .fit`) — matches ghost overlay.
- `ShotSpec.headCircle(in: viewfinderSize)` → `(center: CGPoint, radius: CGFloat)` in **points**.

**Live body rect** (current coaching input — to be replaced for framing):
- Vision on camera buffer with orientation `.right` (back) / `.leftMirrored` (front).
- Normalized 0–1 in oriented buffer space.
- Mapped to viewfinder with **aspect-fill** (`mode = .fill`) — matches `AVCaptureVideoPreviewLayer` (`videoGravity = .resizeAspectFill`).

`CameraViewModel.updateViewfinderSize(_:)` reports viewfinder size from `GeometryReader` in `CameraView`.

### 3.3 Current framing logic (to replace)

In `CompositionCoach`:
- `referenceSubject` = full-body rect from `ShotSpec.subjectRect(inViewfinder:)` (aspect-fit).
- `liveSubject` = full-body rect from `LiveVisionAnalyzer` (aspect-fill).
- Compare `live.height` vs `ref.height` → Move closer/back.
- Compare `live.midX` vs `ref.midX` → Step left/right.
- Thresholds: satisfy `0.10`, unsatisfy `0.14` (normalized viewfinder units).

**Problem:** User aligns face to circle; coach still says "Move closer" because body box differs.

---

## 4. User Stories

### US-001: Live face detection on camera frames
**Description:** As a user, I want the app to detect my subject's face in the live viewfinder so framing coaching reflects what I'm lining up.

**Acceptance Criteria:**
- [ ] `LiveVisionAnalyzer` runs `VNDetectFaceRectanglesRequest` (or `VNDetectHumanBodyPoseRequest` face landmarks if more stable) on throttled frames (~1 fps).
- [ ] Detection runs on `videoQueue`; results published on main thread.
- [ ] Back camera uses orientation `.right`; front camera uses `.leftMirrored` (match existing body detection).
- [ ] When no face detected, framing tips do not claim `framingOK`; behavior documented in FR-6.
- [ ] Build succeeds; no new third-party dependencies.

---

### US-002: Map live face to viewfinder coordinates
**Description:** As a developer, I need live face geometry in the same coordinate space as the head circle so comparisons are valid.

**Acceptance Criteria:**
- [ ] Live face rect (or center + radius) mapped through `ImageContentMapper.viewfinderNormalized` with **aspect-fill** and oriented `contentSize` (same as existing `liveSubjectInViewfinder()`).
- [ ] Reference target head circle converted to comparable form: center `(x, y)` and `radius` in **viewfinder-normalized** 0–1 space (divide point coords and radius by viewfinder width/height; use min dimension for radius scale).
- [ ] Mapping helpers live in one place (extend `ShotSpec`, `ImageContentMapper`, or small `FramingMapper` struct) — not duplicated in coach.
- [ ] Unit-testable pure functions for normalize/denormalize where possible.

---

### US-003: Head-aligned framing satisfaction (`framingOK`)
**Description:** As a user, I want the head circle to disappear when my subject's face is correctly placed inside it.

**Acceptance Criteria:**
- [ ] `framingOK` true when live face circle is sufficiently aligned with reference head circle (see FR-3).
- [ ] Hysteresis applied (match existing coach pattern): enter OK at tight threshold, exit OK at looser threshold — no flicker.
- [ ] `SubjectPlacementGuide` still fades out when `compositionProgress.framingOK` (no UI change required if coach flag is correct).
- [ ] Zoom, tilt, roll, lighting `*OK` flags unchanged.

---

### US-004: Distance tips from head size
**Description:** As a user, I want "Move closer" / "Move back" to mean my subject's **face size** vs the reference head circle, not full-body height.

**Acceptance Criteria:**
- [ ] **Move closer** when live face radius (or height) is **smaller** than reference by more than unsatisfy threshold.
- [ ] **Move back** when live face radius is **larger** than reference by more than unsatisfy threshold.
- [ ] Tips suppressed when `framingOK` is true.
- [ ] Tip priority order unchanged: lighting → zoom → framing (distance/horizontal) → level.

---

### US-005: Horizontal tips from head position
**Description:** As a user, I want "Step left" / "Step right" when the face center is off horizontally relative to the head circle center.

**Acceptance Criteria:**
- [ ] Compare live face **center X** vs reference head circle **center X** in viewfinder-normalized space.
- [ ] **Step right** when live center is left of target (user should move camera right so subject moves right in frame — verify sign on device once).
- [ ] Thresholds use same satisfy/unsatisfy pattern as vertical.
- [ ] Only shown when distance axis is within unsatisfy threshold (prioritize one axis per tip, or distance first then horizontal — match current coach ordering).

---

### US-006: Device verification
**Description:** As a QA tester, I need on-device confirmation that coaching matches the head circle.

**Acceptance Criteria:**
- [ ] Back camera, portrait, single person: placing face in circle clears head guide within ~2 s.
- [ ] Stepping closer enlarges face; "Move back" appears when face exceeds circle size.
- [ ] Stepping away shrinks face; "Move closer" appears when face is smaller than circle.
- [ ] Panning subject left/right triggers correct horizontal tip.
- [ ] No face in frame: head circle remains; no false `framingOK`.
- [ ] Document results in PR/commit notes (screenshots optional via pymobiledevice3).

---

## 5. Functional Requirements

### Detection

- **FR-1:** Add live face detection alongside (or replacing) body rect **for framing only**. Lighting estimation may continue using body rect or face rect region — do not break `lightingOK`.

- **FR-2:** Prefer **`VNDetectFaceRectanglesRequest`** for live face box. Convert Vision box (bottom-left origin) to UIKit normalized (top-left) identically to body rect handling.

- **FR-3:** Derive live **head circle** from face rect:
  - **Center:** face bounding box center.
  - **Radius:** `max(width, height) / 2 * 1.15` (slight padding so circle wraps head like reference guide). Tune on device; constant must be named and documented.

  **Alternative (if face box too tight):** Use `VNDetectHumanBodyPoseRequest` nose + eyes on live frames to mirror `ShotSpec.headCircle` construction — higher cost, better match to reference.

### Comparison (viewfinder-normalized)

- **FR-4:** Reference target from existing `ShotSpec.headCircle(in: viewfinderSize)` converted to normalized:
  ```text
  refCenterX = center.x / viewfinderWidth
  refCenterY = center.y / viewfinderHeight
  refRadius  = radius / min(viewfinderWidth, viewfinderHeight)
  ```

- **FR-5:** Live face converted to same normalized center + radius after aspect-fill mapping.

- **FR-6:** **No face detected:** `framingOK = false`; do not emit distance/horizontal tips (or optionally keep last-known with timeout — default: no timeout, require fresh detection).

- **FR-7:** **Multiple faces:** Use largest face by area (document in code comment).

### Thresholds & hysteresis

- **FR-8:** **Framing satisfied** when ALL hold:
  - `abs(liveCenterX - refCenterX) < positionSatisfy`
  - `abs(liveCenterY - refCenterY) < positionSatisfy` (optional Y — reference is 2D circle; include Y for vertical placement)
  - `abs(liveRadius - refRadius) < sizeSatisfy`

  Suggested starting values (normalized):
  - `positionSatisfy = 0.06` (~6% of viewfinder)
  - `positionUnsatisfy = 0.10`
  - `sizeSatisfy = 0.08`
  - `sizeUnsatisfy = 0.12`

  Use existing `hysteresis(current:wasOK:bad:)` pattern from `CompositionCoach`.

- **FR-9:** **Move closer/back** when `liveRadius - refRadius < -sizeUnsatisfy` / `> sizeUnsatisfy`.

- **FR-10:** **Step left/right** when `liveCenterX - refCenterX` exceeds `positionUnsatisfy` (sign per US-005).

### Integration

- **FR-11:** `CompositionCoach.Input` should accept `referenceHead` and `liveHead` (structs with `center` + `radius` in normalized viewfinder space) instead of full-body `CGRect` for framing. Remove or deprecate body-rect comparison for tips.

- **FR-12:** `CameraViewModel` computes head geometries before `coach.evaluate(...)`. Keep `viewfinderSize` requirement.

- **FR-13:** Do **not** change `VisionAnalyzer` reference import unless adding stored reference head radius for clarity (optional; can compute from landmarks at runtime).

### Performance

- **FR-14:** Max one Vision request bundle per second on live frames (existing throttle). Face + body in same `perform([...])` if lighting still needs body.

### UI

- **FR-15:** No change to head circle drawing unless adding debug overlay (non-goal by default).

- **FR-16:** Tip banner strings remain: `"Move closer"`, `"Move back"`, `"Step left"`, `"Step right"`.

---

## 6. Non-Goals

- **NG-1:** Real-time face **tracking** at 30/60 fps (stay ~1 fps).
- **NG-2:** Re-detecting reference face on live feed (reference is static `ShotSpec` only).
- **NG-3:** Multi-subject coaching ("which person?").
- **NG-4:** Depth / LiDAR distance measurement.
- **NG-5:** Replacing head circle UI with a different visual.
- **NG-6:** Changing zoom/tilt/roll guides or `MotionService`.
- **NG-7:** Post-shot analysis or spam-capture flow changes.
- **NG-8:** Backend, accounts, or analytics.

---

## 7. Design Considerations

- Head circle is **white/yellow** stroke only (`SubjectPlacementGuide`). Coaching is tip banner + guide fade — no new UI required for v1.
- Reference ghost uses aspect-**fit**; live preview uses aspect-**fill**. Reference head and live head must each use the correct mode (already established pattern).
- Face circle on live feed may be **slightly larger** than Vision face rect due to padding factor — must match user mental model of the drawn reference circle.

---

## 8. Technical Considerations

### Suggested data types

```swift
struct HeadCircle: Equatable {
    /// Center in viewfinder-normalized coordinates (0–1).
    let center: CGPoint
    /// Radius as fraction of min(viewfinder width, height).
    let radius: CGFloat
}

extension ShotSpec {
    func referenceHead(inViewfinder size: CGSize) -> HeadCircle { ... }
}
```

### Suggested `CompositionCoach.Input` change

```swift
struct Input {
    let spec: ShotSpec
    let liveHead: HeadCircle?
    let referenceHead: HeadCircle
    // roll, pitch, zoom, lightingScore unchanged
    // Remove liveSubject/referenceSubject CGRect for framing
}
```

### LiveVisionAnalyzer output change

```swift
var onUpdate: ((HeadCircle?, CGRect? /* body for lighting */, Double, CGSize) -> Void)?
```

### Front camera

- Mirroring must be consistent with preview. If horizontal tips are inverted on front camera, apply X-flip in mapped coordinates or use correct `CGImagePropertyOrientation`.

### Debug mode (optional, developer-only)

- Draw live face circle in a different opacity for tuning thresholds — behind `#if DEBUG` only.

---

## 9. Implementation Order

1. Add `HeadCircle` + `ShotSpec.referenceHead(inViewfinder:)`.
2. Extend `LiveVisionAnalyzer` with face detection + publish face rect.
3. Add `CameraViewModel.liveHeadInViewfinder()` mirroring `liveSubjectInViewfinder()` pattern.
4. Refactor `CompositionCoach` framing logic to head circles.
5. On-device tune thresholds (position/size satisfy/unsatisfy).
6. Remove dead body-rect framing code paths if fully unused.
7. Manual QA per US-006.

---

## 10. Success Metrics

- **SM-1:** In 5/5 staged setups (wide/medium/close reference), face placed in circle clears guide without contradictory distance tip.
- **SM-2:** "Move closer/back" direction matches physical step in 5/5 trials.
- **SM-3:** No increase in Vision processing time that stalls preview (>1 fps analysis maintained).
- **SM-4:** Zero regressions on tilt/roll/yellow merge and spam capture flow.

---

## 11. Open Questions

| # | Question | Default if unanswered |
|---|----------|------------------------|
| OQ-1 | Face rect vs body-pose head circle for live? | Start with `VNDetectFaceRectanglesRequest` + padding |
| OQ-2 | Include vertical (Y) position in framingOK? | Yes — 2D center distance |
| OQ-3 | Keep body rect for lighting only? | Yes |
| OQ-4 | Tighten thresholds after user testing? | Ship suggested values, tune in follow-up |
| OQ-5 | Profile / partial face (no eyes on reference)? | Fall back to reference `headCircle` from pose; live face box only |

---

## 12. Reference — Coach Tip Priority (unchanged)

1. Lighting  
2. Zoom  
3. Framing (distance, then horizontal)  
4. Level  

Tilt is visual-only via `TiltPitchGuide` (no text tip).

---

## 13. Test Plan (on-device)

| Scenario | Setup | Expected |
|----------|--------|----------|
| T1 | Medium shot reference, subject at 6 ft | Circle visible; tips guide into circle |
| T2 | Face aligned in circle | `framingOK`, circle fades |
| T3 | Face too small in circle | "Move closer" |
| T4 | Face overflows circle | "Move back" |
| T5 | Face left of circle | "Step right" (verify sign) |
| T6 | No person | No `framingOK`; tips absent or not distance |
| T7 | 0.5× ultrawide | Same behavior, no crash |
| T8 | Front camera | Horizontal tips correct (mirroring) |

---

## 14. Definition of Done

- All US-001 through US-006 acceptance criteria checked.
- FR-1 through FR-16 implemented or explicitly deferred with comment.
- No new dependencies.
- `CLAUDE.md` not required to update in this task.
- Code matches existing style: SwiftUI, on-device Vision, hysteresis coaching, design tokens from `Color+Hex.swift`.

---

## 15. Prompt stub for implementing agent

> Implement **PRD: Face-in-Circle Framing Coaching** (`tasks/prd-face-in-circle-framing.md`).  
> Read `CompositionCoach`, `LiveVisionAnalyzer`, `CameraViewModel`, `ShotSpec.headCircle`, and `ImageContentMapper` first.  
> Replace body-rect framing comparison with head-circle comparison in viewfinder-normalized space.  
> Keep lighting on body or face region; keep zoom/tilt/roll unchanged.  
> Verify on physical iPhone per test plan T1–T8.
