# 构建与发布流程

发布工作流位于 `.github/workflows/release.yml`。它只由版本标签和明确的
`workflow_dispatch` 触发，现有 `.github/workflows/ci.yml` 仍负责日常分支/PR
检查。

## 标签规则

正式发布使用 `v<SemVer>`，例如 `v3.0.0`；候选版可以使用任意合法的
SemVer 预发布标识，例如 `v3.0.0-rc.1`。标签去掉开头的 `v` 后，必须与下面
三个桌面版本字段逐字相同：

* `package.json` 的 `version`
* `src-tauri/Cargo.toml` 的顶层 `version`
* `src-tauri/tauri.conf.json` 的 `version`

如果仓库包含 Android 模块，`MCTier-Android/app/build.gradle.kts` 的
`versionName` 还必须是 `<版本>-android`（例如 `3.0.0-android`）。这是现有
Android 产品标识的后缀，不会改变桌面包的版本。

`scripts/validate-release-version.sh` 在 metadata job 和本地都执行上述检查，
并拒绝不符合 SemVer 的标签。标签含 `-预发布标识` 时 Release 会被标记为
`prerelease` 且不会成为 Latest；没有预发布标识的标签会成为稳定 Latest。

## 触发方式

推送 `v*` 标签后，metadata job 会检出该标签并记录唯一的 commit SHA。所有
后续 job 都用这个 SHA 检出，避免移动标签造成 Windows、Linux、macOS 和
Android 混用不同源码。发布前的必需 job 是：

* `Frontend build and tests`
* `Desktop package (Windows x86_64)`、`Desktop package (macOS x86_64)`、
  `Desktop package (macOS arm64)`
* `Linux package (x86_64)`
* `Android package (arm64 debug-signed)`

`Publish GitHub Release` 依赖以上全部成功，然后下载所有矩阵 artifact。
`scripts/collect-release-artifacts.sh` 会拒绝缺失、空文件、软链接、占位文件、
旧版本文件和意外文件；通过后才生成 `SHA256SUMS` 并创建/更新 Release。这样
某个平台构建失败时不会留下只有部分平台的正式 Release。

Actions 页面中的 **Tag release → Run workflow** 用于诊断或补发：

| 输入 | 行为 |
| --- | --- |
| `tag` 留空，`publish=false`（默认） | 构建当前选定分支的 Windows/Linux/macOS/Android artifact，不发布 Release |
| 填已有 `v<SemVer>`，`publish=false` | 从该标签重建 artifact，不发布 Release |
| 填已有 `v<SemVer>`，`publish=true` | 所有检查和 artifact 门禁通过后，仅发布/续传该标签的 draft；已有公开 Release 会明确失败 |

`publish=true` 没有标签时会在 metadata 阶段失败。手动输入的标签必须存在于
当前仓库，且正式发布仍会经过同一套版本校验；因此普通分支构建不会因为误点
按钮而创建 Release。

## 构建矩阵和资产

| 平台 | Runner/target | 构建与监督 | Release 资产 |
| --- | --- | --- | --- |
| Windows | `windows-latest` / `x86_64-pc-windows-msvc` | `fetch-binaries.ps1` 获取固定运行时；`build-easytier-npcap-free.ps1` 重建并检查不含 Npcap；7-Zip 检查 NSIS | `MCTier-<版本>-windows-x86_64-unsigned.exe` |
| Linux | `ubuntu-latest` / x86_64 | `MCTier-Linux/scripts/fetch-binaries.sh` 校验 EasyTier；Tauri 实际生成 AppImage 和 Debian 包 | `MCTier-<版本>-linux-x86_64.AppImage`、`MCTier-<版本>-linux-x86_64.deb` |
| macOS | `macos-15-intel` / `x86_64-apple-darwin`；`macos-15` / `aarch64-apple-darwin` | `fetch-macos-binaries.sh arm64\|x86_64` 校验架构匹配的 sidecar；Tauri ad-hoc app、DMG、`check-macos-bundle.sh` 冒烟检查 | `MCTier-<版本>-macos-x86_64-adhoc.dmg`、`MCTier-<版本>-macos-arm64-adhoc.dmg` |
| Android | `ubuntu-latest` / `arm64-v8a` | Gradle `assembleDebug`；`apksigner`、包名、JNI 和离线声明检查 | `MCTier-<版本>-android-arm64-debug-signed.apk` |

