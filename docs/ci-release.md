# GitHub Actions 构建与发布

工作流位于 `.github/workflows/ci.yml`，统一覆盖质量检查、三端打包、安装包冒烟验证、签名与 GitHub Release 发布。仓库默认分支当前为 `master`，所以“合并主分支”的触发器使用 `master`；若以后将默认分支改为 `main`，需要同步修改工作流中的分支过滤器。

## 触发与产物策略

| 触发方式 | 检查与构建 | Artifact | GitHub Release |
| --- | --- | --- | --- |
| `pull_request` | 前端、Rust、许可证检查；Windows NSIS、macOS Intel DMG、macOS Apple Silicon DMG、Android debug APK；全部产物做冒烟验证 | 不上传（只验证） | 否 |
| push 到 `master` | 完整检查与三端构建 | 开发版，保留 14 天 | 否 |
| push `vX.Y.Z` | 完整检查、正式签名、Android release APK/AAB | 保留 30 天 | 正式 Release |
| push `vX.Y.Z-rc.N` | 与正式版相同 | 保留 30 天 | prerelease，不标记 Latest |
| `workflow_dispatch` | 必须填写已存在的版本标签；可只重建 Artifact，也可选择受控发布 | 保留 14 天 | 仅 `publish=true` 时覆盖同名 Release 资产 |
| 每日 02:00（Asia/Shanghai） | Nightly 完整检查与三端构建 | 保留 7 天 | 否 |

Android 当前只发布 `arm64-v8a`。这是源码现状决定的：EasyTier JNI 与 LocalVQE 原生库目前只在该 ABI 下存在。

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

PR、开发版和 Nightly 的 macOS 包使用 ad-hoc 签名；正式标签构建使用 Developer ID 签名并由 Tauri 执行公证。

### Android

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | JKS/keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名 key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

建议在仓库中创建名为 `release` 的 GitHub Environment，并配置 required reviewers。最终 Release job 已绑定该 Environment，因此可以在所有构建与验证通过后增加一次人工批准。

## Windows Npcap 再分发门禁

Windows 官方 EasyTier v2.5.0 二进制静态依赖 Npcap 的 `Packet.dll`。`THIRD_PARTY_NOTICES.md` 当前记录项目尚未获得 Npcap OEM Redistribution License，所以工作流允许 PR 在 Runner 内构建和验证，但拒绝把 Windows 安装包上传为 Artifact 或 Release 资产。

获得有效再分发许可并完成法务确认后，添加 repository variable：

```text
NPCAP_REDISTRIBUTION_APPROVED=true
```

不要把该变量当作普通的“跳过检查”开关；它代表项目方已经取得并确认相应授权。macOS 与 Android 产物不受此门禁影响。

## 发版步骤

1. 同步以下版本号为同一个 `X.Y.Z`：
   - `package.json`
   - `src-tauri/Cargo.toml`
   - `src-tauri/tauri.conf.json`
   - `MCTier-Android/app/build.gradle.kts` 中的 `versionName`
2. 合并并确认 `master` 构建通过。
3. 推送正式标签 `vX.Y.Z`，或候选标签 `vX.Y.Z-rc.N`。
4. 工作流验证标签格式、标签是否存在以及四处版本是否一致，然后构建、签名、冒烟验证并发布。

手动补发时，在 Actions 页面运行 **Build and release**，输入已存在标签。默认 `publish=false`，只重建 Artifact；确认需要覆盖 Release 资产时再选择 `publish=true`。上传时会生成新的 `SHA256SUMS`，并以同名资产覆盖旧文件。

## 冒烟验证范围

- Windows：用 7-Zip 完整测试 NSIS 结构，确认包含 `MCTier.exe`；正式版额外验证 Authenticode 签名。
- macOS：`hdiutil verify` 校验 DMG，挂载后确认主程序可执行，并用 `codesign --verify --deep --strict` 验证应用签名。
- Android：验证 APK 签名、包名、arm64 EasyTier JNI 库与离线第三方声明；正式版额外验证 AAB JAR 签名。
