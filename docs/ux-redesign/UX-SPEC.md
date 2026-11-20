# FrameShift — UX Specification

**Status:** Approved product behavior from design conversations, with unresolved details explicitly marked.  
**Goal:** Help people recreate photo compositions using reference imagery, head-position/scale guidance and camera-level feedback, without sacrificing normal photo-taking speed.

## 1. Primary navigation

**Core path:** Reference Gallery -> (curated/imported preview when appropriate) -> Camera -> Session Gallery -> Photo Viewer.

- First-ever launch or no previously chosen reference: open curated Explore gallery.
- Subsequent fresh launch with last-used reference: open Camera directly with that reference.
- Brief app interruption: restore existing view/session rather than creating a new one.
- Camera native back chevron: main reference gallery.
- While session is active, gallery header offers **Resume Camera**.
- Camera reference-picker chevron: bottom sheet; sheet begins compact with favorites/recent and expands to the entire Explore/Yours collection, including filters.
- Switching references updates current camera without ending the shooting session.

## 2. Reference discovery and persistence

### Gallery
- One combined favorite/frequently used horizontal row at top, favorites prioritized and no duplicated images.
- Explore / Yours segmented control below, with shared top row still accessible.
- Explore: editorial two-column portrait grid; chips All / Full Body / Portraits / Seated / Couples / Groups. Header and filters sticky when scrolling.
- Yours: imported-reference two-column grid, newest import first.
- Explore tiles: tap -> immersive preview, horizontal swiping -> adjacent references, Recreate -> camera.
- Favorites/recents: tap -> camera immediately. Long-press -> native preview and management menu.
- Favorite curated references get tiny bookmark indicator in grid; no 'previously used' badge.

### Import and reuse
- Gallery header `+` opens native iOS Photos picker.
- Importing automatically adds an item to Yours; then opens the immersive preview with Recreate. Removing from FrameShift must not delete original from Apple Photos.
- Current-session captures can also become references. Session grid `Select` -> multiple photos -> `Add to References`. Keep user in session gallery, show concise success confirmation. The individual photo viewer may offer `Use as Reference` via overflow, also without forcing camera navigation.
- Keep existing photo associated with reference metadata in session so comparison remains valid after switching references.

## 3. First use and permissions
- No standalone instructional onboarding slides.
- Guided 3-ish step journey inside the actual app: choose reference -> experience reference overlay / Guides control -> take photo; contextual spotlight hints disappear after the real action. Must be possible to skip/continue normally.
- First camera entry: one short contextual camera-access explanation immediately before requesting native iOS camera permission. Request at point of need.
- Recreate transition: selected photo animates into the camera overlay, with reduced-motion version.
- Gallery is useful immediately with curated sample photography; no exposition-heavy sample intro screen.

## 4. Camera visual-aid state machine

### Visual output modes
1. **Adaptive (automatic initial behavior):** starts with Overlay; after roughly 1–2 seconds of stable person detection, transitions once to Guides. Stays in Guides for remainder of that camera/reference phase even if person briefly disappears.
2. **Manual Overlay:** reference overlay displayed at fixed 35% opacity. No head circle or level simultaneously.
3. **Manual Guides:** persistent fixed target head circle; contextual level. No reference overlay.
4. **Manual Clean:** neither visual mode displayed; live coaching pill still available.

### User control
- Two adjacent icon buttons near top: Overlay and Guides, manually selected mode gets yellow highlight.
- Selecting either mode disables automatic switching for that camera/reference phase; buttons mutually exclusive.
- Tapping currently active selected mode again turns both buttons off and enters Manual Clean, not Adaptive. Adaptive resumes at next new camera session or on switching references.
- Switching references (even in same photography session) restarts Adaptive at Overlay, transitioning after stable person detection.
- Switching front/rear cameras preserves reference and current guidance mode; pause/recalibrate feedback while camera switches.
- Starting a truly new camera session restarts Adaptive; the user's last reference is still remembered for fast launch.
- Previously discussed 'remember last-used Overlay/Guides mode across sessions' was **superseded** by this adaptive-on-new-session design.

**Interaction ambiguity needing prototype validation:** A previously chosen behavior says tapping the reference thumbnail toggles the overlay, while newer behavior says tapping an explicit Overlay button establishes manual mode. Recommended preliminary rule: tapping thumbnail is a shortcut for the **same Manual Overlay toggle** as its button; adjacent chevron always opens picker. Test discoverability and state feedback before freezing implementation.

