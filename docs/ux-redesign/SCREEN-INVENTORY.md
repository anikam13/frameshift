# FrameShift — Screen Inventory and Prototype Checklist

Build the full user journey before polishing isolated screens. Treat screenshots in `current-screens/` as **as-is source references**, not approved target designs.

| Priority | Screen or state | Required design treatment | Key interactions |
|---|---|---|---|
| P0 | 01 — Explore gallery (first-ever launch) | FrameShift header, + import, shared quick-access row when populated, Explore/Yours toggle, category chips, 2-column editorial grid | Choose curated ref; filter; import |
| P0 | 02 — Explore gallery (returning with saved refs) | Compact favorites/most-used horizontal row, gallery header with optional Resume Camera, photo grid | Tap go-to -> camera; long press preview/menu |
| P0 | 03 — Yours gallery | Imported grid newest first, same chrome and quick-access row | Select imported ref; long-press management |
| P0 | 04 — Curated reference preview | Immersive single photo, swipe between references, Recreate | Horizontal swipe; Recreate morph |
| P0 | 05 — Camera: adaptive Overlay start | Translucent reference at 35%; UI essentials, two mode buttons not manually highlighted | Stable person detection -> Guides |
| P0 | 06 — Camera: adaptive Guides | Target head circle, contextual level, one coaching instruction | Shoot, change ref, mode selection |
| P0 | 07 — Camera: manually selected Overlay / Guides / Clean | Distinct manual state highlight, coaching always independently present | Tap to lock/toggle; turn off for clean |
| P0 | 08 — Camera: alignment achieved | Subtle yellow guides, pill confirmation, one haptic | Stay ready without repeated visual noise |
| P0 | 09 — Camera reference picker (half sheet) | Favorites and recents above live camera | Tap reference; swipe sheet up |
| P0 | 10 — Expanded reference picker (full sheet) | Explore/Yours, composition chips, curated grid | Browse and select ref; dismiss |
| P0 | 11 — Session gallery | Chronological grid, header camera shortcut, Select, photo count | Tap viewer; select multiple |
| P0 | 12 — Session photo viewer | Full-screen captured photo, minimal chrome | Hold to reference; release; swipe captures |
| P0 | 13 — Session gallery multi-select | Checkmarks and bottom action bar | Add to References; Share; success stays here |
| P1 | 14 — First-use spotlight states (3 steps) | Contextual hints over actual gallery/camera controls | Dismiss on performed action, skip |
| P1 | 15 — Camera permission explanation | Single lightweight contextual prompt before native dialog | Continue; permission recovery |
| P1 | 16 — Gallery settings menu | Small general settings entry, no extra dashboard | Open app info/help |
| P1 | 17 — Camera secondary menu | Flash and secondary options only | Expand/dismiss |
| P1 | 18 — Error and empty states | Camera denied, Photos save failure, analysis failure, zero imports | Meaningful retry, don't dead-end |

## Prototype journeys

1. **New user:** open Explore -> choose curated sample -> preview -> Recreate -> permission -> camera overlay -> Guides -> capture -> session gallery -> compare.
2. **Fast repeat:** relaunch -> last-used reference in camera -> capture several -> tap photo+count -> browse -> return to camera.
3. **Switch composition:** camera -> picker half sheet -> favorite or expand full Explore -> select new reference -> adaptive Overlay -> Guides; session count preserved.
4. **Recreate your own shot:** session gallery -> Select multiple -> Add to References -> confirmation, stays in gallery -> later open Yours -> shoot.
5. **Adjust view:** switch automatic / manual Overlay / manual Guides / manual Clean; collapse coaching pill and restore it.

## Design acceptance checks

- Can a new user understand how to take a photo without reading an explainer page?
- Can a returning user start shooting with their last reference as soon as camera permission permits?
- Can a photographer switch between three favorite references without leaving the camera?
- Can someone browse curated samples without scrolling past verbose onboarding or utility cards?
- Is the shutter and current session count visible even when coaching is active?
- Are camera and gallery visually distinct but recognizably the same product?
- Is the difference between visual mode selection and automatic transition understandable?
- Are all essential interactions reachable without relying exclusively on long-press or gestures?
