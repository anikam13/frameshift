# FrameShift — Design Decisions Log

One entry per decision: **what**, **why**, **rejected alternatives**, **status**.
Status values: `approved` (designer-approved, build it) · `provisional`
(current best guess, validate before freezing) · `implementation` (a call made
while building where the spec was silent — revisit freely) · `superseded`.

Sources: `docs/ux-redesign/` (UX package: `UX-SPEC.md`, `DESIGN.md`,
`SCREEN-INVENTORY.md`), Paper file **"FrameShift — UX Redesign"** (page
"00 · Design notes" is the design contract; artboards marked "V1/V2 approved").
When this log and the code disagree, this log wins until it's updated.

---

## Precedence

1. Paper artboards marked **V2 approved** (newest).
2. Paper "00 · Design notes" + artboards marked **V1 approved**.
3. `UX-SPEC.md` / `DESIGN.md` approved statements.
4. Entries below marked `implementation` or `provisional`.

Paper V2 artboards were made after the UX package, so where they differ, Paper
wins (example: D-12 flash).

---

## Product principles (approved)

| # | Principle | Why |
|---|---|---|
| P-1 | **Photographs lead.** Photos, not copy, supply personality and hierarchy. | Old app leaned on explainer text; the photos are the product. |
| P-2 | **Shoot fast.** Returning users go straight to the camera with their last reference; familiar references are one tap away. | Coaching must never cost normal photo-taking speed. |
| P-3 | **Guide, don't lecture.** One calm instruction at a time; teach with real UI. | Competing corrections and onboarding slides were the main friction. |
| P-4 | **Native familiarity, selective signature.** iOS sheets, menus, haptics; custom motion only where it serves composition. | |
| P-5 | **Progressive disclosure.** Common camera actions visible; secondary ones in a compact menu. | |
| P-6 | **No unnecessary management.** Auto-save to Apple Photos, automatic sessions; not a second photo archive or an editor. | |

Paper design contract headline: *"Photographs lead. The camera stays quiet."*

---

## Navigation & shell

**D-1 · No permanent Reference/Camera tabs** — `approved`
Core path: Gallery → (preview) → Camera → Session gallery → Viewer. The
REFERENCE · CAMERA pill is removed. Camera has a native back chevron to the gallery.
*Rejected:* permanent tabs (listed as an anti-pattern).

**D-2 · Launch routing** — `approved`
Every fresh launch → the gallery home. *(Revised 2026-11-18: previously a
returning user went straight to the camera.)* The camera stays mounted under
the gallery and starts its session at launch, so it's already warm when the
user taps Recreate / Resume Camera. A brief interruption restores the current
view/session.

**D-3 · Settings live in the gallery header only** — `approved`
Not in the camera menu.

**D-4 · Resume Camera** — `approved`
The gallery header shows a subtle Resume Camera while a session is active
(`AppState.sessionShots` non-empty). Exact placement is `provisional`.

**D-5 · Portrait-only UI** — `approved`
Landscape references can be imported; landscape camera UI is deferred.

---

## Reference discovery

**D-6 · Gallery structure** — `approved`
Compact FrameShift wordmark, `+` import, settings access. One merged
favorites + frequently used row (favorites first, no duplicates) above an
Explore / Yours switch. Header + chips are sticky; the quick row scrolls away.
*Rejected:* oversized "References" heading, many competing action buttons.

**D-7 · Explore chips: All / Full Body / Portraits / Seated / Couples / Groups** — `approved`
*Rejected:* technical categories in primary browsing (old "Low angle",
"Telephoto" style groups).

**D-8 · Tap behavior differs by source** — `approved`
Quick-access (favorite/recent) tap → camera immediately. Curated grid tile →
immersive preview with Recreate. Import → preview. Long-press → native
preview + context menu (favorite, share, remove where allowed).

**D-9 · Bookmark badge for favorited curated photos only** — `approved`
No "previously used" badge.

**D-10 · Removing from FrameShift never deletes the Apple Photos original** — `approved`

