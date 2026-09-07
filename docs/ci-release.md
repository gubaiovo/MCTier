# GitHub Actions 构建与发布

工作流位于 `.github/workflows/ci.yml`，统一覆盖质量检查、三端打包、安装包冒烟验证、签名与 GitHub Release 发布。仓库默认分支当前为 `master`，所以“合并主分支”的触发器使用 `master`；若以后将默认分支改为 `main`，需要同步修改工作流中的分支过滤器。

## 触发与产物策略

| 触发方式 | 检查与构建 | Artifact | GitHub Release |
| --- | --- | --- | --- |
| `pull_request` | 前端、Rust、许可证检查；Windows NSIS、macOS Intel DMG、macOS Apple Silicon DMG、Android debug APK；全部产物做冒烟验证 | 上传 Windows/macOS/Android PR 包，保留 3 天 | 否 |
| push 到 `master`、`main`、`feat/workflow` 或 `fix/workflow` | 完整检查与三端构建 | 开发版，保留 14 天 | 否 |
| push `vX.Y.Z` | 完整检查、正式签名、Android release APK/AAB | 保留 30 天 | 正式 Release |
| push `vX.Y.Z-rc.N` | 与正式版相同 | 保留 30 天 | prerelease，不标记 Latest |
| `workflow_dispatch` | 标签留空时构建所选分支；填写已有版本标签时可重建 Artifact 或受控发布 | 保留 14 天 | 仅 `publish=true` 时覆盖同名 Release 资产 |
| 每日 02:00（Asia/Shanghai） | Nightly 完整检查与三端构建 | 保留 7 天 | 否 |

Android 当前只发布 `arm64-v8a`。这是源码现状决定的：EasyTier JNI 与 LocalVQE 原生库目前只在该 ABI 下存在。

所有平台复用 GitHub Actions 缓存：npm 使用 `setup-node` 缓存，Rust 使用 `Swatinem/rust-cache`，Gradle 使用 `setup-gradle`；macOS EasyTier 二进制还按目标架构和下载脚本内容单独缓存，并在命中后重新校验 SHA-256。

## Release 前的仓库设置

正式发布会严格要求签名材料；缺少任一项都会失败，不会退化为未签名包。请在 `Settings → Secrets and variables → Actions` 中添加以下 **repository secrets**：

### Windows

| Secret | 内容 |
| --- | --- |
| `WINDOWS_CERTIFICATE_BASE64` | PFX 代码签名证书的 Base64（纯 Base64，不含 PEM 头尾） |
| `WINDOWS_CERTIFICATE_PASSWORD` | PFX 导出密码 |
| `WINDOWS_TIMESTAMP_URL` | 证书颁发机构提供的 RFC 3161/Authenticode 时间戳地址 |

### macOS

| Secret | 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application `.p12` 的 Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `APPLE_ID` | Apple ID 邮箱 |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 app-specific password |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

PR、开发版和 Nightly 的 macOS 包使用 ad-hoc 签名并上传 Artifact；正式标签构建使用 Developer ID 签名并由 Tauri 执行公证。
桌面端弹幕与游戏 HUD 使用透明悬浮窗，因此 `tauri.conf.json` 启用了 `app.macOSPrivateApi`；这类构建面向 GitHub Release 的 Developer ID 分发，不适用于 Mac App Store 审核。

### Android

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | JKS/keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名 key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

建议在仓库中创建名为 `release` 的 GitHub Environment，并配置 required reviewers。最终 Release job 已绑定该 Environment，因此可以在所有构建与验证通过后增加一次人工批准。

## Windows EasyTier 构建

Windows 使用固定 EasyTier v2.5.0 源码并应用 `pnet_datalink` 补丁，移除 Npcap 的静态导入；不打包 Packet.dll。补丁从 EasyTier 仓库根目录以 `--directory=vendor/pnet_datalink` 应用，防止 Git 在子目录静默跳过补丁。源码、补丁、构建脚本共同约束缓存与重建，打包前继续执行 PE 导入检查。

## 分支测试构建

推送到 `feat/workflow` 会自动构建开发包，无需证书或版本标签。也可在 Actions 中选择 **Build and release**、分支 `feat/workflow`，将 `tag` 留空、`publish` 保持 `false`。发布必须显式指定已有版本标签。

所有任务使用 metadata 检出后解析的同一个 commit SHA，避免标签移动导致不同平台混用源码。macOS 两个原生 Runner 分别执行 Rust check、Clippy、单元测试和 DMG 冒烟验证。Linux 任务还会执行 ShellCheck、actionlint 和进程生命周期测试。

macOS 构建方法、权限及测试限制见 [macOS 适配说明](macos.md)。

## 发版步骤

1. 同步以下版本号为同一个 `X.Y.Z`：
   - `package.json`
   - `src-tauri/Cargo.toml`
   - `src-tauri/tauri.conf.json`
   - `MCTier-Android/app/build.gradle.kts` 中的 `versionName`
2. 合并并确认 `master` 构建通过。
3. 推送正式标签 `vX.Y.Z`，或候选标签 `vX.Y.Z-rc.N`。
4. 工作流验证标签格式、标签是否存在以及四处版本是否一致，然后构建、签名、冒烟验证并发布。

手动补发时，在 Actions 页面运行 **Build and release**，输入已存在标签（留空仅构建当前分支）。默认 `publish=false`，只重建 Artifact；确认需要覆盖 Release 资产时再选择 `publish=true`。上传时会生成新的 `SHA256SUMS`，并以同名资产覆盖旧文件。

## 冒烟验证范围

- Windows：用 7-Zip 完整测试 NSIS 结构，确认包含 `MCTier.exe`；正式版额外验证 Authenticode 签名。
- macOS：`hdiutil verify` 校验 DMG，挂载后校验主程序和 EasyTier sidecar 的架构、签名、权限声明与可执行位，实际执行 core/cli 的 `--version`；正式版额外验证公证票据和 Gatekeeper。失败时也会卸载镜像。
- Android：验证 APK 签名、包名、arm64 EasyTier JNI 库与离线第三方声明；正式版额外验证 AAB JAR 签名。
