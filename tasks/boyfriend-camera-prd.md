# Boyfriend Camera — Product Requirements Document
**Version:** 0.1 (MVP)
**Status:** Draft
**Last Updated:** June 2026

---

## 1. Problem Statement

Most people take mediocre photos of their partners — not because they lack taste, but because they lack spatial awareness in the moment. They don't know how far to stand, how to hold the camera, where the light is coming from, or how to frame the shot. Existing solutions are either too complex (Halide, ProCamera) or too passive (native camera grid). No app closes the feedback loop in real time, in a beginner-friendly way, around the specific use case of photographing someone you're with.

---

## 2. Target User

**Primary:** People who regularly photograph a significant other and are frustrated by the results — not photographers, not content creators, not professionals. Users who know what a good photo looks like but don't know how to take one.

**Platform:** iOS only, iPhone 12 and newer (required for Vision framework performance and LiDAR availability on Pro models).

---

## 3. Goals

- Ship a v1 to the App Store that solves one thing exceptionally well: helping a beginner take a noticeably better photo of their partner using a reference as a guide
- Establish a shareable output loop (before/after) that drives organic growth
- Validate willingness to pay before building v2

---

## 4. Non-Goals (v1)

The following are explicitly out of scope for the initial release:

- Ghost/transparency overlay of reference photo
- Real-time pose detection via computer vision
- Android support
- Social feed or in-app sharing between users
- AI-generated shot guidance (static guidance only in v1)
- User-submitted reference photos
- Video mode

---

## 5. Core Features

### 5.1 Reference Selection & Analysis
**What it is:** The user picks a reference photo before entering the camera. The app analyzes it once and extracts a shot spec that drives all real-time guidance.

**Flow:**
1. On launch, user is prompted to pick a reference from the curated starter library or import from camera roll
2. App runs Vision framework analysis on the selected reference
3. Extracted shot spec includes:
   - Subject bounding box as % of total frame (target framing)
   - Camera tilt angle (target level)
   - Estimated subject distance (near / mid / far, derived from subject size)
   - Light direction (front-lit, side-lit, backlit — derived from highlight/shadow distribution)
4. App surfaces 2–3 suggested poses from the static pose library based on shot type
5. User is shown a brief setup summary screen before entering the live camera

**Notes:**
- Analysis runs once on selection, not continuously. Keeps the live camera phase lightweight.
- Reference image is never uploaded or stored beyond the session unless the user saves it.

---

### 5.2 Pose Suggestion (Setup Phase)
**What it is:** Before the user opens the camera, the app suggests 2–3 poses from a curated static library that fit the detected shot type. User shows the pose card to their partner before shooting.

**Pose library (v1 scope — ~20–30 poses):**
- Categories: standing, seated, candid, over-shoulder, walking, leaning
- Each pose card shows: illustration or photo reference, 1-line direction ("turn slightly away, look back over shoulder"), and applicable shot types

**Notes:**
- Poses are not detected or evaluated in real time. This is intentional — pose guidance is a setup step, not a live feedback loop.
- No computer vision on the live feed for pose. This is a v2 feature if validated.

---

### 5.3 Live Shoot Mode
**What it is:** The real-time camera experience. Lightweight — compares the live frame against the pre-extracted shot spec and surfaces directional nudges. Does not re-run Vision analysis on every frame.

**Real-time feedback signals:**

| Signal | Detection Method | Output |
|---|---|---|
| Subject framing | Subject bounding box vs. target % | "Step back" / "Move closer" |
| Camera tilt | CoreMotion gyroscope | Persistent level indicator + haptic when level |
| Camera height | Face detection via Vision | "Raise the camera" / "Lower the camera" |
| Light direction | Frame luminance distribution | "Turn your partner toward the light" warning |
| Zoom recommendation | Subject size + reference focal length estimate | Suggest 0.5x / 1x / 2x once on session start |

**UI principles:**
- Feedback is directional and non-verbal where possible (arrows, indicators) — not a stream of text overlays
- Only one active nudge shown at a time, prioritized by severity (backlight warning > framing > tilt > height)
- Haptic feedback for: reaching level tilt, reaching target framing distance
- Grid is included as baseline infrastructure, always visible, not a headline feature

