# FrameShift — Accounts & Paid Features PRD (Post-v1.0 Roadmap)

**Status:** Not part of the current App Store submission. `appstore-readiness-prd.md` ships first, as-is: no accounts, no backend, fully on-device, free. This document is for a *later* update, once v1.0 is live.

**Goal:** Add an optional paid tier without disturbing the free experience that already shipped. Existing users should notice nothing different unless they go looking for it.

**Core principle — seamless:** the free, on-device, account-free experience stays exactly as-is. No login wall, no forced account creation, no change to first launch. An account is only ever prompted at the moment someone taps to buy the paid tier or wants to restore it on a new device.

**Provisional, not locked:** backend/auth approach below is a working default so this doc isn't blocked on an infrastructure decision that doesn't matter yet. Revisit before implementation actually starts — by then, requirements or Apple's platform may have shifted anyway.

---

## Open decisions (fill in before build starts)

- [ ] **What's actually Pro?** Candidates from the current feature set: unlimited references (vs. a free cap), burst capture, match-silhouette flash, before/after export card without watermark, additional export formats. This is a monetization/business call, not a technical one — can't be assumed here.
- [ ] **Pricing model:** one-time unlock (non-consumable IAP) vs. auto-renewable subscription. Changes the StoreKit implementation meaningfully.
- [ ] **Backend/auth approach** (provisional default below): Sign in with Apple + CloudKit, vs. a custom server, vs. a third-party BaaS (Firebase/Supabase). The third option reverses "no third-party dependencies" on top of the accounts reversal — worth a deliberate call, not a default.

---

## Provisional architecture (default, not final)

- **Auth:** Sign in with Apple (`AuthenticationServices`) — Apple's own framework, no third-party SDK, no password to manage.
- **Backend:** CloudKit private database, keyed to the user's iCloud account — stores purchase entitlement records and enables restoring/syncing the paid tier across a user's devices. No server to build, host, or maintain.
- **Payments:** StoreKit 2, Apple's own in-app purchase framework — required regardless of backend choice, since digital features/subscriptions inside an iOS app must go through Apple's IAP system.

Constraints this reverses from `CLAUDE.md` (to be updated when this is actually built, same pattern as the onboarding-carousel and settings-menu decisions): *"No backend. No account."* and *"No account, login, or network calls of any kind."* Reversal is scoped narrowly — the free tier keeps making zero network calls; only the purchase/restore flow touches the network at all.

---

## F1 — Paywall entry point (P0, when this ships)

**Requirements:**
1. A "FrameShift Pro" row in the Settings menu (`settings-menu-prd.md` F6, About section, or its own section) — the only place the paid tier is ever mentioned. Nothing on the camera screen, references screen, or onboarding changes.
2. Tapping it shows what's included (from the "what's Pro" decision above) and a StoreKit purchase sheet.
3. Users who never tap this row never see a sign-in prompt, network call, or paywall of any kind.

## F2 — Sign in with Apple, purchase-triggered only (P0, when this ships)

**Requirements:**
1. Sign-in is presented only at the moment of purchase or "Restore Purchase" — never on launch, never blocking any existing feature.
2. Declining sign-in cancels the purchase flow cleanly; the app returns to exactly the state it was in before, no dead ends.

## F3 — Entitlement storage & restore (P1)

**Requirements:**
1. On successful purchase, write an entitlement record to the user's CloudKit private database (or whatever backend is chosen).
2. "Restore Purchase" reads that record on a new device/reinstall and unlocks Pro features without repurchasing, per Apple's requirements for non-consumable/subscription IAP.

## F4 — Feature gating (P1)

**Requirements:**
1. Whatever's decided under "what's Pro" gets a single shared `isPro` check (e.g. on `AppState`), read by the relevant screens.
2. Gated features degrade gracefully when not purchased — e.g. show the feature with a small lock/Pro badge rather than hiding it outright, so free users know it exists (standard freemium pattern) without it being disruptive.

## F5 — Privacy & compliance updates (P0, when this ships)

**Requirements:**
1. App Privacy label in App Store Connect changes from "Data Not Collected" to reflect whatever CloudKit/Sign in with Apple actually collects (Apple ID identifier at minimum).
2. Privacy policy updated to disclose the account/purchase data path, while still being able to state the core photo-processing pipeline remains fully on-device.
3. Paid Applications Agreement signed in App Store Connect (banking/tax info) before any IAP product can go live — non-code, same category as the existing App Store readiness PRD's appendix.

---

## Non-goals (still, even post-v1.0)

- No social login (Google/Facebook/etc.) — avoids the Sign in with Apple parity requirement (Guideline 4.8) entirely by only offering Sign in with Apple in the first place.
- No mandatory account for any existing free feature.
- No third-party SDKs, if the provisional CloudKit/StoreKit path holds.
