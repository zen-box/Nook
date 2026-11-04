# Nook

Nook 是一个私密、离线优先的个人生活空间，目标平台为 iOS 17+。客户端已决定改用 **Swift + SwiftUI**，后端继续使用 **Go**。

## 技术栈

| 层级 | 选型 |
|---|---|
| iOS 界面 | SwiftUI、Observation、NavigationStack、Swift Charts |
| 可移植业务核心 | Swift Package `NookCore`，Foundation / Codable 与协议抽象 |
| iOS 本地数据 | SQLite + GRDB 7.12.0、数据库迁移；当前搜索在内存中过滤 |
| iOS 系统集成 | Keychain、LocalAuthentication、UserNotifications、PhotosPicker |
| 本地密码库 | libsodium（swift-sodium 0.11.0）、Argon2id、XChaCha20-Poly1305 |
| 工程与依赖 | XcodeGen + Swift Package Manager |
| 服务端 | Go；具体数据库、对象存储和部署方案后续确定 |
| 构建与体验 | Windows 编辑 / 核心包测试，Codemagic macOS 编译 + App Preview |
| 真机测试 | 云端生成未签名 IPA → 万能签重新签名 → 自己的 iPhone |

## 当前实现与迁移状态

- [旧 Flutter 原型归档](archive/flutter-prototype-2026-11-04/README.md)：原 `app/` 已移至 `archive/flutter-prototype-2026-11-04/app/`，同时保存旧版规格与 README。原型包含首页、便签、基础日程和收支记录，使用 shared_preferences 本地 JSON；新客户端的视觉以用户提供的参考图为准。
- `server/`：Go 服务端骨架，已有 `/healthz` 健康端点，暂不接收业务数据。
- Swift for Windows 6.4.2 已装在 `E:\Swift\Toolchain`，编译、运行、包构建和 Foundation JSON 测试已通过。
- `packages/NookCore/`：业务模型、金额与日期计算、查询统计、备份格式、同步信封、密码生成器和 Repository 协议。Windows 上 `swift test` 88 个测试全部通过。
- `ios/`：SwiftUI App，包含首页、便签、密码库、日程、记账五个入口，以及中英文界面和设置。正式启动读取 SQLite，示例数据仅用于 Debug UI 测试。
- 本地功能：便签 / 清单 / 照片、日程 / 行程 / 纪念日、收支增删改、统计、货币与月预算设置、JSON 备份导出和恢复。定时日程支持本地通知，需允许通知权限。
- 密码库：主密码创建与解锁、账号 / 卡片 / 自定义秘密字段、搜索 / 收藏 / 密码生成、限时本机剪贴板、修改主密码和重置；密文落库，Keychain 快捷解锁要求系统认证，后台锁定并遮盖应用切换快照。详见 [本地密码库格式与验收](docs/local-vault.md)。
- 构建记录：`8dd62d0` 已在 Codemagic 生成未签名 IPA。本次持久化与密码库版本通过 Windows 核心测试、Go 检查和 iOS Swift 语法检查；**完整 iOS 编译、App 单元/UI 测试与真机验收仍需对最新提交执行**。
- `codemagic.yaml` + `scripts/`：模拟器 Preview、未签名 IPA、测试三个工作流，以及命令行调用构建 API 的脚本。
- JSON 备份包含便签、日程、行程、纪念日与收支；**不包含照片文件、密码库和设置**。请勿把它当成完整迁移包。卸载前需另行保管密码库中的重要凭据；忘记主密码只能清空重建。
- 后续阶段：账号、服务端数据接口、加密同步、统一密钥 / 恢复协议、FTS5、EventKit 和 AI。Go 服务端目前仍只有健康检查。

## 目录

```text
ios/
  project.yml            XcodeGen 工程定义（生成的 Nook.xcodeproj 不入库）
  Config/                Info.plist
  Nook/App               入口、Tab 与导航路由
  Nook/DesignSystem      颜色 / 字体 / 间距 Token、卡片、悬浮 Tab 栏等组件
  Nook/Data              AppStore、Database / Vault、照片、提醒、示例数据
  Nook/Features          Home / Notes / Vault / Schedule / Finance / Settings
  Nook/Resources         Assets.xcassets、Localizable.xcstrings
  NookTests, NookUITests 单元测试与 UI 测试
packages/NookCore/       可在 Windows 编译测试的业务核心
server/                  Go 服务端骨架
docs/                    决策记录、API 约定
testvectors/             预留给后续同步协议；本地密码库向量在 ios/NookTests
scripts/                 构建、测试、图标和字符串脚本
```

