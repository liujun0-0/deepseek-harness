# Windows 源码管理脚本

双击 `dsh.bat` 或不带参数运行时显示中文编号菜单，输入编号执行操作，完成后按回车返回菜单，输入 `0` 退出。带参数运行时直接执行命令。PowerShell 入口可用 `dsh.ps1 -Menu` 打开菜单。

[English](README.md) | 中文

需要 Windows PowerShell 5.1、Git、满足根 package.json engines 的 Node，以及 packageManager 声明版本的 pnpm；它们均须在 PATH 中。

从任意工作目录运行 `ops\windows\dsh.bat rebuild`，安装锁定依赖、清理、构建并启动 Web 配置。日常管理使用 `start`、`stop`、`restart`、`status`、`logs` 或 `url`。`build` 安装依赖并执行完整构建，不重启。`update` 执行 `git pull --ff-only`、安装、构建和重启；不会切换分支或 rebase。

项目路径根据脚本位置解析。运行日志和 PID 默认位于 `<checkout>/.dsh-manager`；通过 `DSH_MANAGER_HOME` 或 PowerShell 参数 `-RuntimeDirectory` 修改。安装复用现有 `node_modules/.modules.yaml` 记录的缓存，首次安装使用 pnpm 默认缓存。DSH 配置使用 `DSH_HOME`，默认是当前用户的 `.dsh`。监听地址和端口由 Web 配置控制。

`rebuild` 显示停止、安装、清理、构建、启动五个阶段。pnpm 输出同时追加到运行目录的 `build.log`，每 15 秒显示子进程 PID、运行时长和无输出时长；运行提示只表示进程尚未退出。安装关闭交互输入、自动确认依赖目录重建并严格检查 Node 版本，保留锁文件和供应链策略。命令失败会停止后续阶段，不会继续启动未构建完成的 DSH。

默认继承代理设置。适合直接访问互联网时可传入 `-DirectNetwork`，为服务绕过环境代理。脚本没有内置提供方地址或 API Key，不会移除插件、修改插件代码、删除锁文件或自动修复文件系统权限。

`autostart` 创建当前用户的 Node 守护启动快捷方式并立即运行守护程序；每 15 秒检查服务，异常退出后重新启动，失败时最多延迟 60 秒重试。`stop` 暂停恢复，`start` 恢复；下次登录重新运行守护程序时也会恢复。构建停止期间不会自动拉起服务。`unautostart` 删除快捷方式并通知守护程序退出，保留已运行的 DSH。守护日志位于运行目录的 `watchdog.log`。移动项目或 Node 后需重新注册。组织策略可能限制或删除启动项，守护程序无法保证被删除的启动项仍生效。正常使用不需要管理员权限；依赖 ACL 错误需要显式修复权限。

示例：`dsh.bat status`、`dsh.bat rebuild`、`dsh.bat autostart -DirectNetwork`。启动就绪表示 CLI 已输出链接，不代表已测试 LLM 请求。
