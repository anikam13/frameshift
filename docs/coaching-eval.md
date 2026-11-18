# Coaching eval (on device)

Resolves open questions **O-5** (detection) and **O-6** (coaching thresholds,
haptics) in `design-decisions.md`. Run it on a real iPhone — the Simulator has
no camera and Vision fails there.

## Setup

1. Run a **Debug** build from Xcode on your iPhone.
2. You need a helper to be the subject (front-camera scenarios: just you).
3. Camera → `⋯` → **Coaching Eval**. A readout appears bottom-left of the
   viewfinder. It's debug-only and never ships.

What the readout shows (✓ = that axis is inside its "good" band):

| Row | Meaning | Good band (current) |
|---|---|---|
| subject | a person is detected | — |
| head off | head center vs. target circle, in circle radii | ≤ 0.75 r (loses ✓ past 1.15) |
| shoulder | live / reference shoulder width (distance) | ×0.84–1.16 (loses past ±0.26) |
| roll err | degrees off the reference's level; `off` = not coached | ≤ 1.4° (loses past 2.3°), widened when pointing up/down |
| pitch err | degrees off the reference's up/down tilt; `off` = not coached | ≤ 2.9° (loses past 4.6°) |
| light | lighting score 0–1 | ≥ 0.50 (loses below 0.38) |
| tip | the instruction currently in the coaching pill | |
| aligns | alignment confirmations (yellow + haptic) | |
| tips / rapid | tip changes / changes < 1 s after the previous one (flicker) | |
| level | level haptics | |
| drops | times the subject was lost | |
| 1st | seconds from Reset to first alignment | |

## Each run

1. Pick the reference for the scenario.
2. Tap **Reset** on the readout.
3. Do the scenario for about 30–60 s.
4. Tap **Copy** → paste the line into the results table below, replace `S?`
   with the scenario number, and add your 1–5 rating and notes.

## Scenarios

### Detection (O-5)

| # | Scenario | Reference | Look for |
|---|---|---|---|
| S1 | Baseline: helper standing, good daylight, back camera | Stone Lean (full body) | Aligns within ~20 s; tips make sense |
| S2 | Seated subject | Sofa Profile or Dinner Table | Detects a seated body; distance tip not fooled by crossed legs |
| S3 | Low light (dusk / dim room) | Any full body | `subject` stays yes; light tip appears, not a framing tip |
| S4 | Two people in frame | Any single-person | Coaches one person consistently; head off doesn't jump between people |
| S5 | Front camera selfie, arm's length | Promenade Glance (portrait) | Tilt direction tips are correct (not inverted) |
| S6 | Subject walks out and back in | Any | `drops` counts it; collapsed pill stays collapsed; "Looking for subject" shows |
| S7 | Back-facing subject | Patio Glance | Still detected? Head circle sensible? |
| S8 | Imported landscape reference | Your own wide photo | Overlay and circle land in the right place |
| S9 | Imported couple / group reference | Your own photo | What does it coach against? (Note it — decides group support) |

### Thresholds and haptics (O-6)

| # | Scenario | Pass when |
|---|---|---|
| T1 | Get aligned, then hold still for 20 s | rapid = 0, aligns = 1 |
| T2 | Misalign and realign on purpose 5 times | aligns = 5, one haptic each, none in between |
| T3 | Sway slowly at the edge of alignment | no buzzing: aligns ≤ 2, rapid ≤ 2 |
| T4 | Tilt the phone slowly through level, 5 times | level = 5, no extra buzzes |
| T5 | Helper follows tips with no other help | 1st ≤ 20 s; every tip moved them the right way |

## Overall pass bar

- Baseline S1/T5: first alignment ≤ 20 s.
- Flicker: rapid ≤ 2 per minute in any scenario.
- No tip ever points the wrong way.
- Haptics: one per real alignment / level crossing.
- Average rating ≥ 4.

## Results

| Run (pasted line) | Rating 1–5 | Notes |
|---|---|---|
| | | |

## Turning results into changes

| Symptom | Constant (in `Services/CompositionCoach.swift` unless noted) |
|---|---|
| Too hard to align / never ✓ on head | `headOffsetSatisfy` / `headOffsetUnsatisfy` |
| Distance tip nags or never settles | `shoulderRatioSatisfy` / `shoulderRatioUnsatisfy` |
| Level nags / level haptic buzzes | `levelSatisfy` / `levelUnsatisfy`; `MotionService` level band |
| Tilt nags | `angleSatisfy` / `angleUnsatisfy` |
| Light tip too eager | `lightingSatisfy` / `lightingUnsatisfy` |
| Guides switch too early/late | `CameraViewModel.stableDetectionDelay` (1.5 s) |
| Wrong person coached, misses seated/back views | `LiveVisionAnalyzer` (detection choice/confidence) |

Send me the results table and I'll tune the constants from it.
