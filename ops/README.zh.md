# 源码目录管理脚本

[English](README.md) | 中文

这些可选脚本管理源码目录中已构建的 Web 配置。它们根据脚本位置定位项目，要求 PATH 中有 Git、满足根 `package.json` 要求的 Node，以及其中声明版本的 pnpm。

- Windows：参阅 [Windows 管理脚本](windows/README.zh.md)；运行 `ops\windows\dsh.bat rebuild`。
- Linux：运行 `bash ops/linux/dsh.sh rebuild`。需要 Bash、`flock` 和 Linux `/proc`。登录自启还需要用户 systemd 会话和 Python 3。

两套管理脚本提供 `install`、`build`、`rebuild`、`start`、`stop`、`restart`、`status`、`logs`、`url`、`update`、`autostart` 和 `unautostart`。build 执行完整仓库构建；rebuild 停止受管理进程、安装锁定依赖、清理、构建并启动。update 先用 `--ff-only` 拉取当前分支，再构建并重启。

运行数据默认位于 `<checkout>/.dsh-manager`；可用 `DSH_MANAGER_HOME` 覆盖。DSH 数据默认位于当前用户的 `.dsh`；可用 `DSH_HOME` 覆盖。管理命令必须使用相同运行目录。日志包含本地认证链接，请勿公开。

Linux `autostart` 在当前用户的 systemd 配置目录写入 `dsh-web.service`，并启用后续用户会话自启。它记录当前 Node PATH 和 DSH 数据目录；移动源码或更换 Node 安装后需重新注册。它不会启用系统级启动或 lingering。systemd 管理进程时使用 `systemctl --user start|stop|status dsh-web.service` 和 `journalctl --user -u dsh-web.service`；不要混用手动启动和 systemd 启动。启动服务单元前先停止手动启动的实例。`unautostart` 禁用、停止并删除此用户单元。

默认继承代理设置。Linux 在动作后接受 `--direct-network`；Windows 接受 `-DirectNetwork`。直连模式清理常见代理变量，并为服务设置通配绕过。脚本没有内置 API Key 或提供方地址。启动就绪检查仅确认 CLI 输出启动链接，不验证 LLM 连通性。
