#!/usr/bin/env bash
# Range — scripted demo for the iPhone Duo Simulator (Xcode 27.1 Device Hub).
# Drives the REAL simulated hinge with the `hinge` CLI, so onHingeChange fires exactly as on device.
#
#   ./scripts/demo.sh            # waits for Enter at each beat (live narration)
#   AUTO=1 ./scripts/demo.sh     # runs straight through (for recording)
#
# Numbers match the seeded patient: start 40° (her choice), last best 84°, target 89°
# (hinge = 180° − flexion).
# Keep folds slow below ~90° hinge — the system anticipates closing on fast folds and
# switches to the outer display.
set -euo pipefail
command -v hinge >/dev/null || { echo "Install hinge: https://github.com/artemnovichkov/hinge"; exit 1; }

DEVICE="${DEVICE:-iPhone Duo}"
BUNDLE="com.lambertzhang.range"
LAST=84
TARGET=89
START=40        # where Maria chooses to start stretching (any angle works)
H_START=$((180 - START))
H_LAST=$((180 - LAST))
H_TARGET=$(echo "180 - $TARGET - 0.5" | bc)

beat() {
  echo
  echo "▶ $1"
  if [[ -z "${AUTO:-}" ]]; then read -r -p "  (Enter to continue) " _; fi
}

beat "Reset: phone CLOSED, fresh demo data, 5-rep goal. The outer display shows Maria's Today card."
hinge -d "$DEVICE" close
xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE" -resetDemo -repGoal 5 ${AUTO:+-startSession} >/dev/null
sleep 3

beat "Tap 'Start session' on the outer display (AUTO starts it for you), then open the phone."
hinge -d "$DEVICE" sweep 0 180 1.2
sleep 1.5

beat "Maria chooses where to start: knee bent at ${START}°. Hold still (or tap Start here) — start locks."
hinge -d "$DEVICE" sweep 180 "$H_START" 1.6
sleep 4.5

beat "Fold to last best (${LAST}°) — 'This is where you were.'"
hinge -d "$DEVICE" sweep "$H_START" "$H_LAST" 2.0
sleep 3
hinge -d "$DEVICE" sweep "$H_LAST" "$H_START" 1.6
sleep 0.8

beat "Reps from her start that push past the ghost arc."
for peak in $((LAST + 1)) $((LAST + 3)); do
  hinge -d "$DEVICE" sweep "$H_START" $((180 - peak)) 1.8; sleep 0.5
  hinge -d "$DEVICE" sweep $((180 - peak)) "$H_START" 1.6; sleep 0.6
done

beat "A rushed rep — 'Slow down, controlled movement.'"
hinge -d "$DEVICE" sweep "$H_START" 95 0.2; sleep 0.4
hinge -d "$DEVICE" sweep 95 "$H_START" 1.2; sleep 2

beat "Target ${TARGET}° — parking-sensor ticks, then 'Perfect. Hold.' for five seconds."
hinge -d "$DEVICE" sweep "$H_START" "$H_TARGET" 2.4
sleep 6.8
hinge -d "$DEVICE" sweep "$H_TARGET" "$H_START" 1.6
sleep 1.5

beat "Rep five of five — 'Set complete.'"
hinge -d "$DEVICE" sweep "$H_START" 94 1.8; sleep 0.5
hinge -d "$DEVICE" sweep 94 "$H_START" 1.6; sleep 2.5

beat "Close the phone to save → recovery replay on the outer display."
hinge -d "$DEVICE" sweep "$H_START" 0 0.6
sleep 9

beat "Open again flat to continue on the inner display (Progress / Care Team)."
hinge -d "$DEVICE" open
echo "Done."
