# FrameShift — App Store Readiness PRD

**Goal:** Ship FrameShift v1.0 to the App Store as a login-free, fully on-device camera app.
**Non-goals:** Accounts, backend, analytics, iPad layout, video, photo editing, localization beyond English.

Features are listed in implementation order. Each feature should leave the app in a shippable state: build passes, no feature depends on a later one.

Constraints carried over from CLAUDE.md: SwiftUI only, no third-party dependencies, Apple frameworks only, design tokens as defined there (except where this PRD or prior user direction supersedes — e.g. the translucent shutter ring).

---

## F1 — Captured photo persistence (P0)

**Problem:** `AppState.capturedShots` is in-memory only. Quitting the app destroys every photo the user has taken. Nothing writes to the system photo library.

**Requirements:**

1. On every successful capture, save the photo to the user's photo library via `PHPhotoLibrary.shared().performChanges` (add-only access; `NSPhotoLibraryAddUsageDescription` is already configured in build settings). Use `PHPhotoLibrary.authorizationStatus(for: .addOnly)` / `requestAuthorization(for: .addOnly)`.
2. If add-to-library permission is denied, captures must still work: keep the in-app copy and surface a one-time, non-blocking notice (small banner/toast in camera view) that photos aren't being saved to the camera roll, with a "Settings" action.
3. Persist the in-app gallery to disk so `capturedShots` survives relaunch. Mirror the `ReferenceStore` pattern: new `CapturedStore` service (FileManager + Codable manifest in Application Support) storing image data (JPEG/HEIC at capture quality), `id`, `capturedAt`, `referenceID`.
4. `AppState.addCapturedShot` writes through to `CapturedStore`; `removeCapturedShot` deletes from it. Deleting in the in-app gallery does NOT delete from the system photo library (matches how third-party camera apps behave).
5. Restore captured shots on launch in `FrameShiftApp`/`AppState.restoreReferences()`-style flow (`restoreCapturedShots()`), newest first.
6. Save failures (disk or Photos) must never crash or lose the in-memory copy; log and continue.

**Acceptance:** Take photo → appears in Photos app. Relaunch FrameShift → shot still in gallery thumbnail + preview. Deny add-only permission → capture still works, notice shown once. Delete in-app → gone from app, still in Photos.

**Files:** new `Services/CapturedStore.swift`; `App/AppState.swift`, `App/FrameShiftApp.swift`, `Models/CapturedPhoto.swift` (Codable manifest entry), `Screens/Camera/CameraView.swift` (banner).

---

## F2 — Camera permission denied state (P0)

**Problem:** `CameraService.isAuthorized` is published but no view reads it. If camera access is denied, the app is a black rectangle with no explanation.

**Requirements:**

1. When camera authorization is denied/restricted, the viewfinder area shows a centered state: camera SF symbol, "FrameShift needs camera access", one-line explanation, and an "Open Settings" button that opens `UIApplication.openSettingsURLString`.
2. State must appear both when permission was previously denied (on launch) and immediately after the user denies the first-run prompt.
3. All capture-dependent chrome (shutter, zoom circles, flash, drawer tools) is hidden or disabled in this state; the mode pill and REFERENCE mode remain fully usable.
4. If the user grants permission in Settings and returns (foreground notification), the session starts without requiring an app relaunch.

**Acceptance:** Deny camera in Settings → launch app → clear explanation + working Settings deep link; grant in Settings → return to app → live viewfinder appears.

**Files:** `Screens/Camera/CameraView.swift`, `Screens/Camera/CameraViewModel.swift`, `Services/CameraService.swift` (publish denied vs. undetermined, observe `willEnterForeground`).

---

## F3 — Wire the post-shot flow: recommendations + before/after export card (P1)

**Problem:** `PostShotView`, `PostShotViewModel`, `RecommendationCard`, and `ExportService` exist but are unreachable dead code. Either they ship wired or they get deleted; this PRD wires them, since the before/after card is the app's shareable moment.

**Requirements:**

