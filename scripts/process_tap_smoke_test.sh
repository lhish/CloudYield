#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="${ROOT_DIR}/scripts/process_tap_probe.swift"
CREATE_APP="${ROOT_DIR}/scripts/create_tap_probe_app.sh"
APP_BIN="${ROOT_DIR}/TapProbe.app/Contents/MacOS/TapProbe"

if [[ ! -f "${PROBE}" ]]; then
  echo "ERROR: missing probe: ${PROBE}" >&2
  exit 1
fi

OUT="$(mktemp -t cloudyield-tap-probe.XXXXXX)"
echo "Raw output will be saved at: ${OUT}"

if [[ ! -x "${APP_BIN}" ]] || [[ "${PROBE}" -nt "${APP_BIN}" ]]; then
  if [[ ! -x "${CREATE_APP}" ]]; then
    echo "ERROR: missing app builder: ${CREATE_APP}" >&2
    exit 1
  fi
  echo "[0/3] Building TapProbe.app (needed for Audio Capture permission attribution)..."
  "${CREATE_APP}"
fi

cleanup_volume() {
  if [[ -n "${ORIG_VOL:-}" ]]; then
    /usr/bin/osascript -e "set volume output volume ${ORIG_VOL}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${ORIG_MUTED:-}" ]]; then
    /usr/bin/osascript -e "set volume output muted ${ORIG_MUTED}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_volume EXIT

DURATION=20
PROBE_ARGS=(
  --device=output
  --duration="${DURATION}"
  --interval=0.1
  --min-on=0.05
  --min-off=0.10
  --db-on=-55
  --db-off=-65
  --out="${OUT}"
)

echo "[1/3] Running Process Tap probe..."
rm -f "${OUT}"
/usr/bin/open -n "${ROOT_DIR}/TapProbe.app" --args "${PROBE_ARGS[@]}"

for _ in {1..200}; do
  if [[ -f "${OUT}" ]] && /usr/bin/grep -q '"type":"start"' "${OUT}" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

ORIG_VOL="$(/usr/bin/osascript -e 'output volume of (get volume settings)' 2>/dev/null || true)"
ORIG_MUTED="$(/usr/bin/osascript -e 'output muted of (get volume settings)' 2>/dev/null || true)"
/usr/bin/osascript -e 'set volume output muted false' >/dev/null 2>&1 || true
/usr/bin/osascript -e 'set volume output volume 50' >/dev/null 2>&1 || true

SOUND_FILE="/System/Library/Sounds/Glass.aiff"
echo "[2/3] Generating test audio..."
if [[ -f "${SOUND_FILE}" ]]; then
  (
    for _ in {1..20}; do
      /usr/bin/afplay "${SOUND_FILE}" >/dev/null 2>&1 || true
    done
  ) &
else
  /usr/bin/say "CloudYield process tap test sound" >/dev/null 2>&1 || true &
fi

for _ in {1..400}; do
  if [[ -f "${OUT}" ]] && /usr/bin/grep -q '"type":"end"' "${OUT}" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

echo "[3/3] Validating probe output..."
python3 - "${OUT}" <<'PY'
import json, sys

path = sys.argv[1]
seen_event_true = False
last_status = None
max_db = None
min_callback_age = None
errors = []
start = None

with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get("type")
        if t == "start" and start is None:
            start = obj
        if t == "error":
            errors.append(obj.get("message"))
        if t == "event" and obj.get("audible") is True:
            seen_event_true = True
        if t == "status":
            last_status = obj
            db = obj.get("db")
            if isinstance(db, (int, float)):
                max_db = db if max_db is None else max(max_db, db)
            age = obj.get("callbackAge")
            if isinstance(age, (int, float)):
                min_callback_age = age if min_callback_age is None else min(min_callback_age, age)

if errors:
    raise SystemExit(f"Probe reported error: {errors[-1]}")

if not seen_event_true:
    msg = "No audible=true event observed."
    if start:
        msg += f" start.deviceKind={start.get('deviceKind')} tapFormat={start.get('tapFormat')}"
    if max_db is not None:
        msg += f" maxDb={max_db:.1f}dB"
    if min_callback_age is not None:
        msg += f" minCallbackAge={min_callback_age:.3f}s"
    if max_db is not None and max_db <= -170 and (min_callback_age is not None and min_callback_age < 0.2):
        msg += " This looks like Audio Capture permission is missing/denied. Open System Settings → Privacy & Security → Audio Capture and allow TapProbe, then re-run."
    else:
        msg += " (Try increasing volume, or run the probe directly to inspect dB values.)"
    raise SystemExit(msg)

if not last_status or last_status.get("audible") is not False:
    raise SystemExit("Final status is not audible=false. (Audio may still be playing or thresholds too low.)")

print("PASS: observed audible=true during playback and returned to audible=false.")
PY

echo "OK. Raw output saved at: ${OUT}"
echo "Tip: re-run and inspect output with: tail -n 20 ${OUT}"
