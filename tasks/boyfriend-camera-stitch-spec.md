# Boyfriend Camera — UI Spec v2
**For:** Google Stitch (new project)
**Updated:** June 2026
**Status:** Working draft

---

## Design Philosophy

This app should be indistinguishable from a first-party Apple camera app. Every screen follows Apple Human Interface Guidelines precisely. The camera screen is a direct extension of the native iOS Camera app — same shutter button, same chrome, same type treatment, same icon weight. Non-camera screens (Library, Post-Shot) follow the iOS Photos / UIKit dark mode aesthetic.

The only things that distinguish this app visually from the native camera are the bounding box overlay and the reference strip. Everything else should look like it shipped with the iPhone.

---

## Design Language Rules

- **Font:** SF Pro Text and SF Pro Display exclusively. Never Inter, never custom fonts.
- **Icons:** SF Symbols only, at "thin" or "regular" weight, matching the weight used in the native iOS Camera app.
- **Corner radius:** Follow iOS squircle geometry. Cards/sheets use 13px (system default for grouped content). Buttons use full pill (9999px) or system default.
- **Spacing:** Follow iOS HIG — 16px safe margins, 44pt minimum tap targets.
- **Motion:** Use iOS spring curves (UISpringTimingParameters). No custom easing.
- **Sheets:** Use native iOS bottom sheet presentation (detent-based). Do not design custom drawers.
- **Navigation:** Standard UINavigationController style — back chevron + title, no custom nav bars on camera screen.
- **No custom accent colors on non-camera screens.** Use iOS system blue (`#007AFF`) for tappable elements in Library and Post-Shot.

---

## Color System

| Token | Value | Source | Usage |
|---|---|---|---|
| `bg-base` | `#000000` | iOS Camera chrome | Camera screen background, shutter area |
| `system-bg` | `#000000` (dark) | iOS systemBackground | Library, Post-Shot background in dark mode |
| `system-bg-2` | `#1C1C1E` | iOS secondarySystemBackground | Cards, sheets |
| `system-bg-3` | `#2C2C2E` | iOS tertiarySystemBackground | Elevated cells |
| `label` | `#FFFFFF` | iOS label (dark) | Primary text |
| `label-2` | `rgba(255,255,255,0.55)` | iOS secondaryLabel (dark) | Supporting text |
| `label-3` | `rgba(255,255,255,0.30)` | iOS tertiaryLabel (dark) | Placeholder, disabled |
| `system-blue` | `#007AFF` | iOS systemBlue | Tappable text, links, CTAs in Library/Post-Shot |
| `camera-yellow` | `#FFD60A` | iOS Camera active state | Active mode label, bounding box when locked, level-locked indicator |
| `camera-white` | `#FFFFFF` | iOS Camera icon color | Shutter button, all camera chrome icons |
| `grid-line` | `rgba(255,255,255,0.25)` | iOS Camera grid | Rule-of-thirds lines (matches native camera exactly) |
| `box-idle` | `rgba(255,255,255,0.80)` | iOS Camera focus square | Bounding box corner handles when composing |
| `box-locked` | `#FFD60A` | iOS Camera focus square locked | Bounding box corner handles when focus locked |
| `level-neutral` | `rgba(255,255,255,0.4)` | Level line when not level |
| `level-locked` | `#34C759` | Level line when level (iOS green) |
| `overlay-glass` | `rgba(0,0,0,0.55)` + blur 24px | Bottom strip, tip banners |

---

## Typography

All type is **SF Pro** (SF Pro Text for ≤19px, SF Pro Display for ≥20px). This is the system font — Stitch should set font to "SF Pro" or "-apple-system". Never substitute Inter or any other font.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Nav bar title | 17px | 600 | Standard iOS nav bar |
| Body | 17px | 400 | iOS default body size |
| Supporting | 15px | 400 | Secondary text |
| Caption | 13px | 400 | Cards, metadata |
| Micro label | 11px | 500 | Thumbnail labels, status |
| CTA button | 17px | 600 | System button default |
| Camera overlay | 14px | 500 | Tip banners, matches native Camera app tip style |

No custom letter-spacing. No monospaced fonts. Follow iOS Dynamic Type behavior.

---

## Spacing

- Side margins: 16px (iOS HIG standard safe margin)
- Card padding: 16px
- Component gap: 8px
- Safe area: always respect iOS dynamic safe area insets — never hardcode 34px
- Tap targets: minimum 44×44pt on all interactive elements (iOS HIG requirement)

