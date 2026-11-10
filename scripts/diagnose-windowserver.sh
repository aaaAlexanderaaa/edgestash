#!/bin/bash
set -euo pipefail
export LC_ALL=C

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
seconds=12
pause_engine=false
probe=false
output="${HOME}/Desktop/EdgeStash-WindowServer-$(date +%Y%m%d-%H%M%S)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pause-engine) pause_engine=true; shift ;;
    --occlusion-probe) probe=true; shift ;;
    --seconds) seconds="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done
case "$seconds" in *[!0-9]*|'') exit 1 ;; esac
if [ "$seconds" -lt 2 ] || [ "$seconds" -gt 60 ]; then
  printf '%s\n' '--seconds must be between 2 and 60' >&2
  exit 1
fi
mkdir -p "$output"
helper="$script_dir/WindowServerDiagnostic"
if [ ! -x "$helper" ]; then
  helper="$script_dir/../.build/windowserver-diagnostic/WindowServerDiagnostic"
  mkdir -p "$(dirname "$helper")"
  if [ ! -x "$helper" ] || [ "$script_dir/WindowServerDiagnostic.swift" -nt "$helper" ]; then
    xcrun swiftc -O -parse-as-library -module-cache-path "$(dirname "$helper")/module-cache" \
      "$script_dir/WindowServerDiagnostic.swift" -o "$helper"
  fi
fi

ws_pid="$(pgrep -x WindowServer)"
app_pids=()
while IFS= read -r candidate; do
  if [ -n "$candidate" ]; then app_pids+=("$candidate"); fi
done < <(pgrep -x EdgeStash || true)
pids=("$ws_pid")
if [ "${#app_pids[@]}" -gt 0 ]; then pids+=("${app_pids[@]}"); fi
while IFS= read -r subject_pid; do
  if [ -n "$subject_pid" ]; then
    duplicate=false
    for candidate in "${pids[@]}"; do
      if [ "$subject_pid" = "$candidate" ]; then duplicate=true; fi
    done
    if ! "$duplicate"; then pids+=("$subject_pid"); fi
  fi
done < <("$helper" subject-pids)
app_pid=''
app_started=''
watchdog=''
paused=false
same_process() {
  [ -n "$app_pid" ] && [ "$(ps -p "$app_pid" -o lstart= 2>/dev/null)" = "$app_started" ]
}
resume() {
  if "$paused"; then
    if same_process; then kill -CONT "$app_pid" 2>/dev/null || true; fi
    paused=false
  fi
  if [ -n "$watchdog" ]; then
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    watchdog=''
  fi
}
trap resume EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf 'Keep the current stash state. Do not use the mouse or keyboard during measurement.\nResults stay on this Mac: %s\n' "$output"
printf '%s\n' "${pids[@]}" > "$output/measured-pids.txt"
"$helper" snapshot > "$output/before.json"
if [ "${#app_pids[@]}" -eq 1 ]; then
  # A sample records the running image's version and whether it is asleep,
  # doing AX work, or running a display link. Keep sampling out of CPU phases.
  /usr/bin/sample "${app_pids[0]}" 3 10 -file "$output/EdgeStash.sample.txt" \
    > "$output/sample-status.txt" 2>&1 || true
fi
printf '%s\n' 'Measurement 1/3: normal operation.'
"$helper" measure "$seconds" "${pids[@]}" > "$output/baseline.json"
if "$pause_engine"; then
  if [ "${#app_pids[@]}" -ne 1 ]; then
    printf '%s\n' 'Exactly one EdgeStash process is required; no process was paused.' >&2
    exit 1
  fi
  app_pid="${app_pids[0]}"
  app_started="$(ps -p "$app_pid" -o lstart=)"
  if [ "$(ps -p "$app_pid" -o uid= | tr -d ' ')" != "$(id -u)" ] || \
      ps -p "$app_pid" -o stat= | /usr/bin/grep -q T; then
    printf '%s\n' 'The process belongs to another user or is already paused; its state was not changed.' >&2
    exit 1
  fi
  # The watchdog survives this shell being killed. Both it and the EXIT trap
  # bind resume to the original PID/start time, never a recycled PID.
  nohup /bin/sh -c '
    sleep "$3"
    if [ "$(ps -p "$1" -o lstart= 2>/dev/null)" = "$2" ]; then
      kill -CONT "$1" 2>/dev/null || true
    fi
  ' watchdog "$app_pid" "$app_started" "$((seconds + 15))" \
    > "$output/watchdog.txt" 2>&1 &
  watchdog=$!
  printf 'Measurement 2/3: pause EdgeStash for %s seconds; stash interaction is temporarily unavailable, then resumes automatically.\n' "$seconds"
  same_process
  paused=true
  kill -STOP "$app_pid"
  "$helper" measure "$seconds" "${pids[@]}" > "$output/engine-paused.json"
  resume
else
  printf '%s\n' 'Measurement 2/3: remain idle (--pause-engine was not selected).'
  "$helper" measure "$seconds" "${pids[@]}" > "$output/idle-repeat.json"
fi
printf '%s\n' 'Measurement 3/3: normal operation after resume.'
"$helper" measure "$seconds" "${pids[@]}" > "$output/resumed.json"
"$helper" snapshot > "$output/after.json"
if "$probe"; then
  printf '%s\n' 'Run the own-window occlusion probe (about 9 seconds); other apps are not controlled.'
  "$helper" occlusion-probe > "$output/occlusion-probe.json"
fi
printf '%s\n' 'Done. No data was uploaded; keep the entire results directory.'