Windows 的资源检查会拒绝 `MCTIER-CI-PLACEHOLDER-NOT-A-REAL-BINARY`，也会拒绝
`Packet.dll`/`Packet.lib`。macOS 构建要求 B 侧提供
`scripts/fetch-macos-binaries.sh`、`scripts/check-macos-bundle.sh` 和
`src-tauri/tauri.macos.conf.json`；sidecar 下载脚本必须先校验固定 SHA-256。
Linux 包含真实 AppImage，而不是只运行 `cargo check`。

## 签名、公证和 Secrets

当前 fork 的发布设计不依赖仓库 Secrets：

* Windows NSIS 是未签名包，但构建仍通过 PE/NSIS 检查；用户安装时可能看到
  SmartScreen 警告。
* macOS app/DMG 使用 ad-hoc 签名，能用于构建产物和测试，不提供 Developer ID
  信任链，也没有公证票据；Gatekeeper 可能阻止直接打开。
* Android 包是 Android debug keystore 签名的可安装 APK，名称明确带有
  `debug-signed`；它不是 Play Store release、不能作为正式发布签名凭据。
* Linux 资产当前没有发行商签名；下载者应使用随 Release 提供的
  `SHA256SUMS`。

未来要做正式签名/公证，应在独立变更中接入 GitHub Environment 和最小权限的
Secrets，而不是把密钥写入 workflow。可选材料包括：

* Windows：`WINDOWS_CERTIFICATE_BASE64`、`WINDOWS_CERTIFICATE_PASSWORD`、
  `WINDOWS_TIMESTAMP_URL`
* macOS：`APPLE_CERTIFICATE_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_ID`、
  `APPLE_APP_SPECIFIC_PASSWORD`、`APPLE_TEAM_ID`
* Android：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、
  `ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`

这些变量在当前工作流中不会被读取；缺少它们不会让 fork 的无密钥构建退化成
伪签名包。macOS 的 `macOSPrivateApi` 和透明悬浮窗也意味着，即使完成
Developer ID 公证，仍应先验证目标系统兼容性，且不应宣称可提交 Mac App Store。

## 复用与舍弃的历史方案

选择性参考了 `origin/feat/workflow` 的 `ci.yml` 和 `docs/ci-release.md`：

* 复用了固定 SHA checkout、Windows/Linux/macOS/Android 构建矩阵、EasyTier
  校验脚本的调用方式、macOS DMG/sidecar 冒烟检查、artifact 汇总和
  `SHA256SUMS` 的思路。
* 没有整体复制那份近千行单文件 CI；发布工作流独立于 PR CI，避免质量检查和
  发布策略互相膨胀。
* 舍弃了 push 分支、schedule 和 PR 也进入同一发布工作流的路径；本任务只需
  标签发布和可诊断的手动构建。
* 舍弃了强制 Windows/macOS/Android 签名和 `release` Environment。当前 fork
  没有这些 Secrets/Environment，强制要求会使无密钥 tag 永远失败；签名作为
  后续可选能力保留在文档中。
* Release 先创建 draft，全部资产和校验和上传成功后才转为公开；已有公开
  Release 会被明确拒绝，不会在重跑时覆盖一个可能已被用户下载的版本。只有
  未完成的 draft 才允许安全续传。
* 没有复制参考方案的 `-rc.N` 狭窄匹配，而是使用完整 SemVer 预发布标识，且
  仍要求版本字段逐字同步。

历史运行证据：`33371134938` 和 `33370541335` 的 Windows job 因补丁后仍检测
`#[link(name = "Packet")]` 失败，`33363176634` 的 Linux/Rust job 因
`chat_auth` 的 `too_many_arguments` Clippy 门禁失败；最终
`34076451166`（PR）和 `33939592279`（push）在 `ea83fe7` 上的 Windows、Linux、
macOS、Android 和汇总 job 全部成功。当前 workflow 因此把 Npcap/占位文件、
产物完整性和源码 SHA 作为阻塞门禁，同时不把历史过严 Clippy 作为发布包装的
唯一成功条件。

## 本地验证

```sh
./scripts/validate-release-version.sh v3.0.0
bash -n scripts/validate-release-version.sh \
  scripts/package-release-artifacts.sh scripts/collect-release-artifacts.sh
shellcheck scripts/validate-release-version.sh \
  scripts/package-release-artifacts.sh scripts/collect-release-artifacts.sh
actionlint .github/workflows/release.yml
```

这些检查分别排除版本漂移、shell 语法错误、未引用变量/不安全展开，以及
GitHub Actions YAML/表达式错误；真正的跨平台编译和产物冒烟仍由对应 runner
完成。
