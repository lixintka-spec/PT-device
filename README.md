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

Launch arguments: `-resetDemo` (fresh seeded data), `-startSession`, `-tab home|exercise|progress`,
`-repGoal N`, `-autopilot`, `-logHinge` (prints every hinge update).

Regenerate the project after adding files: `xcodegen generate` (see `project.yml`).

## The patient experience

| Moment | What happens | iPhone Duo API |
|---|---|---|
| Phone closed | **Home** card on the outer display: day 14, last best 84°, target 89°, and **how many reps** (− 10 +, remembered) | Size classes, vertical bars |
| Open | **She chooses where to start** — straight or bent. Hold still (or tap *Start here*) and the start locks; the **leveler** checks the thigh is flat. Reps are measured from her start | `CMMotionManager.deviceMotionBody` (`CMBodyIdentifiable`), hinge angle |
| Fold | Protractor pivots **exactly on the crease**; leg bends in sync | `onHingeChange`, `reservedRegions(kind: .division)` |
| Every rep | **Bend → Hold 3s → Back**, always shown as three pills with the current one lit. Bend to the amber dot, stop and a big countdown ring fills (3‑2‑1, spoken), then "Now back to 40°" to the blue start dot. Sag out of the zone and the hold pauses; skip it and the rep doesn't count | Hinge angle |
| Match last best | Rep 1 aims at 84°: "That's where you were last time." The hardware is the progress meter | Hinge angle |
| Reps | **Ghost range** arc to beat, parking-sensor ticks toward the target, rising tone; dots fill per clean rep, the coach counts aloud, "Set complete" at the goal | Hinge velocity |
| Rushed rep | "Slow down — controlled movement"; it doesn't count toward the rep goal | Angular velocity |
| Milestone | Holding past 85° unlocks **Climb stairs** | Core Haptics + audio mirror |
| Close the phone | **Close-to-save**; recovery replay plays on the outer display (Day 1 → today) | Hinge status + angle |

Under the hood: adaptive target = median of last 3 peaks + 5° (+2° if it hurt last time),
compensation detection (thigh lifts), functional milestone ladder.

The demo build is patient-only: no clinic dashboard or paywall. RevenueCat is still linked
(`Range/Store/ProStore.swift`, no key, no screens) so a paywall can come back later.
Everything else uses native frameworks: SwiftData, Swift Charts, Core Haptics, AVFoundation
(tones/voice), Core Motion.

## Design notes (Apple's iPhone Duo guidance)

- Standard `TabView` + toolbars → system vertical bars on the side; every toolbar item has a
  title + symbol; `visibilityPriority` keeps **Finish** visible, secondary actions go to
  `ToolbarOverflowMenu`.
- `ArrangementView` (`.split`) for Home, Progress and session setup; navigation kept outside it.
- Tabs say what they hold: **Home** (house), **Exercise** (stretching figure), **Progress** (chart).
- Custom canvas uses `ReservedRegion` for the fold (pivot on the crease) and camera occlusion.
- Same hierarchy and functions on both displays; nothing tied to a single pose.
- Simulator honesty: no haptics or motion sensors — haptics are mirrored in sound and
  visuals, and the leveler shows "Simulated sensor".
