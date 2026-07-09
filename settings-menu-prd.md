# FrameShift — Settings Menu PRD

**Goal:** Give users a single place to configure camera-guide defaults, manage on-device storage, and check permissions/app info — without touching the camera screen itself.

**Entry point:** a gear icon in `ReferencesView`'s toolbar (leading side, opposite the existing "+" add-photos button), presenting `SettingsView` as a sheet. This keeps `CLAUDE.md`'s hard constraint intact: *"No settings panel or drawer accessible from the camera screen."* This PRD is additive — no reversal, no `CLAUDE.md` changes needed.

**Non-goals:** accounts, sign-in, cloud sync/backup, analytics opt-in/out (none exists), light-mode toggle (app is dark-only by design), anything requiring a network call.

Features are listed in implementation order. Each should leave the app in a shippable state.

---

## F1 — Settings entry point & screen shell (P0)

**Problem:** There's no settings surface anywhere in the app today.

**Requirements:**

1. Add a gear (`gearshape`) `ToolbarItem(placement: .topBarLeading)` to `ReferencesView`, opening a `.sheet` presentation of a new `SettingsView`.
2. `SettingsView` is a `NavigationStack` wrapping a native `List`/`Form`, sectioned per the features below. Standard iOS Settings look — grouped list style, no custom chrome.
3. A "Done" button (`.confirmationAction` toolbar placement) dismisses the sheet.
4. Empty sections (e.g., before F2–F6 land) must not be built — this feature exists only to host the sections that follow; ship it together with at least F2.

**Acceptance:** Tapping the gear in References opens Settings; Done dismisses; nothing else in the app changes.

**Files:** new `Screens/Settings/SettingsView.swift`; `Screens/References/ReferencesView.swift` (toolbar item + sheet state).

---

## F2 — Camera guide defaults (P1)

**Problem:** `CameraToolDrawer`'s five toggles (LEVEL, GRID, CIRCLE, TIPS, MATCH) live as in-memory `@Published` state on `CameraViewModel`, hardcoded to default `true` every launch. There's no way to set a lasting preference (e.g., someone who always dismisses GRID has to do it every session).

**Requirements:**

1. Back each of the five toggles with `@AppStorage` (e.g. `frameshift.defaultGridVisible`, `...defaultLevelVisible`, `...defaultHeadCircleVisible`, `...defaultTipsEnabled`, `...defaultMatchSilhouetteEnabled`), all defaulting to `true` to match current behavior.
2. `CameraViewModel`'s five `@Published` properties initialize from these stored defaults instead of a literal `true`.
3. Add a "Camera Guides" section to `SettingsView` with a toggle per item, same labels as the drawer (Level, Grid, Head Circle, Composition Tips, Match Flash).
4. The in-session drawer toggle still works as a quick override for the current camera session; it does not write back to the persisted default (Settings is the only place that changes what a *fresh* session starts with — matches how iOS Camera itself separates "Preserve Settings" from in-session toggles).

**Acceptance:** Turning a guide off in Settings → next time the camera screen appears, that guide starts off. Toggling it back on in the in-camera drawer only affects the current session, not the stored default.

**Files:** `Screens/Camera/CameraViewModel.swift`, `Screens/Settings/SettingsView.swift`.

---

## F3 — Data & storage management (P1)

**Problem:** `ReferenceStore` and `CapturedStore` grow unbounded (especially with burst capture) with no visibility or way to clear them short of deleting the app.

**Requirements:**

1. "Storage" section showing approximate on-disk size of the References and Captures directories (sum file sizes via `FileManager.attributesOfItem`, computed off the main thread, formatted with `ByteCountFormatter`).
2. "Clear All References" — destructive, confirmation dialog ("This removes all imported references from FrameShift. This can't be undone."). Clears `AppState.references` and the underlying `ReferenceStore` files. Does not touch captured shots.
3. "Clear All Captured Shots" — destructive, confirmation dialog explicitly noting shots already saved to the system Photos library are unaffected (consistent with existing single-shot delete behavior in `GalleryPreviewView`). Clears `AppState.capturedShots` and `CapturedStore` files only.
4. Both actions must degrade gracefully on partial failure (reuse the existing `try?`-based silent-failure convention already used by both stores) — never crash, never leave the in-memory and on-disk state inconsistent.

**Acceptance:** Storage figures roughly match reality; both clear actions empty the respective in-app list and free disk space; Photos library untouched by the captured-shots clear.

**Files:** `Services/ReferenceStore.swift`, `Services/CapturedStore.swift` (read-only size helpers), `App/AppState.swift` (clear-all methods), `Screens/Settings/SettingsView.swift`.

---

## F4 — Permissions shortcuts (P2)

**Problem:** Camera-denied state already has an in-camera "Open Settings" flow (App Store readiness PRD, F2), but there's no equivalent for checking Photos access, and no single place to see both at a glance.

**Requirements:**

1. "Permissions" section listing Camera and Photos (add-only) status as read-only text (Authorized / Limited / Denied / Not Determined), reading `AVCaptureDevice.authorizationStatus(for: .video)` and `PHPhotoLibrary.authorizationStatus(for: .addOnly)` on appear.
2. A single "Open System Settings" row below, using `UIApplication.openSettingsURLString` — iOS only exposes one settings deep link per app, so this isn't per-permission, just a shared shortcut.
3. Statuses refresh when the sheet reappears (e.g. after returning from Settings), not just once on first presentation.

**Acceptance:** Denying/granting a permission in Settings and reopening this screen shows the updated status without relaunching the app.

**Files:** `Screens/Settings/SettingsView.swift`.

---

## F5 — Onboarding & hints reset (P2)

**Problem:** Onboarding (`Screens/Onboarding/`) and the in-camera reference hint are both one-time, `@AppStorage`-gated experiences with no way to see them again short of reinstalling.

**Requirements:**

1. "Replay Onboarding" row presents `OnboardingView` as a `.fullScreenCover` directly from Settings (does not require relaunching the app or touching `hasCompletedOnboarding` until the user actually finishes it again, so dismissing mid-replay doesn't strand them without the completed flag).
2. "Show Reference Hint Again" row resets `frameshift.hasSeenReferenceHint` to `false`.

**Acceptance:** Replay Onboarding shows the exact same 4-page flow as first launch; finishing it or backing out doesn't break the app's normal `hasCompletedOnboarding` gate. Resetting the hint makes it reappear next time Camera mode has zero references.

**Files:** `Screens/Settings/SettingsView.swift`, `Screens/Onboarding/OnboardingView.swift` (if it needs a non-launch entry path).

---

## F6 — About (P2)

**Problem:** No in-app way to see version info or the privacy promise the app is built around.

**Requirements:**

1. "About" section: app version + build number from `Bundle.main.infoDictionary` (`CFBundleShortVersionString` / `CFBundleVersion`).
2. Static privacy statement matching the onboarding/export-card language: "FrameShift processes everything on-device. Nothing is uploaded or collected."
3. Privacy policy link (external URL, opens in Safari via `Link` or `UIApplication.shared.open`) — URL itself is a non-code deliverable (see App Store readiness PRD's appendix); this row can ship pointing at a placeholder until that URL exists.

**Acceptance:** Version/build match the actual build; privacy text present; link opens Safari (or is a no-op until the URL is supplied, whichever lands first — don't block this feature on the URL).

**Files:** `Screens/Settings/SettingsView.swift`.
