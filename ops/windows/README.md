# Windows source manager

English | [中文](README.zh.md)

Requires Windows PowerShell 5.1, Git, Node matching the root package.json engines, and the pnpm version declared by packageManager, all available on PATH.

Run `ops\windows\dsh.bat rebuild` from any working directory to install locked dependencies, clean, build and start the web profile. Run `start`, `stop`, `restart`, `status`, `logs` or `url` for daily management. `build` installs dependencies and runs the complete build without restarting. `update` performs `git pull --ff-only`, installs, builds and restarts; it does not change branches or rebase.

The checkout is resolved relative to the script. Runtime logs, PID and package cache default to `<checkout>/.dsh-manager`; set `DSH_MANAGER_HOME` or pass `-RuntimeDirectory` to PowerShell to change this. DSH configuration uses `DSH_HOME`, defaulting to the current user's `.dsh` directory. The web profile controls its listen address and port.

Proxy settings are inherited by default. Pass `-DirectNetwork` to bypass environment proxies for the service when direct Internet access is appropriate. No provider endpoint or API key is embedded. The manager does not remove plugins, modify plugin code, delete lockfiles or repair filesystem permissions automatically.

`autostart` creates a current-user Startup shortcut; `unautostart` removes it. Re-register after moving the checkout. Organization policy may restrict startup entries. No administrator access is needed for normal use; dependency ACL errors require explicit permission repair.

Examples: `dsh.bat status`, `dsh.bat rebuild`, `dsh.bat autostart -DirectNetwork`. Startup readiness means the CLI reported its URL; it does not test an LLM request.
