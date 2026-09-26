# Range — 3-minute demo video

**One line:** *Your knee is a hinge. So is this phone.* iPhone Duo becomes a goniometer and a coach —
the fold is the measurement, the outer screen is the reward.

## Setup (5 minutes before recording)

1. Xcode 27.1 → run **Range** on the **iPhone Duo** simulator once (installs it).
2. Terminal (keep off-camera): `cd ~/Downloads/PT-device && ./scripts/demo.sh`
   The script resets the demo data, closes the phone and launches Range. Press **Enter** at each ▶ beat.
3. Record the **Device Hub window**: ⌘⇧5 → *Record Selected Window* (turn on your microphone under
   Options to narrate live). The window shows whichever display is active — outer when closed,
   inner when open — so the fold is visible in the footage.
4. Optional prop for the intro: a phone (or folded card) draped over your knee like a tent.
5. Backup: `footage/inner.mov` + `footage/outer.mov` are full scripted runs recorded from the
   simulator (portrait — rotate 90° in iMovie). App sounds aren't captured by ⌘⇧5; narrate over them.

No hinge CLI (e.g. recording in Bitrig's 3D simulator)? Use **… → Demo Controls → Run Full Demo**.

## Script (≈ 3:00)

| Time | On screen | Do | Say |
|---|---|---|---|
| 0:00 | You, phone tented over your knee (or title card) | Bend your knee; the phone folds with it | "After a knee replacement, the number that decides your recovery is how far your knee bends. Today it's measured with a plastic protractor, once a week, in a clinic. But your knee is a hinge — and so is iPhone Duo." |
| 0:15 | **Outer display** — Home card | (script beat 1) | "Maria is 14 days out. Closed, Range shows her last best, 84°, today's goal, 89°, and she picks how many reps — four today." |
| 0:28 | Outer → tap **Start session** | Tap, then Enter (beat 2) | "She drapes the phone over her knee like a tent and opens it — a straight leg is 180°." |
| 0:35 | **Inner** — *Choose your start* (40°) + leveler | Enter (beat 3); watch 'Setting your start… 3, 2, 1', or tap **Start here** | "She decides where to start — today with her knee bent at 40°. She holds still and the start locks. The leveler makes sure her thigh stays flat, so the numbers are trustworthy." |
| 0:50 | Rep 1: **Bend → Hold 3s → Back** pills; bend to 84°, the countdown ring fills 3‑2‑1, "Now back to 40°" | Enter (beat 4) | "Every rep is the same three moves, always on screen: bend to the amber dot, hold three seconds while the ring fills, come back to the blue dot. Rep one goes to where she was yesterday — the hardware itself is the progress meter." |
| 1:10 | Rep 2: 87°, hold → **New best** + **Unlocked: Climb stairs** | Enter (beat 5) | "Every best leaves a ghost arc to beat, and near the goal the ticks speed up like a parking sensor, so she can coach herself without looking. 85° is what it takes to climb stairs — unlocked." |
| 1:30 | Rushed rep → **Slow down** | Enter (beat 6) | "Rush it and Range catches it from the hinge's angular velocity — controlled movement, or it doesn't count." |
| 1:40 | Rep 3: today's goal, 89°, hold | Enter (beat 7) | "Today's goal, 89°. Hold… three, two, one. Now back." |
| 1:55 | Rep 4 → **Set complete** | Enter (beat 8) | "Four of four — only clean, held reps count, and the coach counts them out loud. Set complete." |
| 2:05 | **Close the phone** → outer summary + recovery replay | Enter (beat 9) | "She closes the phone to save. On the outside: from 40 to 89, a new personal best — and her knee literally regains its range: day 1, day 7, day 13, today." |
| 2:25 | Open (beat 10) → **Progress** tab: replay, milestones, chart | Tap Progress | "Degrees become her life back: walking, stairs, a chair, a bike." |
| 2:45 | Back to Exercise | — | "onHingeChange, reserved regions, arrangement views, vertical bars and device-motion bodies. The fold isn't a gimmick here — it's the measurement. Range." |

## If a judge asks

- **Why not a regular phone?** A flat phone needs two sensors and calibration to measure a joint angle.
  A hinge *is* a goniometer.
- **Accuracy?** Consistency beats absolute accuracy for tracking change: same placement, leveler-gated
  start and a zero check. Next step: validate against a universal goniometer.
- **Why the outer screen?** In the tent pose the inner screen faces the leg and the outer screen faces you.
- **The Simulator can't bend a real knee** — the hinge is driven by the `hinge` CLI (Device Hub's hidden
  slider), which fires the real `onHingeChange` API.