## 开发与测试流程

```text
Windows 编写 Swift / SwiftUI / Go
  ├── Swift for Windows：纯 Swift 核心包编译与单元测试
  ├── Go：本地后端运行与测试
  └── 命令行调用 Codemagic API：触发云端 macOS + Xcode
       ├── 模拟器 Nook.app → App Preview 交互与截图
       └── 真机 Nook-unsigned.ipa → 万能签 → iPhone 实测
```

Windows 本机检查纯 Swift 业务代码；完整 SwiftUI App、GRDB 与 Apple 框架由云端编译和测试。App Preview 需在支持该功能的团队账户启用，构建和 Preview 按当前账户额度安排。模拟器产物与真机 IPA 分别构建。

首页先在 Preview 中对照参考图验收，再扩展其他页面；真机包按里程碑集中安装。云端工作流不要求提供 Apple 签名证书或本地 Mac。

## 当前可用的本地命令

查看 Swift 工具链：

```powershell
swift --version
```

Go 服务端检查与运行：

```powershell
Push-Location server
try {
    go test ./...
    go vet ./...
    go run .
} finally {
    Pop-Location
}
```

服务启动后访问 `http://localhost:8080/healthz`。远程 Preview / iPhone 联调需配置其可达的 API 地址，不能把 Windows 的 `localhost` 直接用于远程设备；首版本地 MVP 不依赖后端。

NookCore 核心包，在仓库根目录执行：

```powershell
swift build --package-path packages/NookCore
swift test --package-path packages/NookCore
```

一次跑完 Swift 核心包和 Go 的检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-local.ps1
```

改了 logo 或界面文字后重新生成资源（需要 Python 和 Pillow）：

```powershell
python -I scripts/make-app-icon.py logo.png ios/Nook/Resources/Assets.xcassets
python -I scripts/build-strings.py .
```

## 在 Codemagic 上构建

第一次需要做的设置：

1. 在 GitHub 新建仓库，把本项目推送上去（默认分支 `main`）。
2. 在 Codemagic 添加这个仓库，它会读取根目录的 `codemagic.yaml`。App Preview 需要在 Team（按量付费）账户下使用。
3. 在 Codemagic 设置的 Integrations → Codemagic API 里复制 API token；app id 在该 App 页面的网址里（`codemagic.io/app/<app id>`）。

三个工作流：

| 工作流 | 产物 | 用途 |
|---|---|---|
| `ios-simulator-preview` | `Nook.app`（模拟器） | 构建页面里点 Quick Launch 打开 App Preview |
| `ios-device-unsigned` | `Nook-unsigned.ipa` | 下载后用万能签重签，装到自己的 iPhone |
| `ios-tests` | 测试结果 | NookCore 测试 + App 单元测试 / UI 测试 |

可以在 Codemagic 网页上点 Start new build，也可以在命令行触发并下载产物：

```powershell
$env:CODEMAGIC_API_TOKEN = "你的 token"
$env:CODEMAGIC_APP_ID = "你的 app id"
powershell -ExecutionPolicy Bypass -File scripts/codemagic-build.ps1 -Workflow ios-simulator-preview
powershell -ExecutionPolicy Bypass -File scripts/codemagic-build.ps1 -Workflow ios-device-unsigned -DownloadDir build
```

脚本会打印构建页面地址，等待构建结束并列出产物；`-NoWait` 只触发不等待，`-BuildId` 查看已有构建。App Preview 只能在网页上启动（Codemagic API 不提供这个接口）。token 只放在环境变量里，不要写进仓库。

完整技术边界、目标目录、云端构建示例与阶段验收见 [Nook 开发规格书（Swift / SwiftUI 版 v3）](Personal-Hub-开发规格书-v2.md)。
