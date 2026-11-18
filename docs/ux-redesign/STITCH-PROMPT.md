# Google Stitch Prompt — FrameShift UX Redesign

Redesign FrameShift, an existing native iOS photo-composition coaching camera. This is a **complete visual rethink**, not a reskin of the attached screenshots. Use `DESIGN.md`, `UX-SPEC.md`, `SCREEN-INVENTORY.md`, and the existing app screenshots as references. The screenshots show existing functionality and problems; do not preserve their present layout automatically.

Create a coherent, high-fidelity iPhone UX with an **editorial, visually striking, photo-forward references gallery** and a **dark, clean Apple-native camera**. The gallery follows iOS system light/dark mode. Use restrained Apple-Camera-like yellow for deliberate interaction and alignment feedback. Prefer SF system typography, native-feeling sheets, minimal copy, subtle translucent camera pills and clean spacing. Avoid generic AI-generated dashboard cards, verbose onboarding, oversized headings, permanent camera/gallery tabs and filter editor UI.

Design these connected screens and states:
1. Explore gallery with small FrameShift wordmark, + import, optional Resume Camera, one compact combined favorites/frequently used row, Explore/Yours switch, horizontally scrollable composition chips (All, Full Body, Portraits, Seated, Couples, Groups), and a two-column uniform portrait curated grid.
2. Yours gallery with same chrome, newest imported photo first.
3. Immersive curated reference preview with minimal controls and Recreate button, horizontally swipable.
4. Camera when opening a new reference: 35% translucent photo overlay; dark camera controls; reference thumbnail + adjacent picker chevron; two compact adjacent Overlay and Guides icon buttons; zoom, shutter, camera flip and recent capture thumbnail with small top-right session count badge.
5. Camera after stable person detection: overlay gently transitions to one precise fixed head target circle and contextual level; short translucent live coaching pill.
6. Manual Overlay, Guides and clean visual states; camera coaching pill remains available independently.
7. Quick reference picker as a medium-height bottom sheet with favorites/recents; expanded state becomes full Explore/Yours gallery.
8. Chronological session photo gallery, full-screen capture viewer, and multi-select mode with Add to References and Share.
9. In-context first-use spotlight hints, not traditional intro slides.

Show meaningful **interaction and transition diagrams** where static layouts cannot express behavior: selected reference morphs into overlay; automatic overlay -> guides transition after 1–2 seconds of stable person detection; tapping Overlay/Guides overrides adaptive behavior until new reference/session; switching reference restarts adaptive behavior without resetting session photo count; capture confirmation and counter update; hold image to see original reference.

Do not invent functionality outside the supplied UX spec. Where a behavior is explicitly marked provisional or unresolved, present it as an option for review rather than as a settled requirement. The output should work as a source for later **native SwiftUI implementation**, not require shipping generated HTML/CSS.

First produce a consistent design direction and 4 core screens (Explore gallery, reference preview, adaptive Overlay camera, Guides camera). Once approved, extend the system to the remaining screens. Include a compact reusable component and token overview.
