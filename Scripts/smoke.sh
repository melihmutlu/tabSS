#!/bin/zsh
# Launches the app and checks it stays alive with negligible idle CPU.
set -euo pipefail
export LC_ALL=C  # `ps` prints decimal commas in some locales

app="${1:?usage: smoke.sh <path to tabSS.app>}"
seconds="${SMOKE_SECONDS:-30}"
max_avg_cpu="${SMOKE_MAX_AVG_CPU:-1.0}"
(( seconds > 0 )) || { echo "SMOKE_SECONDS must be positive"; exit 2; }

# Total CPU time in seconds; `ps -o time` prints [[hh:]mm:]ss.ss
cpu_seconds() {
    local total=0.0 part
    for part in ${(s.:.)1}; do total=$(( total * 60 + part )); done
    echo "$total"
}

sample() { ps -o time=,rss= -p "$1" 2>/dev/null || true; }

make -s -C "${0:A:h}/.." stop
open "$app"
sleep 5  # let startup work (window discovery, thumbnail seeding) settle

pid="$(pgrep -nx tabSS || true)"
[[ -n "$pid" ]] || { echo "FAIL: tabSS did not start"; exit 1; }

read -r start_time _ <<< "$(sample "$pid")"
sleep "$seconds"
end_sample="$(sample "$pid")"
[[ -n "$end_sample" ]] || { echo "FAIL: tabSS exited"; exit 1; }
read -r end_time rss <<< "$end_sample"

avg_cpu=$(( ($(cpu_seconds "$end_time") - $(cpu_seconds "$start_time")) * 100.0 / seconds ))
printf "alive: yes  avg CPU: %.2f%%  RSS: %.1f MB\n" "$avg_cpu" "$(( rss / 1024.0 ))"
if (( avg_cpu > max_avg_cpu )); then
    echo "FAIL: idle CPU above ${max_avg_cpu}%"
    exit 1
fi
echo "PASS"