**D-11 · Session captures can become references** — `approved`
Session grid Select → Add to References. The user stays in the session gallery
and sees a short confirmation. The viewer may offer "Use as Reference" from overflow.

---

## Camera

**D-12 · Flash is one tap in the top bar (off ↔ on)** — `approved (Paper V2)`
Supersedes the UX-SPEC line "flash in the expandable camera menu". Auto is not offered.
The `⋯` menu holds only secondary options.

**D-13 · Visual-aid state machine** — `approved`
- Adaptive starts at Overlay → moves **once** to Guides after ~1–2s of stable
  person detection; stays in Guides even if the person briefly drops out.
- Overlay / Guides buttons select Manual modes; mutually exclusive.
- Re-tapping the active manual mode → **Manual Clean** (not Adaptive).
- Reference switch → restarts Adaptive at Overlay; the capture count is kept.
- Camera flip keeps the reference and mode.
- New camera session → restarts Adaptive; the last reference is still remembered.
*Superseded:* "remember last-used Overlay/Guides mode across sessions".

**D-14 · Only manual selections get yellow** — `approved`
Adaptive transitions never highlight a button.

**D-15 · Overlay is a person-only cutout at a fixed 35%** — `approved`
The reference background is masked out; head, body and clothing are kept. Source
position and scale are preserved. Native code masks the original photo and does
not redraw it. *Rejected:* opacity slider, per-reference opacity.

**D-16 · Guides = one fixed target circle + contextual level** — `approved`
The circle marks the reference's head position and apparent size. **No ring around the
detected head**, no arrows. The level appears when noticeably tilted and fades once aligned.

**D-17 · Coaching pill is independent of the aid mode** — `approved`
Present even in Clean. One instruction at a time: the largest mismatch
(scale/distance, position, tilt), stabilized against flicker. "Looking for
subject" when nobody is detected. Tap collapses it to a small indicator; the
collapse is respected through detection drops.

**D-18 · Alignment confirmation** — `approved`
Guides turn yellow, one subtle haptic, a brief pill confirmation. Re-arms only
after meaningful misalignment and realignment.

**D-19 · "Looking good" collapses to a yellow check while aligned** — `approved`
(Paper design notes; the UX-SPEC listed it as provisional.) Drift restores
coaching unless the user explicitly collapsed it.

**D-20 · Reference thumbnail tap = Manual Overlay toggle; chevron = picker** — `approved` (Nov 18 2026)
Was the spec's recommended rule for an unresolved conflict; confirmed by the designer. Hold-to-peek the full reference is kept from the old app
(`implementation`).

**D-21 · Never block the shutter** — `approved`
Capture always works; imperfect composition never blocks it.

**D-22 · Zoom presets follow the device's lenses** — `approved`
No hardcoded unsupported lenses. Long-press or drag fine-adjusts.

---

## Sessions & storage

**D-23 · Session count badge on the camera thumbnail** — `approved`
Counts only captures confirmed saved to Apple Photos. A reversal of CLAUDE.md
"no photo counter" (alongside the burst count).

**D-24 · A capture session is not a guidance phase** — `approved`
Switching references resets guidance, not the session or its count. Each capture
stores its reference so comparison still works with several references in one session.

**D-25 · No long-term archive** — `approved`
Older photos live in Apple Photos. Implementation impact: see O-2.

**D-26 · Viewer is comparison-first** — `approved`
Hold the photo → original reference; release → capture. The **Compare**
button is the accessible alternative (approved; closes O-8). No filters,
editor or Save button.

---

## First use

**D-27 · No onboarding slides; in-app spotlight hints (~3 steps)** — `approved`
Steps: choose reference → overlay/guides → take photo. Skippable.
*Superseded detail:* "each hint dismisses on the real action" — the Paper V2
tours (Explore 2 steps, Camera 4 steps, **Next** buttons) are followed instead
(designer-confirmed Nov 18 2026). *Rejected:* the current mandatory carousel.

