# Range — your knee is a hinge. So is this phone.

Range turns **iPhone Duo** into a clinical range-of-motion tool for rehab after knee replacement
(and elbow injuries). Drape the phone over the knee like a tent: a straight leg holds it flat
(180°), bending closes it — **flexion = 180° − hinge angle**. The phone *is* the goniometer.

Built for **Bitrig Hacks: iPhone Duo Edition** (YC, Sept 26 2026). SwiftUI, iOS 27.1, Xcode 27.1 beta.

## Run it

1. Open `Range.xcodeproj` in **Xcode 27.1 beta** (Swift packages resolve automatically — RevenueCat).
2. Pick the **iPhone Duo** simulator → Run.
3. Fold it: in Device Hub hold **⌥ Option** for the precise hinge slider, or script it:
   ```bash
   brew install artemnovichkov/tap/hinge    # or clone github.com/artemnovichkov/hinge
   ./scripts/demo.sh                        # beat-by-beat, press Enter between beats
   AUTO=1 ./scripts/demo.sh                 # runs straight through (recording)
   ```
4. **Drag the leg** on the session screen to test without folding — the knee follows your finger
   (click-and-drag with the mouse in the Simulator). Tap **Use hinge** on the pill to hand control back.
5. No scriptable hinge (e.g. Bitrig)? **… menu → Demo Controls → Run Full Demo (Autopilot)**,
   or launch with `-autopilot`.

Launch arguments: `-resetDemo` (fresh seeded data), `-startSession`, `-tab today|session|progress|care`,
`-unlockClinic` (demo entitlement), `-autopilot`, `-logHinge` (prints every hinge update).

Regenerate the project after adding files: `xcodegen generate` (see `project.yml`).

## The patient experience

| Moment | What happens | iPhone Duo API |
|---|---|---|
| Phone closed | Today card on the outer display: day 14, last best 84°, target 89°, and **how many reps** (− 10 +, remembered) | Size classes, vertical bars |
| Open | **She chooses where to start** — straight or bent. Hold still (or tap *Start here*) and the start locks; the **leveler** checks the thigh is flat. Reps are measured from her start | `CMMotionManager.deviceMotionBody` (`CMBodyIdentifiable`), hinge angle |
| Fold | Protractor pivots **exactly on the crease**; leg bends in sync | `onHingeChange`, `reservedRegions(kind: .division)` |
| Match last best | "Fold to 84° — this is where you were." The hardware is the progress meter | Hinge angle |
| Reps | **Ghost range** arc to beat, parking-sensor ticks toward the target, rising tone | Hinge velocity |
| Rushed rep | "Slow down — controlled movement"; it doesn't count toward the rep goal | Angular velocity |
| Reps | **One rep = out and back**: bend to the amber dot ("Bend to 89°"), then "Now back to 40°" to the blue start dot. Dots fill per clean rep, the coach counts aloud, "Set complete" at the goal | Hinge angle |
| Target | "Perfect. Hold." buzz + 5-second ring → milestone unlocked (Climb stairs) | Core Haptics + audio mirror |
| Close the phone | **Close-to-save**; recovery replay plays on the outer display (Day 1 → today) | Hinge status + angle |

Clinical rules baked in: adaptive target = median of last 3 peaks + 5° (+2° if pain ≥ 5),
±5° measurement-noise band (only real gains are celebrated), compensation detection (thigh lifts),
extension deficit, functional milestone ladder, typical post-TKA recovery band.

## Range Clinic (therapists)

Risk-sorted caseload (stiffness plateau, pain spike, missed days), live session badge, per-patient
chart, **RTM billing tracker** (16 data days / 30), SOAP progress note drafted with Apple's
**on-device Foundation Models** (template fallback), and a device-only **camera assessment** that
puts an interactive, patient-facing pain scale on the outer display via `CameraCaptureAccessory`.

## Monetization — RevenueCat

Range Clinic is sold through **RevenueCat**: offerings, `PaywallView` (RevenueCatUI),
purchases, restore, entitlement checks (`clinic`), `customerInfoStream`, and `CustomerCenterView`
for subscription management. Everything else uses the best native tool: SwiftData (storage),
Swift Charts, Core Haptics, AVFoundation (tones/voice), Core Motion, Foundation Models.

To go live, paste a key in `Range/Store/Secrets.swift`:
1. RevenueCat dashboard → new project → **Test Store** (works in the Simulator, no App Store Connect).
2. Product `range_clinic_monthly` → entitlement **`clinic`** → offering `default` (attach a Paywall).
3. Copy the public SDK key (`test_…`) into `Secrets.revenueCatAPIKey`.

With no key, the paywall runs in clearly labeled **demo mode**.

## Design notes (Apple's iPhone Duo guidance)

- Standard `TabView` + toolbars → system vertical bars on the side; every toolbar item has a
  title + symbol; `visibilityPriority` keeps **Finish** visible, secondary actions go to
  `ToolbarOverflowMenu`.
- `ArrangementView` (`.split`) for Today, Progress and session setup; navigation kept outside it.
- Custom canvas uses `ReservedRegion` for the fold (pivot on the crease) and camera occlusion.
- Same hierarchy and functions on both displays; nothing tied to a single pose.
- Simulator honesty: no camera, haptics or motion sensors — haptics are mirrored in sound and
  visuals, the leveler shows "Simulated sensor", camera assessment runs on device.
