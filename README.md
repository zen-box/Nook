# Nook

Nook 是一个面向 iPhone 的私密生活工具：便签、任务、日程、行程、纪念日和记账放在本地，密码库单独加密。需要多设备同步时，用户自行配置 S3；需要快捷处理事务时，用户自行接入 AI API。日常使用不依赖 Nook 服务器。

## 当前技术栈

| 层级 | 实现 |
|---|---|
| iOS 17+ 客户端 | Swift 6、SwiftUI、Observation，连续便签编辑器使用 UITextView |
| 可移植业务核心 | `packages/NookCore`，Foundation / Codable，可在 Windows 测试 |
| 本地持久化 | SQLite + GRDB 7.12.0，事务和版本化迁移 |
| 密码库 | swift-sodium 0.11.0；Argon2id + XChaCha20-Poly1305 |
| 可选 S3 同步 / 加密备份 | URLSession、SigV4、CryptoKit HKDF / AES-GCM |
| 扫码迁移 | Network / Bonjour、X25519、双端验证码确认、加密分帧传输 |
| 系统能力 | Keychain、LocalAuthentication、UserNotifications、Speech、AVFoundation、WidgetKit |
| 工程 / 构建 | XcodeGen 2.46.0 + SwiftPM；GitHub Actions 原生测试与未签名 Release IPA；保留 Codemagic 工作流 |

`server/` 是早期 Go 健康检查骨架，当前 App 不调用它。旧 Flutter 原型与旧服务端规格保存在 `archive/`，不作为当前架构依据。

## 已接入的功能

- **连续便签**：文字、勾选清单、照片、录音在同一正文内混排；基础富文本、撤销 / 重做、录音播放和本机语音转写。
- **任务与时间管理**：独立任务、日 / 周 / 月 / 年重复日程、星期选择、截止日期 / 次数、仅本次 / 本次及以后 / 整个系列修改；纪念日和本地提醒。
- **交通日程**：车次 / 航班、出发与到达站点、时间与时区、航站楼 / 登机口 / 站台、车厢 / 座位等可选字段。信息由用户维护，不联网查询晚点或实时检票口。
- **记账**：收支与转账记录、分类统计、货币和月预算。金额使用整数最小货币单位，不自动换汇。
- **事务助手**：搜索允许的普通记录，提出选项问题，生成可继续补充的草稿，确认后执行新增 / 修改 / 删除，支持撤销。密码库与基础设施秘密从能力入口隔离。
- **AI 接入**：OpenAI Chat Completions / Responses、Gemini GenerateContent、Claude Messages；自定义 HTTPS API Base、Key、模型列表分页获取与搜索、手填模型、图片输入。模型必须支持对应协议与工具调用；图片能力依模型而定。
- **密码库**：主密码、系统认证快捷解锁、后台锁定与快照遮罩；解密工作移出主线程。密码库不会进入 AI 请求。
- **S3 加密同步**：自配 Endpoint / Bucket / Region / Prefix / 寻址方式 / 凭据；附件先上传，快照最后提交；保留并发冲突、删除墓碑和加密历史，支持显式选版和历史恢复。
- **备份与迁移**：完整 `.nookbackup` 加密包含照片、录音、普通记录、设置与密封密码库；同局域网扫码迁移可选择携带 S3 连接。API Key 不迁移。
- **小组件**：今日安排 / 任务、纪念日和快捷入口，默认隐藏详细标题；依赖重签时正确保留 App Groups 与扩展权限。

功能边界、密钥和恢复流程见 [当前规格书 v4](Personal-Hub-开发规格书-v2.md)、[同步与恢复](docs/sync-and-recovery.md)、[便签与提醒](docs/notes-and-reminders.md)、[密码库](docs/local-vault.md)。

## 三种密钥不要混淆

| 内容 | 用途 | 换手机 / 重装后需要 |
|---|---|---|
| S3 访问凭据 | 读写用户的存储桶 | 同步需重新配置，或通过受确认的设备迁移携带 |
| `NOOK1.…` 恢复码 | 解密对应 S3 资料库或对应备份包 | 必须单独保管；仅有 S3 凭据不能解密 |
| 密码库主密码 | 解开密封密码库 | 恢复码不会替代它；快捷解锁密钥不会迁移 |

丢失全部设备及对应恢复码后，S3 密文无法恢复。手动恢复备份会替换当前本地资料，请先导出当前备份。旧 JSON 导出仅供兼容，不含照片 / 录音文件、密码库和完整设置。

## 开发与验证

在 Windows 编辑 Swift，在 macOS / Xcode 编译和测试完整 App。Windows 通过不代表 SwiftUI / Apple 框架已经通过编译。

```powershell
swift test --package-path packages/NookCore
```

macOS（Xcode 已安装）运行：

```sh
bash scripts/generate-project.sh
IOS_TEST_DESTINATION='platform=iOS Simulator,name=你的可用 iPhone 模拟器' bash scripts/test-ios.sh
bash scripts/build-ios-device-unsigned.sh
```

推送 `main` 或 `codex/**` 会触发 `.github/workflows/ios.yml`：核心包测试 → App 单元 / UI 测试 → 未签名 Release 真机构建。Actions 保存 `ios-diagnostics`（日志、xcresult、截图）和 `Nook-unsigned`（IPA）。下载 IPA 后由用户重签安装；模拟器 `.app` 不能改包成真机 IPA。

`codemagic.yaml` 仍提供 `ios-simulator-preview`、`ios-device-unsigned`、`ios-tests`。命令行脚本 `scripts/codemagic-build.ps1` 从环境变量读取 `CODEMAGIC_API_TOKEN` 与 `CODEMAGIC_APP_ID`；不要把 token 写入仓库。Preview 资格与额度以当前平台账户为准。

本地核心测试当前为 **108 项**。App 单元、UI 和 Release 构建以交付提交对应 Actions 记录为准。真实 S3 厂商兼容性、双手机局域网迁移、Face ID、麦克风、通知和重签小组件还需在设备上验收；本机与模拟 HTTP 测试不会替代这些实测。

## 目录

```text
ios/                    主 App、Widgets、单元 / UI 测试与 XcodeGen 配置
packages/NookCore/      模型、查询、重复规则、Agent 校验与同步冲突模型
scripts/               构建、测试、图标和本地化生成
.github/workflows/     原生 iOS 验证流水线
docs/                  当前协议、安全边界、决策与验收说明
server/                早期 Go 骨架；当前客户端不依赖
archive/               Flutter 原型、历史规格
```

改动界面文字后执行 `python -I scripts/build-strings.py .`。图标由 `scripts/make-app-icon.py` 生成。当前搜索仍是本地内存过滤；FTS5、统一文件中心、EventKit、自动填充等未实现需求保留在规格书的后续清单。