---

## App Flow

```
Launch
  └─ Has references?
       ├─ Yes → Library screen (references ready, "Start Shooting" visible)
       └─ No  → Library screen (empty state, prompt to add references)
            └─ [Import photos from camera roll / files]
                 └─ Background analysis runs per photo (silent)
                      └─ "Start Shooting" → Camera screen
                           └─ [Shoot]
                                └─ Post-Shot screen
                                     └─ [Export] → Before/After card
                                     └─ [Retake] → Camera screen
                                     └─ [Keep] → back to Library
```

---

## Screen 1 — Library

**Purpose:** Reference set management. Should feel like a focused version of the iOS Photos app — same dark mode aesthetic, same grid behavior, same nav bar treatment.

### Layout

- **Navigation bar** — standard iOS UINavigationBar, dark mode
  - Title: "Boyfriend Camera" — centered, SF Pro 17px 600, white
  - Right: SF Symbol `gearshape` (regular weight, 22px) in `label-2` — opens settings
  - No left button (this is the root screen)
  - Large title style: OFF. Standard compact nav bar.

- **Reference grid** (main content area)
  - Matches iOS Photos grid exactly: 3-column, 2px gutters (not 3px — Photos uses 2px), flush to screen edges
  - Each cell is square, full-bleed photo thumbnail, no rounding, no border
  - Black (#000) fills the gaps between photos — same as native Photos
  - Analysis status: a UIActivityIndicatorView (system spinner, white, small) in the bottom-right corner of the thumbnail while processing. Removed entirely when ready — no dot, no badge.
  - Tapping opens a full-screen photo viewer using the standard iOS zoom transition (photo expands from its grid position)

- **Empty state** (no references imported yet)
  - Centered vertically in the safe area
  - SF Symbol: `photo.badge.plus` (thin weight, 48px, `label-3`)
  - Headline: "No references yet" — `label`, SF Pro 17px 400, centered
  - Subtext: "Save shots from Pinterest or Instagram to your camera roll, then import them here." — `label-2`, 15px 400, centered, max-width 260px, line-height 1.4
  - No illustration

- **Toolbar** (bottom, UIToolbar style, above safe area)
  - Background: iOS system material — `UIBlurEffect(.systemUltraThinMaterialDark)`. Same translucent bar material as native apps.
  - Hairline separator at top: `separator` system color at 0.5px
  - Left item: SF Symbol `plus` (22px, `system-blue`), label "Add" below in 11px — this is a standard UIBarButtonItem
  - Center item: "Start Shooting" — iOS filled button style. Background: `system-blue` (#007AFF), white label, SF Pro 17px 600, pill shape (cornerRadius 14px). Width fills remaining center space with 16px margins. Disabled: system opacity 0.3, not tappable.
  - Right item: intentionally empty to balance left

### Behavior

- Multi-select photo import via standard PHPickerViewController (native iOS photo picker)
- Analysis runs per photo, immediately on import, silently in background
- "Start Shooting" activates when ≥1 photo is fully analyzed
- Long-press on thumbnail: iOS context menu (standard UIContextMenuConfiguration) with single option: "Remove" with `trash` SF Symbol
- Order: most recently added first

### Aesthetic notes for Stitch

- This screen is effectively iOS Photos in dark mode with a custom toolbar. Match it exactly.
- Background is pure black (#000), same as Photos dark mode
- The toolbar blur material is the exact same translucent dark bar seen in Photos, Maps, Safari
- Do NOT use a custom colored accent here — system blue only for all interactive elements
- No card surfaces, no custom backgrounds behind the grid, no shadows

---

## Screen 2 — Camera (Live Shoot)

**Purpose:** The core product. This screen IS the native iOS Camera app, with three additions: a bounding box overlay, a reference thumbnail strip, and a coaching tip banner. Everything else is identical to native Camera.

### Reference: study the native iOS Camera app

Before building this screen, study the iPhone 16 Camera app at full resolution. Match every detail: the shutter button geometry, the top icon row, the chrome color, the font used for mode labels. The goal is that a user switching from native Camera to Boyfriend Camera during a shoot notices no visual discontinuity in the chrome — only the bounding box and strip are new.

### Layout

Full bleed viewfinder, edge to edge including behind Dynamic Island.

- **Top control row** (floating, ~44px tall, sits at top of viewfinder)
  - Matches native iOS Camera top bar exactly
  - Background: transparent — no blur, no surface, icons float over the live feed
  - Controls from left to right: back chevron (SF Symbol `chevron.left`, white, 17px), then spacer, then grid toggle (SF Symbol `squareshape.split.3x3`, white, 20px)
  - Icon tint: white when inactive, `camera-yellow` (#FFD60A) when active — exactly as native Camera highlights active flash/timer
  - No labels under icons

- **Bounding box** (viewfinder overlay)
  - Corner handles only — an L-shaped bracket at each of the four corners of the target frame
  - Each arm of the L: 2pt stroke, 20px long, white (`box-idle`)
  - The four handles together imply a rectangle without drawing one — same visual language as the iOS Camera focus square
  - Default (no references): frame centered, mid-body portrait crop, roughly 55% frame height × 65% frame width
  - On focus lock: handles animate to `camera-yellow` (#FFD60A) over 150ms — exactly matching the iOS focus square color lock behavior. Light haptic fires simultaneously.
  - On reference switch: handles spring-animate to new position/size over 180ms

- **Level indicator** (viewfinder overlay, centered horizontally)
  - Matches the native iOS Camera horizon level exactly:
    - Two short lines (each 20px wide, 1.5pt stroke, white at 60% opacity) separated by a small center gap, sitting at vertical center of frame
    - When level: the two lines merge and turn `camera-yellow`, haptic fires (medium impact). This is pixel-identical to iOS Camera's level indicator.
  - No numeric readout, no degree value

- **Rule-of-thirds grid** (viewfinder overlay, toggleable)
  - Matches native iOS Camera grid exactly:
    - 2 horizontal + 2 vertical lines, full bleed edge to edge
    - `rgba(255,255,255,0.25)` — slightly more visible than before to match native
    - 0.5pt stroke
  - Default: visible. Grid toggle button (top row) hides/shows.

- **Tip banner** (viewfinder overlay, top-center, below top row)
  - Style matches native iOS Camera coaching tips (e.g. Portrait mode "Move further away" / "More light needed"):
    - White rounded rectangle background, cornerRadius 8px
    - Text: SF Pro 14px 500, black (#000) — dark text on white pill, same as native Camera
    - Padding: 10px horizontal, 6px vertical
    - Centered horizontally in the viewfinder
  - Content: short directional phrases only — "Move back" / "Raise the camera" / "Turn toward the light"
  - One at a time, auto-dismisses after 4 seconds, tap to dismiss early
  - Does not reappear for the same tip in a session

- **Reference strip** (viewfinder overlay, above shutter area)
  - Background: `UIBlurEffect(.systemUltraThinMaterialDark)` — the same blur used in native Camera's mode selector strip. This lets the live feed bleed through.
  - Height: 72px total (12px top padding, 48px thumbnails, 12px bottom padding)
  - Thumbnails: 48×48px, cornerRadius 6px (squircle-ish, matches iOS thumbnail style), 4px gaps
  - Active thumbnail: 3px `camera-yellow` border, no size change (border is the indicator — cleaner than scaling)
  - Horizontal scroll. First thumbnail = active reference.
  - Leftmost item (before thumbnails): SF Symbol `eye` (regular weight, 22px, white at 60% opacity). **Hold behavior only** — holding reveals the active reference at 40% opacity over the full viewfinder. Releasing clears it. This is a peek gesture, not a tap.
  - Trailing item (after all thumbnails): SF Symbol `plus.circle` (regular, 22px, white at 60%) — adds another reference without leaving camera
  - If no references: strip shows one dashed-border placeholder cell with SF Symbol `photo` inside at `label-3` opacity. Bounding box defaults to centered mid-body.

- **Shutter area** (bottom, below reference strip)
  - Pure black (#000) — no material, no blur, no surface
  - Height: 110px + dynamic safe area bottom inset
  - **Shutter button** — matches native iOS Camera exactly:
    - Outer ring: 2.5pt white stroke circle, 74px diameter
    - Inner fill: solid white circle, 62px diameter
    - Gap between ring and fill: 6px (same ratio as native Camera)
    - On press: inner circle scales to 88% (spring animation, ~120ms). UIImpactFeedbackGenerator .medium fires.
  - Left of shutter (32px from left edge): SF Symbol `photo.on.rectangle` (22px, white at 70%) — opens the reference peek at full screen. Tap behavior here is fine (vs. hold on the strip).
  - Right of shutter: nothing in v1

### Fade-on-Focus behavior

When the user taps the viewfinder to focus:

1. Top control row → opacity 0, 200ms
2. Tip banner → opacity 0, 150ms
3. Level indicator → opacity 0, 200ms
4. Grid → opacity 0, 200ms
5. Bounding box handles → opacity 0.25, 200ms (don't fully hide — ghost presence)
6. Reference strip → opacity 0, 200ms
7. Shutter button → stays fully visible (only element that remains)

All fade back in on: secondary tap to refocus, 4 seconds elapsing, or after capture.

On shutter press: capture fires while faded. The clean viewfinder is the moment of capture.

### Aesthetic notes for Stitch

- Pixel-match the native iOS Camera shutter button. This is the single most important element.
- All icons are white SF Symbols. No custom icon artwork.
- The only `camera-yellow` that ever appears in this screen: active grid toggle, level-locked indicator, focus-locked bounding box. Nothing else is yellow.
- No text labels under icons in the shutter area. No mode name. No zoom indicator.
- The reference strip blur should be identical to the native Camera mode selector (same dark ultra-thin material).

---

## Screen 3 — Post-Shot

**Purpose:** Show the result, surface 2–3 coaching notes, and make export easy. Feels like the native iOS photo viewer with a bottom sheet — not a custom screen.

### Layout

- **Navigation bar** — standard iOS UINavigationBar, dark mode, black background
  - Left: "Retake" — system tinted text button (`system-blue`, SF Pro 17px 400). Returns to camera without saving.
  - Center: nothing
  - Right: "Keep" — system tinted text button (`system-blue`, SF Pro 17px 400). Saves to camera roll, returns to Library.
  - This nav bar pattern is identical to the native iOS Photos "edit" nav bar. Two text buttons, nothing center.

- **Photo** (main content area)
  - Photo fills the screen from below the nav bar to the top of the sheet
  - Pure black (#000) background — letterboxes if needed, same as native Photos viewer
  - No border, no frame, no drop shadow, no mockup device frame
  - Photo is NOT inside a phone outline — it is the screen

- **Recommendation sheet** (UISheetPresentationController — native iOS bottom sheet)
  - Use native iOS sheet detents: small (collapsed, ~160px) and medium (~50% screen)
  - Background: iOS system grouped background — `UIColor.systemGroupedBackground` in dark = `#1C1C1E`
  - Corner radius: 20px (iOS system default for sheets)
  - Drag indicator: system-provided (gray pill, 4px × 36px, auto-positioned at top of sheet — do not design a custom one)
  - Sheet is always visible (not a modal that needs to be summoned), sitting at small detent by default. User swipes up to expand.

  **Inside the sheet — collapsed (small detent):**
  - A single horizontal scroll of recommendation cards, vertically centered
  - Card: 148px wide × 88px tall, `system-bg-3` (#2C2C2E) background, cornerRadius 13px (iOS system card radius)
  - Card interior:
    - SF Symbol icon (regular weight, 18px, `system-blue`) — top-left, 12px inset
    - Title: SF Pro 13px 600, `label` (white) — below icon, 4px gap
    - Body: SF Pro 12px 400, `label-2` — 2 lines max, 4px below title
  - 16px left inset on first card, 8px gaps, 16px right inset after last card
  - Maximum 3 cards

  **Card types:**
  - SF Symbol `sun.max` → "Subject was backlit. Turn them toward the light next time."
  - SF Symbol `figure.stand` → "Try a different pose — see suggestions below."
  - SF Symbol `viewfinder` → "Framing was slightly wide. Step closer next shot."
  - SF Symbol `photo` → "This reference matches your lighting better." (with small reference thumbnail inset)

  **Inside the sheet — expanded (medium detent):**
  - Cards remain at top
  - Below cards: a visual divider (`separator` color, 0.5pt), then "Export before/after" as a standard iOS full-width button — `system-blue` tint, SF Pro 17px 400, centered. No background fill on this button — just tinted text in the iOS style.

### Aesthetic notes for Stitch

- This screen is: iOS photo viewer (top 80%) + iOS native bottom sheet (bottom 20%). That's it.
- The sheet should look exactly like the share sheet or the Maps route details sheet — same material, same radius, same handle.
- No emojis in recommendation text. SF Symbols only.
- No score, no rating, no celebratory copy. The photo and the three cards are the entire screen.
- "Keep" and "Retake" are both `system-blue` — same weight, same size. Neither dominates. The user decides.

---

## Screen 4 — Before/After Export Card

**Purpose:** The shareable artifact. This is the distribution mechanic — a before/after of "reference I was trying to match" vs. "what I actually got." Should feel premium enough to share.

This screen is generated, not navigated to directly. It opens from the Post-Shot "Export before/after card" button as a share sheet workflow.

### Card layout (generated image, not a UI screen)

- Format options: 9:16 (Stories) or 1:1 (Square)
- **9:16 layout:**
  - Top half: reference photo (full width, cropped to fill half)
  - Thin 1px divider: `rgba(255,255,255,0.15)`
  - Bottom half: the captured photo (full width, cropped to fill half)
  - Small label top-left of each half: "REFERENCE" / "YOUR SHOT" — white, 10px, 600, 0.1em spacing, 8px from edges
  - Bottom of card: "Boyfriend Camera" wordmark, right-aligned, 10px, 400, `rgba(255,255,255,0.4)`
- **1:1 layout:**
  - Left half: reference photo
  - Right half: captured photo
  - Same labels and wordmark treatment

### Export behavior

- Generates the card as a PNG in the background (~1 second)
- Opens the iOS share sheet automatically
- Also saves to camera roll
- No account, no upload, fully on-device

### Aesthetic notes for Stitch

- Both photos should display in full color
- No additional overlays, filters, or effects on the photos themselves
- The wordmark branding should be barely there — tasteful, not promotional
- The divider should be a dark line on dark photos and a light line on light photos (or just skip it and use spacing with black letterboxing between)

---

## Screen 4 — Before/After Export Card

**Purpose:** The shareable artifact. Generated image — not a UI screen the user navigates to.

### Card layout

- Format options: 9:16 (Stories) or 1:1 (Square)
- **9:16:** Reference photo fills top half, captured photo fills bottom half. Both full color. 1px black divider between them.
- **1:1:** Reference left half, captured right half. 1px black divider.
- Label in each quadrant, bottom-left corner: "REFERENCE" / "YOUR SHOT" — SF Pro 10px 600, white, 0.08em spacing, 8px from edge
- Wordmark bottom-right of card: "Boyfriend Camera" — SF Pro 10px 400, `rgba(255,255,255,0.35)`

### Export behavior

- Generates as PNG, on-device
- Opens iOS native share sheet
- Also saves to camera roll
- No account, no upload

---

## What to Leave Out (v1 hard constraints)

These should not appear anywhere in the Stitch mockups:

- Any screen that shows numerical analysis output before the camera opens
- Mode switchers in the live camera (portrait / cinematic / night / etc.)
- Post-shot score or rating of any kind
- Gamification copy ("Mission Accomplished", "Stunning Shot", etc.)
- Gallery access from inside the camera screen
- Account creation or login
- Any loading/processing screen between Library and Camera
- EXIF data (ISO, focal length, aperture) — not shown anywhere in v1
- Photo counters ("001/024") — not shown anywhere
- Custom icon artwork — SF Symbols only throughout
- Any green accent color — green (#34C759) is reserved exclusively for the level-locked moment on the camera screen and must not appear anywhere else

---

## Stitch Prompt Notes

When building in Stitch, treat each screen as a separate frame. Suggested frame order:

1. Library — empty state
2. Library — with references (6 photos in grid, one with spinner still processing)
3. Camera — composing (all overlays visible, tip banner showing "Move back")
4. Camera — focus locked (overlays faded, bounding box yellow, only shutter visible)
5. Post-Shot — collapsed sheet (3 recommendation cards visible in strip)
6. Post-Shot — expanded sheet (cards + export button visible)
7. Export card — 9:16 variant

**Typography:** Set all fonts to SF Pro (or -apple-system in web contexts). No Inter, no custom fonts.

**Colors:** Use exact hex values from the Color System table. The only colors in the camera screen are: black, white, and `camera-yellow` (#FFD60A). No blues, no purples, no greens except the level-locked moment.

**Reference photo in camera viewfinder:** Use a realistic outdoor portrait — a person in natural light, not a studio. This grounds the UX in the actual use case.

**Shutter button:** Reference an actual iPhone 16 Camera app screenshot when drawing the shutter. The outer ring to inner fill ratio, the gap, and the exact white are critical to the native feel.
