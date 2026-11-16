# Source checkout managers

English | [中文](README.zh.md)

These optional scripts manage the built web profile from a source checkout. They resolve the checkout relative to their own location and require Git, a Node version satisfying the root `package.json`, and its declared pnpm version on PATH.

- Windows: see [Windows manager](windows/README.md); run `ops\windows\dsh.bat rebuild`.
- Linux: run `bash ops/linux/dsh.sh rebuild`. Bash, `flock` and Linux `/proc` are required. Login startup additionally requires a user systemd session and Python 3.

Both managers provide `install`, `build`, `rebuild`, `start`, `stop`, `restart`, `status`, `logs`, `url`, `update`, `autostart` and `unautostart`. Build runs the complete repository build; rebuild stops the managed process, installs locked dependencies, cleans, builds and starts it. Update pulls the current branch with `--ff-only` before building and restarting.

Runtime data defaults to `<checkout>/.dsh-manager`; override with `DSH_MANAGER_HOME`. DSH data defaults to the current user's `.dsh`; override with `DSH_HOME`. Keep the same runtime directory across management commands. Logs contain the local authentication URL; do not publish them.

Linux `autostart` writes `dsh-web.service` under the current user's systemd configuration and enables it for future user sessions. It captures the current Node PATH and DSH home; re-register after moving the checkout or changing Node installations. It does not enable system-wide boot or lingering. Use `systemctl --user start|stop|status dsh-web.service` and `journalctl --user -u dsh-web.service` while systemd owns the process; do not mix manual start with systemd start. Stop a manually started instance before starting the unit. `unautostart` disables, stops and removes this user unit.

Proxy settings are inherited. Linux accepts `--direct-network` after the action; Windows accepts `-DirectNetwork`. Direct mode clears common proxy variables and sets wildcard bypass for the service. No API keys or provider endpoints are built into these scripts. Startup readiness only checks the CLI's startup URL, not LLM connectivity.