1. After a capture **taken with an active reference**, show the post-shot screen (sheet or fullScreenCover over camera) with: captured photo, the reference, and `RecommendationCard`s from `PostShotViewModel`. Captures without a reference skip this screen entirely (straight to thumbnail, like today).
2. Post-shot screen actions: "Done" (dismiss, keep shooting) and "Share card" (generate before/after via `ExportService`, present share sheet). Saving the card also writes it to Photos per F1 rules.
3. The post-shot screen must be skippable fast — one tap, no forced flow. Camera session stays warm underneath.
4. Audit `PostShotView`/`ExportService` against the current models before wiring (they predate `ShotSpec` growth); fix compile/logic drift rather than rewriting.
5. If any of the four files turn out to be fundamentally broken or off-spec, fallback decision: cut recommendations, keep only the export card action (reachable from gallery, see F4), and delete the rest. Note the choice in the commit message.

**Acceptance:** Capture with reference active → post-shot screen appears with populated recommendations → Share card produces a correct before/after image in the share sheet. Capture with no reference → no interruption.

**Files:** `Screens/PostShot/*`, `Services/ExportService.swift`, `Screens/Camera/CameraView.swift` (present after capture), `App/AppState.swift` if the shot→reference lookup needs a helper.

---

## F4 — Make gallery preview buttons real (P1)

**Problem:** Heart, info, and edit-sliders buttons in `GalleryPreviewView` are visual-only. Non-functional UI is an App Review rejection risk (guideline 2.1).

**Requirements:**

