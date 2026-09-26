# Range — 3-minute demo video

**One line:** *Your knee is a hinge. So is this phone.* iPhone Duo becomes a goniometer, a coach,
and a clinic dashboard — the fold is the measurement, the outer screen is the reward.

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
| 0:15 | **Outer display** — Today card | (script beat 1) | "Maria is 14 days out. Closed, Range shows one thing: last best 84°, today 89° — an adaptive target from her comfortable max, not a number she has to type." |
| 0:28 | Outer → tap **Start session** | Tap, then Enter (beat 2) | "She drapes the phone over her knee like a tent and opens it — a straight leg is 180°." |
| 0:35 | **Inner** — *Choose your start* (40°) + leveler | Enter (beat 3); watch 'Hold 3…2…1', or tap **Start here** | "She decides where to start — today with her knee bent at 40°, where it's comfortable. She holds still, the start locks, and every rep is measured from there. The leveler makes sure her thigh stays flat, so the numbers are trustworthy." |
| 0:50 | Fold to 84° | Enter (beat 4) | "The protractor pivots exactly on the physical crease — that's the ReservedRegion API. And the first move is to fold back to where she was yesterday. The hardware itself is the progress meter." |
| 1:05 | Reps, ghost arc, "New best" | Enter (beat 5) | "Every best leaves a ghost arc — she's competing against herself. As she gets close, the ticks speed up like a parking sensor, because behind her knee she can't see the screen." |
| 1:25 | "Slow down" | Enter (beat 6) | "Rush a rep and Range catches it from the hinge's angular velocity — controlled movement, or it doesn't count." |
| 1:35 | Target → **Perfect. Hold.** → 5-second ring → **Unlocked: Climb stairs** | Enter (beat 7) | "At 89°: Perfect, hold. Five seconds… and she's unlocked climbing stairs. Degrees become her life back." |
| 1:55 | **Close the phone** → outer summary + recovery replay | Enter (beat 8) | "She closes the phone to save. On the outside: stretched from 40 to 90, plus 6 degrees — beyond measurement error, real progress — and her knee literally regains its range: day 1, day 7, day 13, today." |
| 2:15 | Open (beat 9) → **Care Team** tab → **Start free trial** → **Start 14-day free trial** | Tap | "Her physical therapist sees it immediately. Range Clinic is a subscription — paywall, purchases, entitlements and Customer Center all run on RevenueCat." |
| 2:30 | Dashboard: Maria **Live**, James **Stiffness risk**, RTM 28/16, tap **Draft note** | Tap Maria, then James, then Draft note | "Patients are sorted by risk: James plateaued at 86° in week 7 — the window where surgeons consider manipulation — so he's flagged today, not at his six-week visit. Remote monitoring days are counted for billing, and the progress note is drafted on-device." |
| 2:50 | Back to Session or Progress (replay) | — | "onHingeChange, reserved regions, arrangement views, vertical bars, device-motion bodies, and a camera accessory for clinic assessments. The fold isn't a gimmick here — it's the measurement. Range." |

## If a judge asks

- **Why not a regular phone?** A flat phone needs two sensors and calibration to measure a joint angle.
  A hinge *is* a goniometer.
- **Accuracy?** Consistency beats absolute accuracy for tracking change: same placement, leveler-gated
  start, zero check, and a ±5° noise band so we only celebrate real gains. Next step: validate against a
  universal goniometer.
- **Why the outer screen?** In the tent pose the inner screen faces the leg and the outer screen faces you.
- **Business?** Clinics subscribe per clinician (RevenueCat); remote therapeutic monitoring (RTM) makes
  the home data billable — Range tracks the 16-day threshold automatically.
- **The Simulator can't bend a real knee** — the hinge is driven by the `hinge` CLI (Device Hub's hidden
  slider), which fires the real `onHingeChange` API.
