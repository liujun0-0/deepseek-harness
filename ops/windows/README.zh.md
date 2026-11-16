# Windows 源码管理脚本

[English](README.md) | 中文

需要 Windows PowerShell 5.1、Git、满足根 package.json engines 的 Node，以及 packageManager 声明版本的 pnpm；它们均须在 PATH 中。

从任意工作目录运行 `ops\windows\dsh.bat rebuild`，安装锁定依赖、清理、构建并启动 Web 配置。日常管理使用 `start`、`stop`、`restart`、`status`、`logs` 或 `url`。`build` 安装依赖并执行完整构建，不重启。`update` 执行 `git pull --ff-only`、安装、构建和重启；不会切换分支或 rebase。

项目路径根据脚本位置解析。运行日志、PID 和包缓存默认位于 `<checkout>/.dsh-manager`；通过 `DSH_MANAGER_HOME` 或 PowerShell 参数 `-RuntimeDirectory` 修改。DSH 配置使用 `DSH_HOME`，默认是当前用户的 `.dsh`。监听地址和端口由 Web 配置控制。

默认继承代理设置。适合直接访问互联网时可传入 `-DirectNetwork`，为服务绕过环境代理。脚本没有内置提供方地址或 API Key，不会移除插件、修改插件代码、删除锁文件或自动修复文件系统权限。

`autostart` 创建当前用户的启动快捷方式；`unautostart` 删除该快捷方式。移动项目后需重新注册。组织策略可能限制启动项。正常使用不需要管理员权限；依赖 ACL 错误需要显式修复权限。

示例：`dsh.bat status`、`dsh.bat rebuild`、`dsh.bat autostart -DirectNetwork`。启动就绪表示 CLI 已输出链接，不代表已测试 LLM 请求。