1. **Heart:** persisted favorite. Add `isFavorite: Bool` to `CapturedPhoto` + `CapturedStore` manifest (depends on F1). Toggling updates immediately and survives relaunch.
2. **Info:** tapping opens a compact sheet: capture date/time, image dimensions, and — when `referenceID` resolves — a thumbnail of the reference it was shot against. No EXIF display (hard constraint in CLAUDE.md).
3. **Sliders button:** repurpose as the before/after export-card action (from F3's `ExportService`) for shots with a linked reference; hidden for shots without one. If F3 took the fallback path, this is the only entry point to the card.
4. No button in the preview may be a no-op when the build is submitted.

**Acceptance:** Every visible button in the gallery preview does something observable; favorites survive relaunch; info sheet shows correct data; export card generates from gallery.

**Files:** `Screens/Library/GalleryPreviewView.swift`, `Models/CapturedPhoto.swift`, `Services/CapturedStore.swift`, `Services/ExportService.swift`.

---

## F5 — Device targeting: iPhone-only, portrait-only (P2)

**Problem:** Reviewers run apps on iPad in landscape. The fixed 3:4 letterboxed layout and motion-based level are designed for handheld portrait iPhone.

**Requirements:**

1. `TARGETED_DEVICE_FAMILY = 1` (iPhone only) in both Debug and Release configurations.
2. Supported interface orientations: portrait only (`INFOPLIST_KEY_UISupportedInterfaceOrientations` / equivalent). No upside-down.
3. Verify minimum deployment target is intentional (iOS 17 APIs like two-parameter `onChange` and `safeAreaPadding` are already in use — set the target to match reality, not the iOS 16 aspiration in CLAUDE.md; update CLAUDE.md to say iOS 17+).
4. Confirm the app builds and runs correctly after the change; no other behavior changes.

**Acceptance:** Project builds with iPhone-only/portrait-only settings; rotating the device does not rotate the UI; CLAUDE.md matches the real deployment target.

**Files:** `FrameShift.xcodeproj/project.pbxproj`, `CLAUDE.md`.

---

## F6 — First-launch experience & empty states (P2)

**Problem:** A reviewer (and every new user) opens the app cold: no references, no captures. The core concept — import a reference, get guided to recreate it — is currently only discoverable by accident.

**Requirements:**

1. Camera mode with zero references: one-time coach mark or subtle persistent hint pointing at the REFERENCE segment of the mode pill ("Add a reference photo to get framing guides"). Dismissible, never shown again after the first reference is added (persist flag in `UserDefaults`).
2. REFERENCE mode empty state (exists in `ReferencesView`): tighten copy to sell the loop — e.g. "Save a shot you love from Pinterest or Instagram, then FrameShift guides you to recreate it." Keep the existing Add Photos button.
3. Gallery thumbnail placeholder (empty dark square) does nothing when tapped today — acceptable, but add `.disabled` semantics/no press feedback so it doesn't feel broken.
4. ~~No mandatory onboarding carousel. Zero screens between launch and live viewfinder.~~ **Reversed:** a mandatory 4-page first-launch onboarding carousel now runs before `RootTabView` (`Screens/Onboarding/`), gated on `@AppStorage("frameshift.hasCompletedOnboarding")`. It covers the reference → guided-framing → before/after loop and ends with the on-device-processing privacy disclosure. The in-camera hint (req. 1) still fires afterward for anyone who finishes onboarding without adding a reference yet — the two aren't mutually exclusive.

**Acceptance:** Fresh install (or wiped simulator) → onboarding carousel runs once, then hint visible in camera if no reference was added, empty state clearly explains the loop, nothing dead-ends. Relaunching after onboarding is completed skips straight to the camera.

**Files:** `Screens/Camera/CameraView.swift`, `Screens/References/ReferencesView.swift`, `Screens/Onboarding/*`, `App/FrameShiftApp.swift`, small `UserDefaults` flags.

---

## F7 — Failure-path hardening (P2)

**Problem:** Untested edge paths that App Review and real users will hit.

**Requirements:**

1. **Limited photo library access:** importing references with "Selected Photos" access must work (PHPicker is out-of-process, so it should already — verify and fix if the flow assumes full access anywhere).
2. **Capture failure:** `capturePhoto` completion with `nil` must not silently no-op forever — show a brief "Couldn't capture photo" toast.
3. **Disk-full / store write failure:** `CapturedStore`/`ReferenceStore` write errors degrade gracefully (in-memory copy retained, no crash).
4. **Front camera / no-telephoto devices:** verify zoom pills and virtual-device fallbacks on wide-only hardware paths (simulator + oldest supported device you can test).
5. **Interruption handling:** phone call / Control Center camera grab during a session — session restarts cleanly on return (handle `AVCaptureSession` interruption notifications if not already).

**Acceptance:** Each path manually exercised (simulator where possible, device otherwise) without a crash, hang, or silent dead state.

**Files:** `Services/CameraService.swift`, `Services/CapturedStore.swift`, `Screens/Camera/CameraViewModel.swift`, `Screens/Camera/CameraView.swift`.

---

## F8 — Release hygiene (P2)

**Requirements:**

1. App icon: verify `AppIcon.png` is 1024×1024 with **no alpha channel** (`sips -g hasAlpha`); flatten if needed.
2. Set marketing version `1.0`, build number `1`; confirm bundle ID `com.anirudhkamath.frameshift`, display name "FrameShift".
3. Remove dead code and stale references: anything F3 decided to cut, plus the legacy "Boyfriend Camera" naming in queue/label strings (`boyfriendcamera.session`, `boyfriendcamera.video`) — cosmetic but embarrassing in crash logs.
4. Full clean Release build + archive validates in Xcode Organizer without warnings that block upload.

**Acceptance:** `xcodebuild archive` succeeds; Organizer validation passes; icon check clean.

---

## Appendix — Non-code submission checklist (owner: Anirudh)

Not implementable in this repo, tracked here so nothing is forgotten:

- [ ] Apple Developer Program membership ($99/yr); create app record in App Store Connect
- [ ] Distribution certificate + provisioning (Xcode-managed signing is fine)
- [ ] Privacy policy URL (one page: "all processing on-device, no data collected, no accounts")
- [ ] App Privacy label: **Data Not Collected**
- [ ] Screenshots: 6.9" (iPhone 16/17 Pro Max) and 6.5" sets — camera with guides visible, references grid, gallery, before/after card
- [ ] Name ("FrameShift"), subtitle, description, keywords, category **Photo & Video**, support URL
- [ ] Age rating questionnaire (expect 4+)
- [ ] TestFlight pass on at least one physical device before submitting for review
