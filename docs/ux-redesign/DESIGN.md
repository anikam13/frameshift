# FrameShift — Visual Design System

**Status:** Design brief v1, approved direction; visual token values other than noted accent are provisional until mockups are reviewed.  
**Platform:** Native iOS, portrait-first.  
**North star:** An editorial, photo-forward inspiration gallery flows into a precise, unobtrusive Apple-native camera. Make taking the shot feel effortless.

## Experience principles

1. **Photographs lead.** Photos, not explanatory copy, supply personality and hierarchy.
2. **Shoot fast.** Returning users with a previously used reference can enter the camera directly. Familiar references are one tap away.
3. **Guide, don't lecture.** One calm, actionable coaching instruction at a time. Use real UI for first-use teaching.
4. **Native familiarity, selective signature.** Prefer familiar iOS affordances, sheets, context menus, gestures, haptics and transitions. Custom motion should serve composition.
5. **Progressive disclosure.** Keep common camera actions visible; place secondary controls in a compact camera menu.
6. **No unnecessary management.** Photos save to Apple Photos, sessions group automatically, and FrameShift does not become a second photo archive or full editor.

## Visual language

### Appearance
- **Gallery:** follows system Light / Dark appearance, with an editorial rather than dashboard feel.
- **Camera:** consistently dark chrome, maximizing the usable live preview.
- **Accent:** use the yellow associated with Apple's Camera UI as the visual reference. `#FFD60A` is a **provisional design token**, not a claim that this is Apple's exact internal color. Confirm contrast and appearance in mockups.
- **Neutral palette:** prefer system semantic colors/materials for adaptive interfaces. Avoid gratuitous fixed gray palettes.
- **Yellow usage:** active manual camera controls, confirmed alignment, selective focus. Do not fill the gallery with yellow buttons.
- **Typography:** San Francisco system font and native Dynamic Type where appropriate. Gallery wordmark is compact and editorial, not an oversized `References` heading.
- **Surfaces:** subtle translucent camera pills and panels with adequate contrast; rounded controls where useful; minimize borders, shadows and stacked cards.
- **Spacing:** comfortable, consistent native spacing. Favor generous photo area. Exact spacing/radii to be determined during mockups rather than presenting guessed values as final rules.

## Gallery system
- Compact **FrameShift** wordmark, plus (`+`) import button, and unobtrusive access to general settings. When an active camera session exists, show a subtle **Resume Camera** shortcut.
- Header and composition category chips remain sticky while scrolling; quick-access reference row scrolls away.
- A **single compact horizontal row** merges favorites and frequently used references, with favorites prioritized and duplicates removed.
- **Explore / Yours** segmented control switches between curated and personally imported references; quick-access row remains above both.
- **Explore:** two-column, consistently portrait-cropped photo grid with horizontal composition filter chips: `All`, `Full Body`, `Portraits`, `Seated`, `Couples`, `Groups`.
- **Yours:** same two-column visual treatment, ordered most recently imported first.
- Subtle bookmark indicator for favorited curated images only; do not badge recently used photos.
- No technical category overlays or long captions on image tiles. Curated photos should be visually excellent and varied, not generic sample imagery.
- Long-press any reference for native photo preview and context actions (favorite/unfavorite, share, remove where applicable); give accessible menu alternatives.
- Tapping a favorite/recent item enters the camera directly. Tapping a curated grid tile opens its immersive preview. Importing opens a preview.

## Immersive reference preview
- Photo fills the available canvas with minimal chrome, an unobtrusive back/close affordance and one primary **Recreate** action.
- Swipe horizontally among neighboring references.
- Long-press context actions may be available without permanent management icons.
- Recreate causes the photo to morph gracefully into a translucent camera overlay; keep motion brief and offer a Reduce Motion fallback.
- No composition-parameter paragraphs or explainer cards.