**D-28 · Camera permission at point of need** — `approved`
One short contextual explanation right before the system prompt.

**D-29 · Recreate morphs the photo into the overlay** — `approved`
With a Reduce Motion fallback.

---

## Visual language

**D-30 · Gallery follows system light/dark; camera is always dark** — `approved`

**D-31 · Accent #FFD60A, used sparingly** — `approved`
Only for active manual controls, confirmed alignment and selection. No yellow
buttons across the gallery. Value is provisional pending contrast review.

**D-32 · SF system font + Dynamic Type** — `approved`
Helvetica Neue in Paper is a stand-in only.

**D-33 · Tokens from Paper** — `approved`
Camera control fill #242424 · selected-control tint #332B00 · coach pill
black 72% · guide ring white 90% @ 1.5pt · shutter 78pt ring / 3pt / 66pt
fill · thumbnail 48pt r8 with 22pt white count badge · sheet radius 24.

**D-34 · Welcome screen** — `approved` *(2026-11-18)*
First launch only (Replay Tutorial shows it again): black screen, "Welcome
to FrameShift / Press the shutter to get started", the real shutter at its
camera position. Behind it, a "reference wall": the bundled sample photos in
three tilted columns drifting slowly in alternating directions (the scrolling
collage photo apps use on welcome screens) under a faint thirds grid, falling
off to black behind the text. *(First pass — floating framing aids on black —
was replaced as too sparse.)* Press → haptic, the wall falls away, the shutter
disc grows to fill the screen in the gallery's background colour and dissolves
into the gallery; the Explore tour
waits for it. The camera starts underneath meanwhile. Reduce Motion: still
wall, cross-fade. Not a carousel — one screen, one action.

---

## Implementation decisions (camera phase, Nov 18 2026)

**I-1 · Stable-detection delay = 1.5s** — `implementation`
Middle of the spec's 1–2s range. `CameraViewModel.stableDetectionDelay`.

**I-2 · Session ends after 30 min without a capture** — `approved` (Nov 18 2026)
`AppState.sessionInactivityLimit`. Survives the app being closed (I-8).

**I-3 · Re-entering the camera from the gallery restarts Adaptive** — `approved` (Nov 18 2026; closes O-1)
Back to the gallery ends the guidance phase; returning starts again at
Overlay. The capture session and its count carry on.

**I-4 · Grid + 4:3/16:9 aspect live in the `⋯` menu** — `implementation`
Neither is in the mockups. Both were kept as secondary options rather than dropped.

**I-5 · Explore = bundled samples, Yours = imports** — `implementation`
`ReferencePhoto.isCurated` = has `bundledAssetName`. The curated set is the
bundled AI-generated (Gemini) photos — approved (O-3). Curated photos carry
hand tags (`SampleReferencePack.tags`); imports fall back to
`ShotSpec.framing` for Full Body / Portraits. Chips with no matches hide —
today Couples / Groups (no such photos yet). Curated photos can be favorited
but not removed.

**I-6 · Coaching collapse is session-scoped** — `implementation`
Not persisted across launches.

**I-7 · Camera stays mounted under the interim references screen** — `implementation`
Rebuilding `ViewfinderView` hangs the main thread. Kept for the gallery home
too (phase 2): `GalleryHomeView` is layered over the mounted camera.

## Implementation decisions (phases 2–5, Nov 18 2026)

**I-8 · Captures are session-only; no in-app copies** — `approved` (resolves O-2)
The camera thumbnail opens `SessionGalleryView` (`AppState.sessionShots`).
`CapturedStore` and capture favorites are removed. Full JPEGs sit in
`SessionCaptureCache` (Caches dir) only while the session is open — for
full-size share, Add to References and save retry — with a small manifest so
an open session comes back if iOS closes the app in the background (D-2).
On launch a session whose last capture is within 30 min is restored; anything
older is deleted (as are the old Application Support/Captures store and
filter presets). Storage settings no longer list captures.
The old `Screens/Library/` views are deleted.