### Coaching independent of overlays
- Floating translucent pill always handles live coaching, even in Manual Clean.
- Tap pill to collapse to a small indicator; tap to expand again. Respect the collapsed preference even when face detection drops.
- When no face detected, show quiet `Looking for subject` status if pill is expanded; Guides target circle remains visible when in Guides mode.
- The target circle is fixed to desired head position and apparent size from reference. Do not draw an extra detected-head ring.
- Coaching identifies the largest composition mismatch (scale/distance, position, camera tilt) and displays one actionable correction at a time. Stabilize instructional state to prevent flicker or conflicting corrections.
- Level appears when appreciably tilted and fades after alignment; head circle persists throughout Guides mode.
- Confirm successful alignment only after relevant metrics stable: guides turn yellow; subtle single haptic; brief pill confirmation; prevent repeated triggers until meaningful misalignment and realignment.
- **Provisional not confirmed:** after `Looking good`, pill reduces to small yellow ready checkmark while in acceptable alignment.

## 5. Shooting, sessions and storage
- Shutter stays available during coaching; never block capture solely for imperfect composition.
- Successful capture automatically saves to Apple Photos. If permission/storage fails, provide clear actionable retry/error and do not increment saved count as though saved.
- Stay in camera after capture, with restrained shutter feedback and device-appropriate sound.
- Camera's bottom-left most recent photo thumbnail has a small top-right badge displaying the current session's saved-photo count.
- Sessions group photos automatically based on shooting activity. Brief app switching/interruption must not split a session. **Exact inactivity threshold remains to be specified and tested.**
- A photography session (capture group) is distinct from a camera's guidance phase (which resets on a reference change). Switching references does NOT reset capture count.
- Store which reference each capture used, so comparison works with multiple references in one session.
- The app does not build a browsable long-term historical session archive; older photos reside in Apple Photos.

## 6. Session gallery and photo viewer
- Thumbnail/count -> session's chronological two-column or standard Apple Photos-like grid (responsive native grid).
- Session gallery top header includes camera shortcut to return to same shooting context.
- Tap image -> full-screen viewer. Swipe between photos.
- Press and hold captured photo -> reveal corresponding original reference; release -> captured photo. Provide accessible alternative in final UI.
- Viewer is comparison-first: no filters, separate editor, or Save button.
- Select mode: checkmarks plus bottom actions `Add to References` and `Share`; multiple selections supported.
- Adding references shows lightweight success and stays on session gallery.

## 7. Camera controls and settings
- Always show: shutter, zoom, camera flip, reference thumbnail, picker chevron, Overlay and Guides icons, and recent-capture thumbnail/count. Native back chevron to gallery.
- Zoom presets match device capabilities; long-press or drag to fine-adjust.
- Flash and secondary capture functions in camera expandable menu. General app settings only in gallery header.
- Portrait-only UI for initial redesign. Landscape references may be imported, but landscape camera UI is deferred. Confirm actual output aspect/cropping behavior during engineering.

## 8. State model and critical edge cases

Suggested conceptual state, not implementation code:

```text
lastUsedReferenceID: optional
activeCaptureSessionID: optional
captureSessionStartedAt / lastCaptureAt: timestamps
aidMode: adaptive-overlay | adaptive-guides | manual-overlay | manual-guides | manual-clean
coachingCollapsed: boolean
cameraPosition: front | rear
referenceForEachCapture: stable reference ID / snapshot
cameraPermissionState: unknown | granted | denied | restricted
photosSaveState: ready | needs-permission | failed
```

Test at minimum:
1. First launch and camera permission denied.
2. Returning launch with and without previous reference.
3. Detect person -> stable automatic transition; face disappears briefly.
4. Toggle Overlay / Guides / Clean; switch camera; switch reference mid-session.
5. Switch app briefly; resume; return much later (new session).
6. Take several photos, then change reference; count and associations stay correct.
7. Apple Photos save failure, interrupted save, count consistency.
8. Favorite/import/remove references without deleting Apple Photos original.
9. Long-press compare versus horizontal swipe, VoiceOver/reduced motion.
10. No faces, multiple faces, nonportrait/group references, and reference analysis failure.

## 9. Open design/engineering questions
- Session timeout and boundary semantics, and when navigation Back should/should not end a camera guidance phase.
- Stable detection confidence/latency, multiple-face selection, detection on front camera, and handling unsupported reference compositions.
- Exact photo saving permission UX and recovery.
- Data model for bundled curated assets versus local imported assets, licensing and availability of curated images.
- Native modal sheet detents, how sticky headers behave inside expanded sheet, and modal dismissal.
- Precise coaching scores/thresholds/haptic cooldown (cannot be determined by mockups alone).
- Complete screen state for camera access denied and media save failure.