---

### 5.4 Before/After Export Card
**What it is:** After taking a photo, a one-tap option to generate a shareable side-by-side card showing the reference photo next to the result.

**Purpose:** This is the distribution mechanic. A before/after of "photo someone took of me vs. what I got using this app" is a natural TikTok and Instagram unit.

**Specs:**
- Square or 9:16 format options
- Minimal branding (small wordmark, not intrusive)
- Exports directly to camera roll or share sheet
- Does not require account or login

---

## 6. Technical Architecture

### Stage 1 — Reference Analysis (runs once)
- **Framework:** Apple Vision + Core Image
- **Inputs:** Selected reference photo
- **Outputs:** Shot spec object (bounding box %, tilt, distance estimate, light direction)
- **Performance:** Can be heavier compute — runs once on photo selection, not in camera loop

### Stage 2 — Live Measurement (runs continuously, must be lightweight)
- **Framework:** CoreMotion (tilt), Vision (face detection for height), AVFoundation (camera feed)
- **Logic:** Compares live frame metrics against pre-computed shot spec
- **Target:** < 100ms feedback latency on iPhone 12+
- **No full Vision model inference on live frames** — subject detection only (not pose, not segmentation)

### Other
- **Minimum deployment target:** iOS 16, iPhone 12
- **Camera permissions:** `NSCameraUsageDescription` required
- **Photo library permissions:** `NSPhotoLibraryUsageDescription` for reference import and export
- **No backend required for v1** — fully on-device

---

## 7. User Flow (End to End)

```
Launch app
  → Onboarding (first launch only, 3 screens max)
  → Reference selection screen
      → Browse curated library  OR  Import from camera roll
  → Reference analysis (loading state, ~1–2 seconds)
  → Setup screen
      → Shot spec summary (light, distance, tilt targets)
      → 2–3 pose suggestions
      → "Start shooting" CTA
  → Live camera
      → Real-time nudges active
      → Grid visible
      → Shutter button
  → Post-shot screen
      → Keep / Retake / Export before/after card
```

---

## 8. Curated Reference Library (v1 Scope)

The starter library ships with ~30 reference photos covering the most common beginner use cases:

- Outdoor portrait (golden hour, front-lit)
- Cafe / indoor ambient light
- Street / urban background
- Beach / open sky
- Candid walking shot
- Seated / relaxed
- Over-shoulder / looking back

Library expands in v2. User-submitted references are a v2 feature.

---

## 9. Monetization (v1 hypothesis)

- **Free tier:** Access to 5 curated reference photos, core live guidance features
- **Pro ($4.99/month or $29.99/year):** Full reference library, unlimited camera roll imports, pose library, before/after export card
- **Hypothesis to validate:** Are users willing to pay for the library and export, or does the free tier convert on its own?

---

## 10. Success Metrics (90 days post-launch)

| Metric | Target |
|---|---|
| App Store downloads | 5,000 |
| D7 retention | > 20% |
| Before/after exports | > 30% of sessions |
| Pro conversion | > 5% of active users |
| App Store rating | > 4.5 stars |

---

## 11. Open Questions

1. **Reference library sourcing:** License stock photos, commission original shots, or use Creative Commons? Licensing cost needs to be resolved before build.
2. **Onboarding flow:** How much does a first-time user need to understand before the camera is useful? Needs usability testing assumption baked into build.
3. **Pose illustration style:** Photo reference vs. illustrated silhouette? Illustrated is safer from a rights perspective and more universally applicable across body types.
4. **Zoom recommendation timing:** Surface once at session start based on reference, or re-surface if user manually changes zoom during shoot?
5. **iPhone 12 floor:** Confirm Vision framework face detection performance is acceptable on A14 chip before committing to minimum deployment target.

---

## 12. v2 Backlog (Do Not Build Now)

- Real-time pose detection via Vision body pose API
- AI-generated shot guidance from reference (dynamic Position / Camera / Environment tabs)
- Android port
- In-app reference community / sharing
- Video mode
- Integration with Instagram Saves for reference import