**I-13 · Filters removed** — `approved` (resolves O-4, per D-26)
`FilterService`, `FilterPresetStore`, `CustomFilterPreset`, `FilterPresetSheet`
and their tests are deleted. Preset files from older builds are deleted on
launch. `ExportService` remains dormant.

**I-9 · Tours replace the onboarding carousel** — `implementation`
`Screens/Onboarding/` deleted. Tours are shown once each
(`frameshift.tour.explore.done`, `frameshift.tour.camera.done`); the camera
tour waits for camera authorization. Onboarding image assets remain in
`Assets.xcassets` (cleanup in phase 6).

**I-10 · "No person found" badge only on imports** — `implementation`
Curated tiles never show it (they're vetted; simulator Vision fails on them).

**I-11 · Dropped from Settings** — `implementation`
"Show Reference Hint Again" and the camera guide toggles; guides are now the
camera's mode buttons.

**I-12 · Recreate morph, zoom fine-adjust, Dynamic Type** — `implementation`
- D-29: the preview photo flies to exactly where the overlay draws it
  (aspect-fit in the viewfinder) on a critically damped spring (0.45s, no
  bounce — nothing was flung), going semi-transparent in flight. The overlay
  is held back during the flight (no double exposure), then photo-out and
  overlay-in cross-fade in one 0.25s ease-out hand-off just before the spring
  settles (~0.7s total). Reduce Motion → 0.25s cross-fade.
- Motion rules (from Apple's *Designing Fluid Interfaces* and Emil Kowalski's
  `emilkowalski/skills` audit): enter/exit = ease-out, never ease-in; on-screen
  moves = ease-in-out or a no-bounce spring; bounce only after a gesture with
  momentum; one shared toast transition (fade + rise, fade-only under Reduce
  Motion).
- D-22: drag sideways on the zoom row (exponential, left = in) with a live
  readout and a tick per lens; VoiceOver swipe up/down adjusts.
- D-32: text uses text styles; screens cap at `.xxxLarge` (fixed-height
  controls); Settings uncapped; camera chrome glyphs stay fixed like the
  system Camera. Reduce Motion also drops the toast's slide.
- Cleanup: onboarding images, `ExportService`, `BoundingBoxOverlay` deleted.

**I-14 · Shutter latency, adaptive detection, subject-lift Recreate, Delete** — `implementation`
- Shutter: haptic + blink on the tap (never on photo completion); taps
  overlap (≤4 in flight); iOS 17 zero shutter lag, responsive capture and
  fast-capture prioritization; pipeline pre-warmed with
  `setPreparedPhotoSettingsArray` so the first shot doesn't stall.
- Adaptive Overlay → Guides: presence = a Vision body box with confidence
  ≥ 0.6 (was always true — a non-optional struct compared to nil).
- Recreate (D-29) is now `RecreateMorphView`, shared by the preview, the
  quick row, picker-sheet switches and cold launch (in place, no flight):
  flight → scan (0.375s passes; the background is cut away behind the line
  and the person's outline glows) repeated until the camera is running, the
  zoom has settled and the cutout is loaded (≥ 1 pass, ≤ 2.5s) → lift over
  the live feed → settle to the 35% overlay. The photo + scrim hide the
  feed until then, so a starting camera is never seen. Gallery ↔ camera
  fades with a slight scale.
- Delete from the session gallery / viewer deletes from the camera roll
  (stored asset id); read/write Photos access requested on first Delete.

---

## Open questions

| # | Question | Blocks |
|---|---|---|
| O-5 | Detection: confidence, multiple faces, front camera, non-portrait/group references | Run `docs/coaching-eval.md` (S1–S9) |
| O-6 | Coaching thresholds and haptic cooldown values | Run `docs/coaching-eval.md` (T1–T5) |

**Closed Nov 18 2026:** O-1 (I-3), O-2 (I-8), O-3 (I-5), O-4 (I-13), O-7 (save-failure
and camera-denied states signed off as built), O-8 (Compare button, D-26).
