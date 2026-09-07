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

`tauri.macos.conf.json` 自动覆盖 Windows 默认的 NSIS 配置。下载脚本校验 EasyTier v2.6.4 压缩包及解压后的 core/cli SHA-256，并生成 Tauri 所需的目标架构文件名。支持的 Rust targets 是 `aarch64-apple-darwin`（Apple Silicon）和 `x86_64-apple-darwin`（Intel）；脚本不会把另一架构的二进制放进当前包。

脚本契约如下：

```bash
bash scripts/fetch-macos-binaries.sh arm64    # 生成 aarch64-apple-darwin sidecars
bash scripts/fetch-macos-binaries.sh x86_64   # 生成 x86_64-apple-darwin sidecars
bash scripts/check-macos-bundle.sh aarch64-apple-darwin
bash scripts/check-macos-bundle.sh x86_64-apple-darwin
```

`fetch` 是无交互、严格失败的下载/校验步骤，产物落在 `src-tauri/resources/binaries/`（未加后缀的开发副本和 Tauri `externalBin` 所需的 target-suffixed 副本，均为可执行 Mach-O）。`check` 接收 Rust target，挂载对应 release DMG，检查 app、Info.plist、sidecar 架构/权限/签名并执行两个 sidecar 的 `--version`；它不会用 placeholder 替代真实二进制。

发行包中的 EasyTier 位于 `MCTier.app/Contents/MacOS/`，作为 sidecar 随应用一起签名。运行配置写入应用数据目录；不会往 `.app` 或只读 DMG 中写入配置、覆盖已签名程序。开发模式仍支持校验后解出内嵌资源。

### 签名、公证与更新限制

当前仓库没有 Developer ID 证书、公证凭据或 Tauri updater 配置。上述命令生成的是本机测试用的 ad-hoc/未公证包，不代表正式发布签名；其他 Mac 上首次打开可能被 Gatekeeper 拦截或提示应用来自未知开发者。只应对可信的测试包在 Finder 中选择“打开”并按系统提示确认。正式发行需由发布环境注入 Developer ID Application 证书、签名身份及 notarization 凭据，再按 Apple 流程公证并 stapling。

当前版本也没有可交付的 updater bundle/签名更新元数据；版本检查只能引导用户手动下载，不应把此包当作支持自动更新的产物。

## 权限与平台差异

- GUI 以普通用户运行；首次创建 utun 时通过密码对话框授权 EasyTier。无 TUN 模式不需要提权。密码不写入日志、命令参数或配置。
- EasyTier 的控制管道由 GUI 持有。离开大厅、取消连接或 GUI 异常退出会关闭管道，由监督进程终止自己的子进程，无需再次使用 sudo，也不会按进程名终止其他 EasyTier 实例。
- macOS 自动分配 `utunN` 网卡名；不使用 Windows 的 `MCTier_Net`、Wintun 或 WinDivert 驱动。Ping 超时使用 macOS 的毫秒单位。
- 开启虚拟域名时，hosts 写入通过 macOS 原生管理员授权执行并刷新 DNS；不会调用 Linux 的 `pkexec`。
- 文件授权和 ZIP 解压识别 macOS 的 `/var`、`/tmp`、`/etc` 系统链接，仅允许 root 所有且指向对应 `/private/` 目录的固定映射，仍拒绝用户创建的目录链接及 ZIP 路径越界。
- 麦克风、摄像头及本地网络使用目的已在 Info.plist 声明；音视频签名权限在 Entitlements.plist 中配置。拒绝过麦克风权限时，在系统设置中重新允许 MCTier 使用麦克风。
- 屏幕共享依赖当前 WKWebView 的 `getDisplayMedia` 能力，缺失时会给出错误提示，接收共享不受此限制。macOS 的远程输入注入尚未实现，因此会在开始捕获前拒绝成为被控端；仍可作为控制端。
- 点击 Dock 图标会恢复隐藏的主窗口。

## 实机联机检查

使用你有权限的 EasyTier 节点和信令服务器，两端配置相同的节点、协议、群组名和密码。确认注册完成后，再验证虚拟 IP 互 ping、成员列表、语音、文件传输、退出再加入，以及授权取消、密码错误和断线重连。不要把“WebSocket 已连接”或“获得虚拟 IP”单独当作注册成功的证据。

建议分别验证 Intel / Apple Silicon 与 Windows / Android 的互通。CI 会验证原生编译和安装包结构；真实麦克风授权、utun 路由、提权提示及跨机联机仍需要在 Mac 上测试。

构建与签名配置依据 [Tauri macOS 打包文档](https://v2.tauri.app/distribute/macos-application-bundle/) 和 [sidecar 文档](https://v2.tauri.app/develop/sidecar/)。正式发布所需证书见 [CI 发布说明](ci-release.md)。