## Camera system
- Dark, Apple-native camera chrome, portrait interface.
- Always-visible essentials: reference thumbnail plus adjacent picker chevron, Overlay and Guides mode icon buttons near the top, zoom presets, shutter, camera flip, recent-capture thumbnail with small top-right count badge, and navigation back to gallery.
- Flash and secondary capture controls live in a compact expandable camera menu. General app settings live in the gallery, not this menu.
- **Reference thumbnail:** tap toggles reference overlay (see interaction contract in UX-SPEC), while adjacent chevron opens the expandable reference picker.
- **Mode controls:** Overlay and Guides are adjacent compact icon buttons; manually selected state gets Apple-yellow highlighting. Never show both manually selected.
- **Overlay:** reference picture over live camera at fixed **35% opacity**. No opacity slider and no per-reference opacity customization.
- **Guides:** one thin fixed target head-position circle, plus a contextual level that appears when noticeably tilted and fades once aligned. Guides stay visually minimal; avoid additional rings or arrows.
- **Coaching pill:** small translucent, floating, one instruction at a time, independent of visual aids. Tap to collapse into small indicator; tap to reopen. A quiet ready state with small yellow checkmark is the current **provisional** choice, not yet user-confirmed.
- **Alignment:** target guides turn yellow when thresholds are satisfied; one subtle haptic and brief confirmation, with stability/hysteresis/cooldown to avoid repeats. Confirm success only when real signals support it.
- **Zoom:** available camera-dependent presets, with finer adjustment on long press/drag; no hardcoded unsupported lenses.
- **Capture:** Apple Camera-like brief shutter feedback, capture sound as appropriate to platform/device settings, immediate thumbnail and counter update after a successful save.

## Session gallery + photo viewer
- Tap the recent-capture thumbnail/count to open this session's chronological **Apple Photos-style grid**.
- Top-header camera shortcut returns directly to the current capture workspace.
- Full-screen photo viewer: swipe between captures; press and hold image to show reference used for that shot; release to return to the capture. Make an accessible non-hold comparison alternative during design testing.
- Multi-select via a visible `Select` action; checkmarks and bottom bar support `Add to References` and `Share`.
- No filter editing screen. No separate save step for captures, which save automatically to Apple Photos.
- Older captures are accessed in Apple Photos, not a FrameShift history library.

## Motion and tactility
- Use restrained, spring-like native transitions where appropriate; do not animate for decoration alone.
- Reference preview -> camera: selected photo becomes the live overlay.
- Adaptive camera startup: overlay to Guides dissolves after stable subject detection for roughly 1–2 seconds.
- Alignment: brief yellow confirmation and a single restrained haptic.
- Shutter: native-feeling animation and count refresh, no elaborate flying-photo transition.
- Honor Reduce Motion, VoiceOver, sufficient contrast, 44pt-or-larger hit targets where feasible, and native context/menu accessibility.

## Anti-patterns to remove from the existing app
- Three explanatory onboarding slides before entering the actual product.
- Exposition-heavy 'Try sample references' view.
- Oversized `References` header, numerous competing action buttons, and permanent Reference/Camera tabs.
- Excessively technical photo categories in primary browsing.
- Always-present opacity percentage/slider or complex per-photo settings.
- Full-screen filter editing as a required post-capture step.
- Repeated long-form descriptive copy explaining the technology.

## Still to resolve in mockups or engineering validation
- Exact pixel typography, padding, radii and image crop behaviors.
- Final icon choices and the specific gallery settings / Resume Camera placements.
- Which actions exist for bundled samples versus imported assets (e.g. removal semantics and licensing).
- The exact tap-to-toggle versus manual-mode state handling for reference thumbnail; see interaction ambiguity in UX-SPEC.
- Face-detection confidence thresholds and whether adaptive guidance must consider body visibility for non-portrait compositions.
- Exact first-use spotlight order, camera permission timing, and non-blocking fallback.
- Clean compare alternative for accessibility and long-press conflicts.
