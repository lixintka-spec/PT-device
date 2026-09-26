#!/usr/bin/env bash
# Range — scripted demo for the iPhone Duo Simulator (Xcode 27.1 Device Hub).
# Drives the REAL simulated hinge with the `hinge` CLI, so onHingeChange fires exactly as on device.
#
#   ./scripts/demo.sh            # waits for Enter at each beat (live narration)
#   AUTO=1 ./scripts/demo.sh     # runs straight through (for recording)
#
# Numbers match the seeded patient: last best 84°, target 89° (hinge = 180° − flexion).
# Keep folds slow below ~90° hinge — the system anticipates closing on fast folds and
# switches to the outer display.
set -euo pipefail
command -v hinge >/dev/null || { echo "Install hinge: https://github.com/artemnovichkov/hinge"; exit 1; }

DEVICE="${DEVICE:-iPhone Duo}"
BUNDLE="com.lambertzhang.range"
LAST=84
TARGET=89
H_LAST=$((180 - LAST))
H_TARGET=$(echo "180 - $TARGET - 0.5" | bc)

beat() {
  echo
  echo "▶ $1"
  if [[ -z "${AUTO:-}" ]]; then read -r -p "  (Enter to continue) " _; fi
}

beat "Reset: phone CLOSED, fresh demo data. The outer display shows Maria's Today card."
hinge -d "$DEVICE" close
xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE" -resetDemo ${AUTO:+-startSession} >/dev/null
sleep 3

beat "Tap 'Start session' on the outer display (AUTO starts it for you), then open flat — straight leg = 180°."
hinge -d "$DEVICE" sweep 0 180 1.2
sleep 5   # leveler settles, 3-second position lock + zero check

beat "Fold to last best (${LAST}°) — 'This is where you were.'"
hinge -d "$DEVICE" sweep 178 "$H_LAST" 2.2
sleep 3
hinge -d "$DEVICE" sweep "$H_LAST" 178 1.6
sleep 0.8

beat "Reps that push past the ghost arc."
for peak in $((LAST + 1)) $((LAST + 3)); do
  hinge -d "$DEVICE" sweep 178 $((180 - peak)) 1.8; sleep 0.5
  hinge -d "$DEVICE" sweep $((180 - peak)) 178 1.6; sleep 0.6
done

beat "A rushed rep — 'Slow down, controlled movement.'"
hinge -d "$DEVICE" sweep 178 100 0.35; sleep 0.4
hinge -d "$DEVICE" sweep 100 178 1.4; sleep 2

beat "Target ${TARGET}° — parking-sensor ticks, then 'Perfect. Hold.' for five seconds."
hinge -d "$DEVICE" sweep 178 "$H_TARGET" 2.6
sleep 6.8
hinge -d "$DEVICE" sweep "$H_TARGET" 178 1.8
sleep 1.5

beat "Close the phone to save → recovery replay on the outer display."
hinge -d "$DEVICE" sweep 178 0 0.6
sleep 9

beat "Open again flat to continue on the inner display (Progress / Care Team)."
hinge -d "$DEVICE" open
echo "Done."
