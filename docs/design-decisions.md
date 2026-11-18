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
First launch, or no previously chosen reference → Explore gallery. Later
fresh launches with a last-used reference → camera directly. A brief
interruption restores the current view/session.

**D-3 · Settings live in the gallery header only** — `approved`
Not in the camera menu.

**D-4 · Resume Camera** — `approved`
The gallery header shows a subtle Resume Camera while a session is active.
Exact placement is `provisional`.

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

**D-20 · Reference thumbnail tap = Manual Overlay toggle; chevron = picker** — `provisional`
This was the spec's recommended rule for an unresolved conflict. Needs a
discoverability test. Hold-to-peek the full reference is kept from the old app
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
Hold the photo → original reference; release → capture. Needs an accessible
alternative. No filters, editor or Save button.

---

## First use

**D-27 · No onboarding slides; in-app spotlight hints (~3 steps)** — `approved`
Steps: choose reference → overlay/guides → take photo. Each hint dismisses on the real action.
Skippable. *Rejected:* the current mandatory carousel.

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

---

## Implementation decisions (camera phase, Nov 18 2026)

**I-1 · Stable-detection delay = 1.5s** — `implementation`
Middle of the spec's 1–2s range. `CameraViewModel.stableDetectionDelay`.

**I-2 · Session ends after 30 min without a capture** — `implementation`
The spec leaves this open (O-1). `AppState.sessionInactivityLimit`.

**I-3 · Re-entering the camera from the gallery restarts Adaptive** — `implementation`
Treated as a new guidance phase. The spec leaves "when Back ends a guidance
phase" open (O-1).

**I-4 · Grid + 4:3/16:9 aspect live in the `⋯` menu** — `implementation`
Neither is in the mockups. Both were kept as secondary options rather than dropped.

**I-5 · Explore = bundled samples, Yours = imports** — `implementation`
`ReferencePhoto.isCurated` = has `bundledAssetName`. Chips map Full Body /
Portraits from `ShotSpec.framing`. Seated / Couples / Groups are hidden until
curated photos carry tags (O-3).

**I-6 · Coaching collapse is session-scoped** — `implementation`
Not persisted across launches.

**I-7 · Camera stays mounted under the interim references screen** — `implementation`
Rebuilding `ViewfinderView` hangs the main thread. Kept for the gallery home
too (phase 2): `GalleryHomeView` is layered over the mounted camera.

## Implementation decisions (phases 2–5, Nov 18 2026)

**I-8 · Session gallery is session-only** — `implementation`
The camera thumbnail opens `SessionGalleryView` (`AppState.sessionShots`).
`CapturedStore` still persists copies; the old `Screens/Library/` views
(`GalleryPreviewView`, `GalleryLibraryView`, filters) and `ExportService` are
unreachable but not deleted — pending O-2 / O-4.

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

**I-12 · Not built yet** — `implementation`
Recreate morph transition (D-29), zoom fine-adjust (D-22). Recreate uses a
plain cover dismiss.

---

## Open questions

| # | Question | Blocks |
|---|---|---|
| O-1 | Session inactivity threshold; does Back end a guidance phase? | I-2, I-3 |
| O-2 | Keep the in-app captured-photo store (`CapturedStore`, favorites, library grid) or move to session-only per D-25? | Phase 3 |
| O-3 | Curated set: which images, how they're tagged (Seated/Couples/Groups), licensing, what actions bundled photos allow (remove?) | Phase 2 |
| O-4 | Filters (`FilterService`, `FilterPresetSheet`): remove per D-26 or keep somewhere? | Phase 3 |
| O-5 | Detection: confidence, multiple faces, front camera, non-portrait/group references | Coaching tuning |
| O-6 | Coaching thresholds and haptic cooldown values | Coaching tuning |
| O-7 | Photos save-permission UX and retry flow; camera-denied full state — built from the V1 artboards; confirm | Phase 4 |
| O-8 | Accessible alternative to hold-to-compare | Phase 3 |
