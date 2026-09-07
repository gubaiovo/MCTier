# macOS 构建与测试

支持 Intel 和 Apple Silicon，最低系统版本为 macOS 12。两种架构分别构建，不混用 EasyTier 二进制。

## 本机开发与打包

在 Mac 上安装 Xcode Command Line Tools、Rust stable 和 Node.js 22 后执行：

```bash
npm ci
bash scripts/fetch-macos-binaries.sh
npm run tauri dev
# 本地测试包：ad-hoc 签名
APPLE_SIGNING_IDENTITY=- npm run tauri build -- --bundles app,dmg
```

`tauri.macos.conf.json` 自动覆盖 Windows 默认的 NSIS 配置。下载脚本校验 EasyTier v2.6.4 压缩包及解压后的 core/cli SHA-256，并生成 Tauri 所需的目标架构文件名。

发行包中的 EasyTier 位于 `MCTier.app/Contents/MacOS/`，作为 sidecar 参与签名、公证。运行配置写入应用数据目录；不会往 `.app` 或只读 DMG 中写入配置、覆盖已签名程序。开发模式仍支持校验后解出内嵌资源。

## 权限与平台差异

- GUI 以普通用户运行；首次创建 utun 时通过密码对话框授权 EasyTier。无 TUN 模式不需要提权。密码不写入日志、命令参数或配置。
- EasyTier 的控制管道由 GUI 持有。离开大厅、取消连接或 GUI 异常退出会关闭管道，由监督进程终止自己的子进程，无需再次使用 sudo，也不会按进程名终止其他 EasyTier 实例。
- macOS 自动分配 `utunN` 网卡名；不使用 Windows 的 `MCTier_Net`、Wintun 或 WinDivert 驱动。Ping 超时使用 macOS 的毫秒单位。
- 开启虚拟域名时，hosts 写入通过 macOS 原生管理员授权执行并刷新 DNS；不会调用 Linux 的 `pkexec`。
- 文件授权和 ZIP 解压识别 macOS 的 `/var`、`/tmp`、`/etc` 系统链接，仅允许 root 所有且指向对应 `/private/` 目录的固定映射，仍拒绝用户创建的目录链接及 ZIP 路径越界。
- 麦克风、摄像头及本地网络使用目的已在 Info.plist 声明；音视频签名权限在 Entitlements.plist 中配置。拒绝过麦克风权限时，在系统设置中重新允许 MCTier 使用麦克风。
- 屏幕共享依赖当前 WKWebView 的 `getDisplayMedia` 能力，缺失时会给出错误提示，接收共享不受此限制。macOS 的远程输入注入尚未实现，因此会在开始捕获前拒绝成为被控端；仍可作为控制端。
- 点击 Dock 图标会恢复隐藏的主窗口。

## 私有测试环境

在客户端设置中开启私有服务器，填写：

| 配置 | 地址 |
| --- | --- |
| EasyTier 节点 | `tcp://floatawa.top:25002` |
| WebRTC 信令 | `ws://floatawa.top:25003` |

两端都使用同一组节点、大厅名和密码。最新客户端使用信令协议 v3，需要同步升级信令服务器；只建立 WebSocket 连接或获得虚拟 IP 不代表注册成功。

建议分别验证 Intel / Apple Silicon 与 Windows / Android 的组网、成员列表、语音、文件传输、退出再加入，以及授权取消、密码错误和断线重连。CI 会验证原生编译和安装包结构；真实麦克风授权、utun 路由及跨机联机仍需要在 Mac 上测试。

构建与签名配置依据 [Tauri macOS 打包文档](https://v2.tauri.app/distribute/macos-application-bundle/) 和 [sidecar 文档](https://v2.tauri.app/develop/sidecar/)。正式发布所需证书见 [CI 发布说明](ci-release.md)。
