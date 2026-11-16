#!/usr/bin/env bash
# Manage a built web profile belonging to this checkout.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/../.." && pwd)
runtime_dir=${DSH_MANAGER_HOME:-"$project_dir/.dsh-manager"}
mkdir -p -- "$runtime_dir"
runtime_dir=$(cd -- "$runtime_dir" && pwd)
entry="$project_dir/apps/cli/lib/bin.js"
pid_file="$runtime_dir/service.pid"
log_file="$runtime_dir/service.log"
action=${1:-status}
direct=${2:-}
if [[ -n "$direct" && "$direct" != --direct-network ]]; then
  echo 'Only --direct-network is accepted after the action.' >&2; exit 2
fi
cd -- "$project_dir"

service_pid() {
  local pid command_line
  [[ -f "$pid_file" ]] || return 1
  read -r pid < "$pid_file"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  command_line=$(tr '\0' '\n' < "/proc/$pid/cmdline")
  # Check the exact argv element before signaling a potentially reused PID.
  grep -Fxq -- "$entry" <<< "$command_line" || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  printf '%s\n' "$pid"
}
stop_service() {
  local pid
  if pid=$(service_pid); then
    kill -TERM "$pid"
    for ((i=0;i<30;i++)); do
      if ! service_pid >/dev/null; then break; fi
      sleep 1
    done
    if service_pid >/dev/null; then echo 'DSH has not stopped; inspect it before retrying.' >&2; return 1; fi
  fi
  rm -f -- "$pid_file"
}
run_service() {
  export DSH_HOME=${DSH_HOME:-"$HOME/.dsh"}
  if [[ "$direct" == --direct-network ]]; then
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NODE_USE_ENV_PROXY
    export NO_PROXY='*' no_proxy='*'
  fi
  exec node "$entry" web --no-open
}
start_service() {
  if service_pid >/dev/null; then echo 'DSH is already running.'; return; fi
  [[ -f "$entry" ]] || { echo 'Build output missing; run rebuild first.' >&2; return 1; }
  command -v node >/dev/null
  # flock prevents simultaneous manager invocations from launching duplicates.
  (
    flock -n 9 || { echo 'Another start is in progress.' >&2; exit 1; }
    if service_pid >/dev/null; then exit 0; fi
    nohup bash "$script_dir/dsh.sh" serve "$direct" </dev/null >"$log_file" 2>"$log_file.err" 9>&- &
    printf '%s\n' "$!" > "$pid_file"
    for ((i=0;i<30;i++)); do
      sleep 1
      service_pid >/dev/null || { echo "DSH exited; inspect $log_file.err" >&2; exit 1; }
      if grep -q 'dsh web: http' "$log_file"; then grep 'dsh web: http' "$log_file" | tail -1; exit 0; fi
    done
    echo "Readiness timeout; inspect $log_file" >&2; exit 1
  ) 9>"$runtime_dir/start.lock"
}
install_dependencies() {
  command -v pnpm >/dev/null
  npm_config_confirm_modules_purge=false pnpm install --frozen-lockfile --store-dir "$runtime_dir/pnpm-store"
}
install_autostart() {
  command -v systemctl >/dev/null
  local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local node_dir escaped_command
  node_dir=$(dirname -- "$(command -v node)")
  # systemd expands percent specifiers even inside quoted values.
  escaped_command="$script_dir/dsh.sh"
  [[ "$runtime_dir$node_dir$escaped_command" != *$'\n'* ]] || { echo 'Newlines in paths are unsupported.' >&2; return 1; }
  mkdir -p -- "$unit_dir"
  # Quote unit values with Python's JSON encoder to preserve spaces and backslashes.
  command -v python3 >/dev/null
  DSH_UNIT_COMMAND="$escaped_command" DSH_UNIT_RUNTIME="$runtime_dir" DSH_UNIT_PATH="$node_dir:$PATH" DSH_UNIT_HOME="${DSH_HOME:-$HOME/.dsh}" DSH_UNIT_DIRECT="$direct" python3 - <<'PY' > "$unit_dir/dsh-web.service"
import json, os
def quote(value):
    return json.dumps(value.replace('%', '%%'), ensure_ascii=False)
command = os.environ['DSH_UNIT_COMMAND']
print('[Unit]\nDescription=DSH web profile\nAfter=network.target\n\n[Service]\nType=simple')
print('ExecStart=/usr/bin/env bash ' + quote(command) + ' serve ' + os.environ['DSH_UNIT_DIRECT'])
for key, source in [('PATH', 'DSH_UNIT_PATH'), ('DSH_MANAGER_HOME', 'DSH_UNIT_RUNTIME'), ('DSH_HOME', 'DSH_UNIT_HOME')]:
    print('Environment=' + quote(key + '=' + os.environ[source]))
print('Restart=on-failure\nRestartSec=10\n\n[Install]\nWantedBy=default.target')
PY
  systemctl --user daemon-reload
  systemctl --user enable dsh-web.service
  echo 'Enabled user-session startup. Use systemctl --user start dsh-web.service to start it now.'
}
case "$action" in
  start) start_service ;;
  serve) run_service ;;
  stop) stop_service ;;
  restart) stop_service; start_service ;;
  status) if pid=$(service_pid); then echo "DSH running: $pid"; else echo 'DSH is stopped.'; fi ;;
  logs) for file in "$log_file" "$log_file.err"; do [[ ! -f "$file" ]] || tail -40 -- "$file"; done ;;
  url) [[ ! -f "$log_file" ]] || { grep 'dsh web: http' "$log_file" | tail -1; } ;;
  install) install_dependencies ;;
  build) install_dependencies; pnpm run build ;;
  rebuild) stop_service; install_dependencies; pnpm run clean; pnpm run build; start_service ;;
  update) git pull --ff-only; install_dependencies; pnpm run build; stop_service; start_service ;;
  autostart) install_autostart ;;
  unautostart) systemctl --user disable --now dsh-web.service; rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/dsh-web.service"; systemctl --user daemon-reload ;;
  *) echo 'Actions: start stop restart status logs url install build rebuild update autostart unautostart' >&2; exit 2 ;;
esac
