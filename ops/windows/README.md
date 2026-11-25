# Windows source manager

Double-click `dsh.bat` or run it without arguments for the numbered Chinese menu. Select an action, press Enter to return, or enter `0` to exit. Commands with arguments run directly. Use `dsh.ps1 -Menu` for the PowerShell menu.

English | [中文](README.zh.md)

Requires Windows PowerShell 5.1, Git, Node matching the root package.json engines, and the pnpm version declared by packageManager, all available on PATH.

Run `ops\windows\dsh.bat rebuild` from any working directory to install locked dependencies, clean, build and start the web profile. Run `start`, `stop`, `restart`, `status`, `logs` or `url` for daily management. `build` installs dependencies and runs the complete build without restarting. `update` performs `git pull --ff-only`, installs, builds and restarts; it does not change branches or rebase.

The checkout is resolved relative to the script. Runtime logs and PID default to `<checkout>/.dsh-manager`; set `DSH_MANAGER_HOME` or pass `-RuntimeDirectory` to PowerShell to change this. Installation reuses the store recorded in `node_modules/.modules.yaml`, or pnpm's default store for a fresh checkout. DSH configuration uses `DSH_HOME`, defaulting to the current user's `.dsh` directory. The web profile controls its listen address and port.

`rebuild` reports five stages: stop, install, clean, build and start. pnpm output is appended to `build.log` in the runtime directory. Every 15 seconds a heartbeat reports the child PID, elapsed time and time since output; this indicates process liveness only. Installation disables interactive input, confirms dependency-directory reconstruction and strictly checks the Node engine while preserving lockfile and supply-chain policies. Failed commands stop subsequent stages.

Proxy settings are inherited by default. Pass `-DirectNetwork` to bypass environment proxies for the service when direct Internet access is appropriate. No provider endpoint or API key is embedded. The manager does not remove plugins, modify plugin code, delete lockfiles or repair filesystem permissions automatically.

`autostart` installs and immediately runs a Node watchdog through a current-user Startup shortcut. It checks the service every 15 seconds and retries failures with backoff up to 60 seconds. `stop` pauses recovery; `start` or a fresh watchdog at login resumes it. Builds pause recovery while the service is stopped. `unautostart` removes the shortcut and asks the watchdog to exit, leaving DSH running. Watchdog diagnostics go to `watchdog.log` in the runtime directory. Re-register after moving Node or the checkout. Organization policy may restrict or remove startup entries; a watchdog cannot make a deleted shortcut run. No administrator access is needed for normal use; dependency ACL errors require explicit permission repair.

Examples: `dsh.bat status`, `dsh.bat rebuild`, `dsh.bat autostart -DirectNetwork`. Startup readiness means the CLI reported its URL; it does not test an LLM request.
