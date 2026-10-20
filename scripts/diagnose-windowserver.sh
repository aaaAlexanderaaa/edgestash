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

printf '保持当前收纳状态，接下来各测量阶段请勿操作鼠标或键盘。\n结果仅保存在本机：%s\n' "$output"
printf '%s\n' "${pids[@]}" > "$output/measured-pids.txt"
"$helper" snapshot > "$output/before.json"
if [ "${#app_pids[@]}" -eq 1 ]; then
  # A sample records the running image's version and whether it is asleep,
  # doing AX work, or running a display link. Keep sampling out of CPU phases.
  /usr/bin/sample "${app_pids[0]}" 3 10 -file "$output/EdgeStash.sample.txt" \
    > "$output/sample-status.txt" 2>&1 || true
fi
printf '%s\n' '测量 1/3：正常运行。'
"$helper" measure "$seconds" "${pids[@]}" > "$output/baseline.json"
if "$pause_engine"; then
  if [ "${#app_pids[@]}" -ne 1 ]; then
    printf '%s\n' '需要恰好一个 EdgeStash 进程，未暂停任何进程。' >&2
    exit 1
  fi
  app_pid="${app_pids[0]}"
  app_started="$(ps -p "$app_pid" -o lstart=)"
  if [ "$(ps -p "$app_pid" -o uid= | tr -d ' ')" != "$(id -u)" ] || \
      ps -p "$app_pid" -o stat= | /usr/bin/grep -q T; then
    printf '%s\n' '进程不属于当前用户或已经被暂停，未改变其状态。' >&2
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
  printf '测量 2/3：短暂停住 EdgeStash %s 秒；期间无法唤出收纳窗口，随后自动恢复。\n' "$seconds"
  same_process
  paused=true
  kill -STOP "$app_pid"
  "$helper" measure "$seconds" "${pids[@]}" > "$output/engine-paused.json"
  resume
else
  printf '%s\n' '测量 2/3：继续静置（未使用 --pause-engine）。'
  "$helper" measure "$seconds" "${pids[@]}" > "$output/idle-repeat.json"
fi
printf '%s\n' '测量 3/3：正常运行，确认可恢复。'
"$helper" measure "$seconds" "${pids[@]}" > "$output/resumed.json"
"$helper" snapshot > "$output/after.json"
if "$probe"; then
  printf '%s\n' '运行自有临时窗口遮挡实验（约 9 秒）；不操作其他应用窗口。'
  "$helper" occlusion-probe > "$output/occlusion-probe.json"
fi
printf '%s\n' '完成。数据没有上传；请保留整个结果目录。'
