# Nook 开发规格书（Swift / SwiftUI 版 v3）

> 项目名：Nook  
> 产品定位：Nook 是一个私密、离线优先的个人生活空间，把日常安排与重要信息（便签、密码、日程、财务和文件）收纳在一个由用户掌控的地方。  
> 文档用途：产品需求、客户端实现、后端接口、安全设计、iOS 系统能力边界与测试验收的统一依据，可交付 Codex 分阶段实施。  
> 修订重点：原生 Swift / SwiftUI 客户端、Go 服务端、Windows 纯 Swift 检查、Codemagic 云端编译与 App Preview、未签名 IPA + 万能签真机测试。
> 版本：v3（2026-11-04）。  
> 当前开发环境：Windows。  
> 产品目标平台：iOS 17+；首版专注 iPhone。

---

## 0. 给 Codex 的工作约定

1. 按第 13 章阶段顺序开发并逐阶段验收；明确标记为后置的安全阶段可延后，不阻塞本地 MVP 的其他核心模块。
2. 客户端改用 Swift + SwiftUI；状态与交互使用原生能力，服务端继续使用 Go。
3. 将可移植的数据模型、业务规则、协议和同步状态机放入独立 Swift Package `packages/NookCore`；SwiftUI、数据库实现和 Apple 系统能力放在 iOS 工程。
4. Windows 是主要编辑环境。Swift for Windows 用于编译、测试纯 Swift 核心包；Go 服务端在本机运行和测试。
5. SwiftUI、iOS SDK、iOS 数据保护和系统集成由 Codemagic 的 macOS + Xcode 编译与测试；Windows 核心包测试只覆盖其实际包含的代码。
6. 日常页面检查使用 Codemagic CI 与 App Preview；可在 Windows 通过命令行调用构建 API，iOS 编译实际发生在云端 macOS 构建机。
7. 按功能里程碑生成未签名的真机 IPA，由用户通过万能签重新签名并安装到自己的 iPhone。云端构建无需配置用户的签名证书；不要求本地拥有 Mac。
8. 服务端使用 Go。数据库、对象存储、缓存、消息队列和部署平台暂不锁定；先定义业务职责、API 契约、数据模型和可替换接口，再由项目所有者决定具体基础设施。
9. 禁止自研密码学算法，只使用成熟、经过审查的密码学库。跨端加密协议必须有固定测试向量，客户端和服务端实现通过同一组测试向量。
10. 服务端任何代码路径、日志、错误信息都不得出现明文业务数据、密码、主密钥或解密后的文件内容。
11. 遇到本文未定义的细节，选择最简单且可迁移的方案，并在 `docs/decisions.md` 记录决策、原因和影响。
12. 不得擅自删除需求、降低安全等级或改变数据格式。发现协议存在歧义或安全风险时，先记录并提出方案，不得自行发明密码学设计。
13. 新工程目录采用 `/ios`、`/packages/NookCore`、`/server`、`/docs`、`/testvectors`、`/scripts`，根目录维护 `codemagic.yaml`。旧 Flutter 原型已移入 `/archive/flutter-prototype-2026-11-04/app`，保留作功能与数据迁移参考。
14. UI 以用户提供的参考图为准，先完成首页的实际渲染与视觉确认，再扩展其他页面；旧原型页面不作为已验收的设计基准。

## 1. 产品概述

Nook 是一个私密、离线优先的个人生活管理 App。它把日常安排与重要信息收纳在一个由用户掌控的空间里；核心模块包括：首页、便签、密码库、日程、记账、文件附件中心，并预留可控 AI 功能。产品取舍优先保证隐私、离线可用和数据可迁移，而不是追求信息聚合数量或依赖云端能力。

### 1.1 核心原则

1. **离线优先**：所有读写先落本地数据库，后台同步；网络不可用时仍可查看和编辑已下载的数据。
2. **服务端零知识**：业务内容原则上由客户端加密，服务端只保存密文和必要的不透明元数据。
3. **数据所有权**：可完整导出；可通过加密备份包恢复到新设备或全新账号。
4. **安全优先**：密码库永不进入 AI 请求；不为方便搜索、统计而将敏感明文发送到服务端。
5. **统一数据引擎**：先完成通用加密记录、文件和同步引擎，各业务模块建立在通用能力之上。
6. **基础设施可替换**：客户端不绑定特定云厂商；后端不绑定特定数据库或对象存储实现。
7. **视觉一致性**：全 App 使用统一 Design System，以用户参考图约束布局、配色与信息层级；SwiftUI 系统控件应适配这套视觉规范。

### 1.2 产品模块

- 首页 Dashboard：今日概览、近期日程、即将到来的纪念日、最近便签、本月支出、快捷入口。
- 便签 Notes：文字、Markdown、待办、标签、图片和附件。
- 密码库 Vault：网站账号、邮箱、服务器、软件账号、银行卡、安全笔记、自定义字段。
- 时间管理 Calendar：统一日历入口，包含普通日程、待办、多日旅行/出差行程、纪念日与周年倒计时。
- 记账 Finance：收入、支出、转账、账户、分类、预算、周期账单和订阅管理。
- 文件 Files：统一附件中心，供便签、行程、账单等模块引用。
- 设置 Settings：账号、设备、安全、系统集成、备份、导出、AI、存储用量。

---

## 2. 技术边界与选型原则

### 2.1 客户端

- UI 与业务客户端：Swift + SwiftUI，使用 Swift 6 语言模式；具体编译器、依赖与云端 Xcode 的兼容组合在 P0 固定。
- 最低正式支持平台：iOS 17+。
- 状态管理：Observation 的 `@Observable` 配合 `@State`、`@Bindable` 与环境注入；UI 状态在 `@MainActor` 隔离，避免引入额外状态框架。
- 路由：`NavigationStack` + 类型化路由；五个主入口由根视图统一管理，各入口保留自己的导航状态。
- 业务核心：独立 Swift Package `NookCore`，使用 Foundation、Codable 与协议抽象；不依赖 SwiftUI、UIKit、GRDB 或 Apple 专属框架，供 Windows 和 iOS 共用。
- 本地数据库：SQLite + GRDB，负责 schema、DAO、事务、迁移和查询。GRDB 实现属于 iOS 数据层，通过 Repository 协议接入核心包，实际数据库测试在 macOS / iOS 执行。
- 本地全文搜索：SQLite FTS5；只索引客户端可解密的数据，密码字段不得进入索引。
- 网络与并发：URLSession + async/await；共享可变状态使用 actor 等隔离手段，API 地址按构建环境注入。
- 加密：保留第 5 章的 XChaCha20-Poly1305、Argon2id、HKDF、X25519 协议，采用经审查的成熟实现及 Swift / C 绑定。CryptoKit 可承担其支持的原语；XChaCha20-Poly1305 和 Argon2id 需另行选用成熟库，不能为适配框架而更换算法或格式。
- 安全存储：通过 Security / Keychain 保存密钥材料；生物识别使用 LocalAuthentication。
- 通知：UserNotifications 本地通知优先；APNs 后置，并受实际签名权限约束。
- 图表：Swift Charts，外层统一配色、字号和数值格式。
- 依赖与工程：Swift Package Manager 管理依赖并提交 `Package.resolved`；用 `ios/project.yml` 和 XcodeGen 在云端生成 Xcode 工程，适配 Windows 编辑流程。

### 2.2 iOS 系统集成与扩展

主客户端直接使用 Swift 调用 Apple 框架，通过薄适配层向业务核心暴露能力：

- Security / Keychain：密钥存储、访问控制和受保护项读取。
- LocalAuthentication：Face ID / Touch ID 与设备认证。
- Data Protection：数据库、WAL / SHM、附件和临时文件的保护属性。
- UserNotifications、EventKit：本地通知和用户主动触发的系统日历读写。
- PhotosUI、文件选择与预览能力：照片、附件导入及内容预览；必要时用 UIKit 封装 SwiftUI 未覆盖的交互。
- WidgetKit、Share、Credential Provider 等独立 Extension Target：按第 2.4 节的签名权限决定是否实施。

Apple 平台实现留在 iOS 工程；Windows 测试通过明确的测试替身验证调用流程，真实权限、硬件和系统行为由 iOS 测试验收。

### 2.3 服务端与存储

服务端使用 Go 实现。数据库、对象存储、缓存、消息队列和部署平台暂不指定。必须先满足以下逻辑能力：

- Auth：认证、会话、设备身份。
- Records：通用加密记录读写。
- Sync：增量同步、游标、冲突检测、幂等。
- Blob：加密文件上传、下载、分块、续传和删除。
- Key Metadata：密钥包裹材料及设备公钥等元数据。
- Backup：备份导出、恢复和完整性校验。
- Push：设备推送令牌管理（后置；依赖 APNs 签名权限）。
- AI Proxy：可选的无状态 AI 转发服务。

必须通过 Repository / Storage Provider 等抽象隔离数据库与对象存储实现。业务层不得直接依赖某一家云厂商的 SDK 或专有数据结构。

### 2.4 iOS 系统能力与当前签名环境约束

当前开发者使用 Windows 编辑代码，由 Codemagic 生成未签名的真机 IPA，再通过用户自己的万能签服务签名并安装。Codemagic 无需持有用户的签名证书或 Provisioning Profile。最终签名的实际 Entitlements 尚未确认，普通系统 API 与需要额外签名能力的扩展分别验收。

**基础系统 API（通常可在普通签名 App 中使用，仍须用实际签名 IPA 和真机验收）：**

- Face ID / Touch ID：通过系统认证 API 调用；配置用途说明。
- 本 App 自身 Keychain：保存本 App 的密钥材料；跨 App / Extension 共享 Keychain Access Group 另行验证。
- 本地通知：用于日程、待办、订阅和纪念日提醒，不依赖 APNs。
- 相机与系统照片选择器：按用户操作时申请；优先使用系统照片选择器，避免申请完整照片库权限。
- 系统日历访问：用户授权后通过 EventKit 读取或写入；首版默认只提供用户主动触发的导入/导出或单向写入。
- 文件选择器、剪贴板、触觉反馈：按需使用，不应在首次启动时集中申请权限。

**依赖 App Extension、App Groups 或特定 Entitlement 的能力（必须先检查实际签名，再决定是否纳入正式版本）：**

- WidgetKit 桌面/锁屏小组件：需要 Widget Extension；若主 App 与扩展共享数据，通常还需要 App Groups。
- Share Extension：需要独立 Extension Target 和对应签名配置。
- 密码自动填充 Credential Provider：需要独立扩展及 `com.apple.developer.authentication-services.autofill-credential-provider` 等相应配置。
- APNs 远程推送：需要签名具备 `aps-environment` 等对应推送配置；不能与本地通知混为一谈。
- Live Activities / 灵动岛：需要 ActivityKit 与 Widget Extension 配置；本地启动/更新和 APNs 远程更新是不同能力，分别验证。
- App Groups / Shared Keychain：必须确认签名 profile 授权对应 App Group / Keychain Access Group。
- iCloud：依赖 iCloud Container 等 entitlement，首版不作为必要依赖。

**万能签验收规则：**

1. 万能签是签名/安装服务，不代表其提供的证书必然包含上述全部 Entitlements。
2. 在取得实际签名 IPA 后，检查主 App 与每个 Extension 的签名 Entitlements，以及 `embedded.mobileprovision` 中允许的 Entitlements。
3. 仅当对应权限确实存在、扩展可安装且真机测试通过，才将该能力标记为「支持」。
4. 不具备权限时，基础功能必须仍可用：本地通知替代远程推送；App 内附件选择替代分享扩展；App 内密码复制替代自动填充；普通日程页面替代 Widget / 灵动岛。
5. 不得为了获得扩展能力而假设可以随意添加 Entitlement；签名服务无法提供时，将该能力标记为可选或暂缓。
6. 首次启动不得一次性请求所有权限；必须在用户首次使用对应功能时解释用途并请求授权。

### 2.5 开发环境、工程目录与迁移状态

工作流：

```text
Windows 编辑 Swift / SwiftUI / Go
  ├── Swift for Windows → NookCore 编译与单元测试
  ├── Go → 本地服务与 go test
  └── 命令行调用 Codemagic API → 云端 macOS + Xcode
       ├── iOS Simulator 构建 → Nook.app → App Preview 页面交互与截图
       └── iPhone 真机构建 → Nook-unsigned.ipa → 万能签 → 真实 iPhone
```

- 当前本机 Swift 为 6.4.2，工具链位于 `E:\Swift\Toolchain`；Windows 不运行 Xcode 或 SwiftUI Canvas。
- Swift 核心包、云端 Xcode、XcodeGen 与依赖版本在 P0 固定并记录；本机安装的 Swift 版本不代表云端已使用同一版本。
- Codemagic App Preview 运行的是构建后的模拟器 App，需在支持该功能的团队账户中启用。它与 Xcode 的 SwiftUI Canvas 是不同工具。
- CI 构建与 Preview 分别计量，按当前账户的可用额度安排使用；本规格不把试用额度视为长期免费承诺。
- 项目当前保留 Go 服务端骨架；旧 Flutter 原型及切换前的文档快照已移入 `archive/flutter-prototype-2026-11-04/`，入口见[归档说明](archive/flutter-prototype-2026-11-04/README.md)。Swift 工程、核心包、云端工作流和 Preview 尚待 P0 建立。旧原型使用 shared_preferences 保存本地 JSON，尚不具备本规格要求的 SQLite、加密存储或同步能力。
- 新客户端在 `ios/` 建设；迁移以用户需求与参考图为准。若旧原型已有需要保留的数据，先提供导出、映射和导入路径，再切换存储；不直接覆盖旧数据。

目标结构（P0 起分阶段建立）：

```text
/ios
  project.yml                 # XcodeGen 工程定义
  /Nook                       # SwiftUI App、设计系统、功能页面、iOS 适配层
  /NookTests                  # iOS 数据层与平台集成测试
  /NookUITests                # 页面交互与截图
/packages/NookCore            # Package.swift、纯 Swift 核心代码及测试
/server                      # Go 服务端
/docs                        # 决策、接口与设计参考
/testvectors                 # 共享加密协议向量
/scripts                     # 本地检查及云端构建脚本
/archive/flutter-prototype-2026-11-04
  /app                       # 已归档的旧 Flutter 原型与构建产物
  README.md                  # 归档说明与查阅入口
  README-flutter.md           # 切换前的旧 README
  Personal-Hub-开发规格书-v2.md # Flutter 版 v2 历史快照
codemagic.yaml               # 模拟器预览与未签名真机包两个工作流
```

实施依据：[Swift Windows 安装说明](https://www.swift.org/install/windows/)、[GRDB](https://github.com/groue/GRDB.swift)、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。云端构建与 Preview 见第 13.3 节。

---

## 3. UI / UX 与 Design System

### 3.1 视觉定位

整体风格：**Apple-inspired Light Minimal + Clean Card-based UI**。

视觉关键词：整洁、克制、轻盈、留白、低饱和、层级清楚、长期使用耐看。用户提供的浅色蓝白卡片式参考图是首版页面结构与视觉验收基准，迁移技术栈不改变这套设计目标。

设计原则：

1. 页面以白色和极浅冷灰为主，浅蓝作为主强调色。
2. 留白优先，不把所有信息挤在首屏；通过卡片和间距建立层级。
3. 大卡片圆角统一，内部小组件圆角略小；避免每个元素使用不同圆角。
4. 阴影非常轻或不使用阴影，优先用背景色差和细边框区分层级。
5. 图标统一使用简洁线性风格，避免混用实心、拟物和不同粗细图标。
6. 字体层级清楚：页面标题、卡片标题、正文、辅助说明有稳定的字号和字重体系。
7. 渐变只作为少量强调，不允许大面积高饱和渐变、强玻璃拟态或过度装饰。
8. 默认浅色模式，同时支持深色模式；两套主题共用同一套语义 Token。
9. 页面要有真实内容密度，不做空洞的展示型 Dashboard；也不能因追求信息量而失去留白。
10. 所有页面必须适配不同 iPhone 尺寸、安全区、动态字体和键盘弹出状态。

### 3.2 初始设计 Token（可在视觉验收后微调）

| Token | 建议值 / 规则 | 用途 |
|---|---|---|
| `background` | `#F6F8FC` | 页面底色，浅冷灰 |
| `surface` | `#FFFFFF` | 卡片和主要容器 |
| `primary` | `#7DADE3` | 低饱和浅蓝主色 |
| `primarySoft` | `#EAF2FC` | 浅蓝选中态背景 |
| `textPrimary` | `#202938` | 主文字 |
| `textSecondary` | `#7B8798` | 辅助文字 |
| `border` | `#E8EDF4` | 细边框、分隔线 |
| `success` | 低饱和薄荷绿 | 成功、收入等状态 |
| `warning` | 低饱和淡橙 | 提醒、待处理状态 |
| `danger` | 低饱和红 | 删除、错误、支出提示 |
| 页面边距 | 20–24 pt | 页面左右留白 |
| 基础间距 | 8 pt 网格 | 统一布局节奏 |
| 大卡片圆角 | 20–24 pt | 首页与主要内容卡片 |
| 小卡片圆角 | 14–18 pt | 列表项、次级容器 |
| 按钮圆角 | 12–16 pt | 操作按钮 |
| 动效 | 短、柔和、克制 | 页面切换和状态反馈 |

颜色值是初始设计 Token，不是不可修改的硬编码。所有颜色、间距、圆角、阴影和字体样式必须集中定义，禁止散落在页面代码中。

### 3.3 导航结构

底部固定 5 个主标签：

1. 首页
2. 便签
3. 密码库
4. 日程
5. 记账

右上角提供统一快速新增入口。快速新增包括：新建便签、新建日程、记一笔账、添加账号、上传文件。

文件中心不占底部主标签，作为全局附件选择器，并提供「设置 → 文件」入口。文件也可以从各业务模块内打开。

日程主标签内部采用二级分区或顶部 Segmented Control，至少包含「日历 / 行程 / 纪念日」三个入口。三者共用统一日期体系和提醒能力，但使用不同的数据模型与详情页面：

- 日历：按月、周、日查看所有可见事件。
- 行程：管理旅行、出差等跨日计划及其子事件。
- 纪念日：管理生日、周年和个人重要日期，显示倒计时或已过去天数。

避免把纪念日伪装成普通全天事件；日历视图可以展示纪念日标记，但点击后进入纪念日详情。

### 3.4 统一组件库

至少建立以下可复用组件：

- `AppScaffold`：页面基础结构、安全区和背景。
- `AppBottomNavigation`：底部五栏导航。
- `AppTopBar`：标题、返回、右侧操作。
- `AppCard`：统一卡片容器。
- `AppSectionHeader`：区块标题与右侧操作。
- `AppButton` / `AppIconButton`：按钮。
- `AppTextField`：输入框。
- `AppSearchField`：搜索框。
- `AppTag` / `AppChip`：标签与筛选项。
- `AppEmptyState`：空状态。
- `AppLoadingState`：加载状态。
- `AppErrorState`：错误与重试状态。
- `AppConfirmDialog` / `AppBottomSheet`：确认弹窗与底部操作面板。
- `AppDatePicker`：日期选择封装。
- `AppAmountInput`：金额输入。
- `AppAttachmentPreview`：附件预览。

组件以 SwiftUI View、ViewModifier 与集中式 Design Token 实现；名称表示职责，不沿用旧框架的组件实现。组件必须支持浅色和深色主题、禁用态、加载态、错误态和无障碍语义。不得在每个业务页面重复实现一套相似组件。

### 3.5 页面视觉验收

- 首页、便签、密码库、日程、记账五个主页面视觉语言一致。
- 以用户参考图逐项对照页面结构、卡片布局、配色、留白和导航；SwiftUI 的默认 List / Form 外观不能代替设计实现。
- 页面左右边距、卡片圆角、标题层级、图标风格统一。
- 长列表滚动、键盘弹出、空状态、加载状态、错误状态均有设计。
- 先在 App Preview 检查首页实际渲染并与参考图对照，再扩展其他主页面；关键页面使用 iOS 模拟器截图建立视觉回归基准。

---

## 4. 系统架构与职责边界

### 4.1 客户端架构

```text
SwiftUI App / Feature Views
  └── Observation State / Presentation
       └── NookCore（纯 Swift Package）
            ├── Domain Models / Use Cases
            ├── Repository / Crypto / Platform Protocols
            └── Sync State Machine / Conflict Rules
       └── iOS Implementations
            ├── SQLite + GRDB Repository
            ├── Encryption Provider / URLSession / File Manager
            └── Keychain / LocalAuthentication / UserNotifications / EventKit

Optional iOS Extension Targets
  └── Widget / Share / Credential Provider / Live Activities

Local SQLite (GRDB)
  ├── Local records / cache
  ├── Outbox queue
  ├── Sync cursor
  └── Local FTS index
```

依赖方向：iOS 页面与适配层依赖 NookCore，NookCore 只依赖可在 Windows 编译的库。真实数据库迁移、加密库集成和 Apple 系统实现由云端 iOS 测试覆盖；Windows 测试使用内存 Repository 等测试替身验证业务规则。

客户端负责：

- UI 和交互。
- 本地数据读写。
- 加密和解密。
- 本地搜索和统计。
- 离线队列。
- 同步调度和冲突展示。
- 文件压缩、加密、分块和预览。
- 本地通知。
- iOS 原生能力调用。

### 4.2 服务端逻辑架构

```text
API Layer
  ├── Authentication / Sessions
  ├── Device Management
  ├── Record Sync
  ├── Encrypted Record Sync（包含 event / plan / anniversary 类型）
  ├── Blob Management
  ├── Key Metadata
  ├── Backup / Export
  ├── Push Token Management
  └── Optional AI Proxy

Persistence Abstraction
  ├── Record Repository
  ├── User / Device Repository
  ├── Sync Sequence Repository
  ├── Blob Store
  └── Backup Store
```

服务端负责：身份认证、权限校验、密文持久化、同步序列、幂等处理、文件存取、设备管理、备份任务和必要的系统运维能力。

服务端不得负责：业务明文搜索、解密后的财务统计、密码明文处理、用户私人内容 AI 分析（除非用户明确选择并主动提交指定内容）。

### 4.3 基础设施可替换原则

- 数据库通过 Repository 接口隔离。
- 对象存储通过 BlobStore 接口隔离。
- 缓存为可选能力，不得成为核心业务正确性的唯一依赖。
- API 协议和客户端数据模型不得绑定具体云厂商。
- 数据导出必须能够迁移到另一套兼容实现。
- 具体云厂商、数据库、对象存储和部署拓扑由项目所有者另行确定。

---

## 5. 密钥体系与加密规则

> 本章保留原规格的设计方向。正式实施前必须进行独立密码学协议审查，确认密钥派生、登录凭证、设备配对、恢复、轮换和备份流程没有循环依赖或实现漏洞。不得仅凭本文描述直接认定方案已经通过安全审计。

### 5.1 密钥层级

```text
RecoveryKey (256 bit 随机，用户离线保管)
PasswordKey (Argon2id 派生)
        │ 分别包裹一份
        ▼
MasterKey (256 bit 随机，明文仅在授权客户端内存中短暂存在)
   ├── HKDF(info=notes)    → 便签密钥
   ├── HKDF(info=finance)  → 记账密钥
   ├── HKDF(info=schedule) → 日程密钥
   ├── HKDF(info=files)    → 文件包裹密钥
   └── VaultKey (独立随机，由 MasterKey 包裹，可额外受生物识别保护)
```

- 每条记录使用随机 nonce 的 XChaCha20-Poly1305。
- AAD 绑定 `record_id || type || key_version`，防止密文被替换到其他记录。
- 每个文件生成独立随机 FileKey。
- 所有密钥材料带 `key_version`，为轮换预留。
- 生产环境必须使用安全随机数生成器；测试向量允许固定 nonce，但固定 nonce 绝不得用于生产加密。

### 5.2 密码派生与登录凭证

原规格提出：注册时生成随机 salt；使用 Argon2id 派生 64 字节，再通过 HKDF 或明确的密钥分离方案得到 AuthKey 与 PasswordKek；AuthKey 作为登录凭证提交，PasswordKek 永不上传；服务端对 AuthKey 再做安全哈希存储。

具体 KDF 参数、派生标签、输入编码、服务端验证方式、抗重放和限流策略必须在协议审查后冻结，并写入测试向量。不得在客户端和服务端分别凭理解实现。

### 5.3 恢复密钥

- 注册时生成 256 bit 随机恢复密钥。
- 展示为便于抄录的 Base32 分组字符串，并包含校验机制。
- 必须强制用户确认已保存，可要求重新输入指定分组。
- 支持复制和导出恢复材料；导出文件必须加密或明确警告。
- 服务端只保存被恢复密钥包裹的主密钥材料，不保存恢复密钥明文。
- 丢失全部设备、密码和恢复密钥时，数据不可恢复；UI 必须明确告知。

### 5.4 设备与密钥流程

- 注册：生成 salt、MasterKey、RecoveryKey、设备密钥对；上传必要的 salt、KDF 参数、认证材料、包裹后的主密钥和设备公钥。
- 登录：获取 salt 与 KDF 参数；本地派生登录材料；验证成功后取得包裹后的主密钥并在本地解开。
- 新设备扫码授权：新设备创建短时配对会话和公钥；旧设备扫码并确认设备名称与指纹；旧设备使用新设备公钥封装主密钥；新设备取回并解开。
- 修改密码：重新派生并重新包裹 MasterKey，不必默认重加密所有业务数据；撤销其他设备会话的策略需明确提示。
- 恢复：验证恢复密钥后解开 MasterKey，设置新密码并生成新恢复密钥；强制用户保存。
- 设备撤销：服务端立即撤销对应会话；是否触发密钥轮换由用户确认并按密钥版本执行。
- 密码库额外保护：VaultKey 在本地受生物识别保护；设备解锁主数据不代表密码库自动解锁。

### 5.5 本地数据保护

- iOS SQLite 数据库及 WAL / SHM 文件应配置合适的 iOS Data Protection 等级。
- 密钥不得写入普通偏好设置、日志、崩溃报告或明文文件。
- 应用切后台或锁屏后按安全策略清理内存中的敏感数据并锁定密码库。
- 剪贴板复制密码后定时清理；清理失败时不得宣称已清理。
- Windows 核心包测试验证安全流程与状态机；iOS Keychain、Face ID、Secure Enclave 和文件保护使用最终签名的真机 App 验收。

---

## 6. 通用数据模型

### 6.1 通用记录信封

所有业务数据采用统一记录信封，具体业务字段放入密文 JSON。

| 字段 | 是否加密 | 说明 |
|---|---|---|
| `id` | 否 | 客户端生成的 UUIDv7 |
| `type` | 否 | note / vault_item / event / plan / anniversary / transaction / account / budget / subscription / file / tag / category 等 |
| `rev` | 否 | 服务端维护的记录版本号，每次接受修改 +1 |
| `seq` | 否 | 用户级单调递增序号，用于增量拉取 |
| `key_version` | 否 | 加密密钥版本 |
| `nonce` | — | 加密 nonce |
| `ciphertext` | — | 密文，包含全部业务字段与客户端时间戳 |
| `deleted` | 否 | 墓碑标记，删除时可清空 ciphertext |
| `updated_by_device` | 否 | 最后修改设备 ID |
| `server_updated_at` | 否 | 服务端时间 |

服务端可见元数据严格限制在必要字段内。提醒时间等必须由服务端知晓的字段，应放入独立最小化元数据结构，不含标题和内容。

### 6.2 业务字段（位于密文 JSON 内，版本化）

- `note`：title、body（Markdown）、tags、folder_id、pinned、todo items、file_refs、created_at、updated_at。
- `vault_item`：category（website/email/server/software/card/secure_note/custom）、name、fields[]（key、value、is_secret）、url、totp_secret（后置）、icon、favorite、password_history[]。
- `event`：title、start、end、all_day、location、notes、rrule、reminders、status、plan_id、file_refs。
- `plan`（行程）：title、start_date、end_date、destination（可选）、summary、status、file_refs；子事件通过 event.plan_id 关联。
- `anniversary`（纪念日）：title、date、calendar_type（首版 Gregorian）、repeat_rule（不重复/每年）、category（生日/周年/个人/项目/自定义）、description、cover_file_ref、reminders、show_countdown、created_at、updated_at。日期和描述均放在密文内。
- `transaction`：type（expense/income/transfer）、amount（整数最小货币单位）、currency、account_id、category_id、note、occurred_at、file_refs、subscription_id。
- `account / category / budget / subscription`：账户、分类、预算、订阅；subscription 含名称、金额、币种、周期、下次扣费日、提醒提前量，可在客户端生成对应 event。
- `file`：name、mime、size、blob_ids、file_key、chunk_size、created_at。

### 6.3 关联关系

- 同一文件只创建一条 file 记录，可被多个业务对象引用。
- 关联关系放在加密业务字段中，例如 `file_refs`、`plan_id`、`subscription_id`，服务端不需要知道具体业务关联。
- 文件删除前检查客户端已知引用；删除文件应采用回收站或延迟清理，避免误删仍被引用的附件。

### 6.4 服务端逻辑数据实体

至少需要以下逻辑实体，具体表结构由最终存储方案决定：

- users
- devices
- sessions（refresh token 哈希）
- key_material（salt、KDF 参数、认证哈希、包裹后的主密钥）
- pairing_sessions
- records（密文记录及版本、序号；anniversary 作为一种记录类型）
- sync_ops（幂等操作记录）
- blobs（文件元数据、分块状态）
- reminders（提醒元数据；首版实际通知由客户端本地调度）
- audit_logs
- push_tokens
- backup_jobs / backup_manifests（备份任务与清单）

单条加密记录建议设置 1 MB 上限；大附件必须走 Blob 分块流程。

---

## 7. 数据同步协议

### 7.1 基本原则

- 每个用户维护单调递增的 `seq`。
- 服务端在事务中分配序号，确保游标顺序稳定。
- 不使用“最后修改时间获胜”。
- 所有推送请求必须幂等。
- 服务端必须检测版本冲突，不得静默覆盖。

### 7.2 拉取

`GET /api/v1/sync/changes?cursor=N&limit=500`

返回：`seq > N` 的记录、`next_cursor`、`has_more`。

首次同步 cursor=0。客户端必须分页拉取，应用成功后才推进本地 cursor。

### 7.3 推送

`POST /api/v1/sync/push`

请求结构示例：

```json
{
  "op_id": "uuid",
  "device_id": "uuid",
  "changes": [
    {
      "id": "uuid",
      "type": "note",
      "base_rev": 3,
      "key_version": 1,
      "nonce": "base64url",
      "ciphertext": "base64url",
      "deleted": false
    }
  ]
}
```

- `op_id` 为幂等键；重复提交返回首次处理结果。
- 每条记录：若 `base_rev` 等于服务端当前 `rev`，则接受并递增 rev、分配 seq；新建记录要求 ID 不存在。
- 若版本不匹配，返回 conflict 和服务端当前版本，不覆盖。
- 客户端收到确认后更新本地 rev，再拉取增量变更。

### 7.4 墓碑与游标过期

- 删除采用 `deleted=true` 墓碑。
- 墓碑至少保留 180 天，具体清理策略需考虑长期离线设备。
- 若客户端 cursor 早于已清理范围，返回 `resync_required`，客户端执行全量同步。

### 7.5 客户端同步流程

本地写入 → 写入 outbox → 网络可用时批量推送 → 收到确认后更新 rev → 拉取增量 → 解密并应用 → 推进 cursor。

采用指数退避重试。启动、前台恢复、收到静默推送、手动下拉时可触发同步。同步失败不得阻塞本地读写。

### 7.6 冲突策略

- 便签：保留两份，将本地版本另存为冲突副本并提示合并。
- 日程：展示本地与远程版本，由用户选择或手动合并。
- 记账：交易优先设计为独立记录；冲突时保留本地副本，避免静默丢账。
- 密码库：禁止静默覆盖；冲突时保留两个版本并提示。密码字段变更可写入 password_history。
- 行程：行程计划与子事件分别进行版本检查；父级日期变更不得静默覆盖子事件，冲突时展示受影响的日期和事件。
- 纪念日：按记录版本检测冲突；保留双方版本或提供字段级合并，不得因重复规则计算覆盖原始日期。
- 其他记录：必须明确每种类型的冲突策略，不允许默认使用最后修改时间覆盖。

---

## 8. 文件与 Blob 管理

### 8.1 客户端处理流程

选择文件 → 校验类型与大小 → 图片按需压缩并生成缩略图 → 生成随机 FileKey → 分块 → 每块独立加密 → 上传 → 完成校验 → 创建 file 记录并同步。

- 图片压缩和缩略图生成在客户端完成。
- 缩略图同样需要加密，不得以明文缩略图泄露内容。
- 文件名、MIME、尺寸等元数据是否加密应在威胁模型中明确；默认尽量减少服务端可见信息。
- 每个文件使用独立 FileKey，FileKey 通过用户文件密钥体系包裹。
- 按 1–4 MB 分块，块序号纳入 AAD。
- 支持断点续传和幂等重试。

### 8.2 文件接口逻辑

- `POST /api/v1/blobs`：声明 blob_id、总大小、块数，返回上传会话。
- `PUT /api/v1/blobs/{id}/chunks/{n}`：上传分块，支持幂等与断点续传。
- `POST /api/v1/blobs/{id}/complete`：提交整体 SHA-256，服务端校验后标记可用。
- `GET /api/v1/blobs/{id}`：下载密文，支持 Range。
- `DELETE /api/v1/blobs/{id}`：删除或进入延迟清理状态。

### 8.3 文件规则

- 不做跨用户去重。
- 客户端按需下载原图；列表优先下载加密缩略图。
- 未被 file 记录引用的孤儿 Blob 由客户端确认清理；服务端可清理超过 30 天未 complete 的上传会话。
- 单文件上限默认 200 MB，可配置。
- 文件完整性必须通过哈希校验。
- 文件元数据与 Blob 备份必须能够配对恢复。

---

## 9. API 规范

### 9.1 通用规则

- API 前缀：`/api/v1`。
- 请求与响应以 JSON 为主；二进制文件通过 Blob 接口传输。
- 时间统一 RFC 3339 UTC。
- 二进制字段使用 Base64URL。
- 统一错误格式：`{ "error": { "code": "...", "message": "...", "request_id": "..." } }`。
- 每个响应携带 `X-Request-ID`。
- 所有用户数据接口必须校验用户身份和资源归属。
- 敏感数据不得写入日志。

### 9.2 认证

- 短期 access token（建议约 15 分钟）。
- 可轮换 refresh token，绑定设备。
- refresh token 使用后轮换；检测到复用时按安全策略撤销相关 token 链。
- 登录、恢复、配对接口按 IP 与账号维度限流。
- 具体 token 格式和签名实现由后端方案确定，但客户端 API 契约保持稳定。

### 9.3 接口分组

| 分组 | 主要接口 |
|---|---|
| auth | register、login/params、login、refresh、logout、password/change、recovery/start、recovery/finish、email/verify |
| devices | 列表、详情、撤销、更新名称 |
| pairing | 创建会话、读取会话、上传封装密钥、取回封装密钥 |
| sync | changes、push |
| blobs | 创建上传会话、上传分块、完成上传、下载、删除 |
| keys | 密钥元数据读取、更新、轮换状态 |
| backup | 创建备份、查询状态、下载、恢复校验 |
| push | 注册和撤销设备推送令牌 |
| ai | 可选 POST /ai/proxy |
| system | health、version |

---

## 10. 客户端功能与界面

### 10.1 首页 Dashboard

- 问候与日期。
- 今日日程（最近 2 条）。
- 今日待办。
- 最近/即将到来的纪念日（可配置显示）。
- 最近便签。
- 本月支出概览。
- 密码库入口（仅显示数量或分类，不展示敏感内容）。
- 最近文件。
- 统一快速新增：便签、日程、记账、账号、上传文件。
- 所有可从本地数据推导的统计优先在客户端计算。

### 10.2 便签 Notes

- 列表、置顶、标签筛选、分类。
- 搜索。
- 使用一个连续的原生编辑区，文字、待办 checkbox、图片按光标位置混排，不拆成独立卡片。
- 基础富文本格式（标题、正文、粗体、斜体），统一选择、复制粘贴与撤销 / 重做。
- 当前使用 UIKit UITextView / TextKit 封装为 SwiftUI 组件；有序 `rich_content` 为编辑来源，`body` / `todos` / `file_refs` 为搜索、首页和文件管理保留投影。旧版正文按原始文本保留，Markdown 解析及导入导出另行实现。
- 待办 checkbox。
- 图片与附件。
- 自动保存。
- 快速记录（无标题直接写）。
- 收藏置顶。
- 回收站（默认 30 天）。
- 历史版本查看与恢复。

### 10.3 密码库 Vault

- 分类入口：全部、账号、卡片、其他。
- 条目列表：可按策略显示用户名，密码默认掩码。
- 详情页、自定义字段。
- 密码生成器。
- 密码强度与重复检测。
- 收藏。
- 复制后剪贴板定时清理（默认 60 秒，可配置）。
- 密码库进入时需要 Face ID 或设备认证。
- 后台超过设定时间自动锁定。
- 任务切换界面遮罩，降低截图泄露风险。
- TOTP 后置。

#### 自动填充扩展（可选，受签名能力限制）

- 若当前签名包含 Credential Provider 所需 Entitlement，开发 iOS Credential Provider Extension，在 Safari 和其他支持的 App 中按域名匹配。
- 经 Face ID 确认后填充。
- 主 App 与扩展通过经验证可用的 App Group / Keychain Access Group 访问必要的密钥与本地加密库。
- 扩展只做必要的读取和匹配，不做同步。
- 通行密钥 Passkey 后置。
- 必须先检查万能签实际 IPA 的签名权限，再决定是否实施；真实 iPhone 验收通过后才能标记为支持。若权限不可用，密码库仍须支持 App 内搜索、查看和复制。App Preview 仅用于交互检查，此扩展以最终签名后的真机行为验收。

#### 导入与泄露检查

- 支持 Chrome、Apple 密码、1Password、Bitwarden 导出的 CSV；导入前预览并提示重复条目。
- 导入完成后提醒用户安全删除明文 CSV。
- 泄露检查可选使用 HIBP k-anonymity 接口，仅发送哈希前 5 位，默认关闭。
- 网站图标由客户端直接访问目标网站 favicon，缩小后写入条目密文；服务端不代理、不接触域名。抓取失败使用首字母占位图；设置中可关闭自动抓取。

### 10.4 时间管理 Calendar（日历、日程、行程、纪念日）

时间管理是一个主模块，内部包含「日历」「行程」「纪念日」三个子区域。三者共享日期显示、提醒、搜索和附件能力，但必须保留独立的数据类型。

#### 10.4.1 日历与普通日程

- 月视图、周视图、日视图和按时间排序的 Agenda 时间线。
- 在同一日历中展示普通事件、待办截止日期、行程区间和纪念日标记；使用不同颜色/图标区分类型。
- 创建、编辑、删除事件；支持全天事件、开始/结束时间、地点、备注、附件和状态。
- 重复规则：不重复、每天、每周、每月、每年及自定义规则；编辑单次事件或整个重复系列时必须明确作用范围。
- 提醒支持多个提前量；首版以本地通知为主，同步到新设备后由客户端重新调度。
- 待办可设置截止日期、优先级、完成状态；待办与普通日程可以在日历中统一查看，但数据类型应可区分。
- 提供「今日」「未来 7 天」「即将到来」快捷视图。

#### 10.4.2 行程 Trips / Plans

行程用于管理旅行、出差、活动周等跨日计划，是一个父级计划对象，可包含多个普通日程/子事件。

- 行程标题、开始日期、结束日期、目的地（可选）、摘要、封面（可选）、状态。
- 子事件包含日期、时间、地点、备注、提醒和附件。
- 支持按天分组显示行程时间线。
- 支持关联便签、文件、账单和密码库条目（例如酒店/交通账号；关联只在客户端解密后展示）。
- 行程总览显示日期范围、目的地、子事件数量和附件数量。
- 父级日期范围调整时，必须提示子事件是否超出新范围，不得自动静默删除或移动子事件。
- 支持行程归档、取消和复制为新行程。

#### 10.4.3 纪念日 Anniversaries

纪念日是独立数据类型，不应仅作为普通日程的全天事件处理。首版支持公历日期；农历及复杂历法作为后续可选增强，避免首版引入不必要的日期换算复杂度。日期存储必须区分「纯日期」与「带时区的时间点」：生日/纪念日使用纯日期，不得因 UTC 转换在不同时区显示到前一天或后一天；普通日程的时间点需保存时区语义。

支持类型：

- 生日：本人、家人、朋友等。
- 周年纪念：相识、结婚、恋爱、合作等。
- 个人纪念：毕业、入职、搬家、重要经历。
- 项目纪念：网站上线、项目成立、重要版本发布。
- 自定义纪念日。

每条纪念日包含：名称、原始日期、是否每年重复、类别、备注、封面/关联图片、提醒规则、是否显示倒计时。

展示与计算：

- 对未来日期显示「还有 N 天」。
- 对过去日期显示「已经 N 天」。
- 对每年重复的纪念日，计算下一次发生日期及距离天数。
- 在周年当天显示第 N 周年；对于非重复纪念日，显示从原始日期累计经过的天数。
- 处理闰年日期（例如 2 月 29 日）时必须定义并测试非闰年的周年落点策略，由用户设置或采用明确默认规则，不得依赖系统隐式行为。
- 支持提前提醒、当天提醒和关闭提醒。
- 可关联便签、图片和文件。

#### 10.4.4 与 iPhone 系统日历的联动

- APP 内部日历是本产品数据的主要来源。
- 提供用户主动触发的「添加到 Apple Calendar」功能；首版优先支持单向写入 APP 创建的事件。
- 可选提供从 Apple Calendar 导入事件，但必须由用户选择日历或事件范围。
- 不默认开启双向自动同步，避免重复事件、删除传播和冲突难以解释。
- 记录系统日历 event identifier 与内部记录 ID 的映射；映射属于设备本地数据，必要时可同步不透明映射标识，但不得泄露事件正文。
- 将 E2EE 事件写入 Apple Calendar 会在 APP 加密边界之外生成一份系统日历数据。写入前必须明确告知用户，并允许用户只保留在 APP 内。
- 系统日历权限按需申请；若用户拒绝授权，APP 内日历、行程和纪念日仍须完整可用。

#### 10.4.5 提醒规则

- 日程、行程子事件、纪念日和待办均可独立设置提醒。
- 首版使用本地通知调度；设备重装或重新登录后根据已同步的加密数据重新建立提醒。
- 本地通知不依赖 APNs。跨设备远程推送属于后续能力，受签名环境和 APNs Entitlement 影响。
- 通知默认使用隐私友好文案（例如「你有一项日程提醒」）；用户可选择是否在锁屏显示具体标题。
- 通知权限未授权时，APP 内仍显示提醒状态，并提示用户前往系统设置开启。

#### 10.4.6 时间管理验收要点

- 月/周/日视图切换正确，跨月、跨年和时区变化显示正确。
- 重复事件生成、单次修改、系列修改和删除范围正确。
- 行程父级与子事件关系稳定，调整行程日期不会静默丢失子事件。
- 纪念日倒计时、已过去天数、每年重复、闰年策略计算正确。
- 同一日期可同时显示普通日程、行程和纪念日，不互相覆盖。
- 离线创建/修改后可同步；冲突时保留数据。
- 系统日历拒绝授权时，APP 内时间管理功能不受影响。
- 提醒时间与重复规则在 Windows 核心包测试；UserNotifications 调度和实际提醒到达在真实 iPhone 上验证。

### 10.5 记账 Finance

- 支出、收入、转账。
- 分类与账户。
- 预算。
- 日、周、月、年统计与趋势图。
- 周期账单。
- 小票和发票附件。
- 订阅管理：月/年汇总、下次扣费、到期提醒，并可生成日程。
- CSV 导出。
- 金额以最小货币单位整数存储，避免浮点精度问题。

### 10.6 文件 Files

- 图片、PDF、文本和常见附件列表。
- 最近使用、收藏、分类。
- 预览、下载、删除、恢复。
- 文件大小和存储用量。
- 统一附件选择器。
- 显示文件关联到哪些业务记录（关联信息由客户端解密后展示）。
- 文件重复引用不重复上传。

### 10.7 设置 Settings

- 账号与设备管理。
- 设备列表、撤销设备、扫码授权新设备。
- 修改密码。
- 查看或重新生成恢复密钥（需验证）。
- 自动锁定时间。
- 导出与加密备份。
- AI 开关与隐私说明。
- 存储用量。
- 系统集成设置：系统日历导入/导出、通知偏好、可用扩展能力状态。
- 主题设置：浅色、深色、跟随系统。
- 关于、版本与隐私说明。

### 10.8 本地搜索

- 全局搜索由客户端在本地解密数据上完成。
- 使用 SQLite FTS5 建立本地索引。
- 密码库只索引名称与网址，不索引密码字段、恢复码或其他 secret 字段。
- 索引文件随设备数据保护一同保护。

---

## 11. AI 功能规则

E2EE 与云端 AI 存在天然冲突，规则如下：

1. 优先使用设备端能力；本地摘要、分类、嵌入向量优先在设备完成，向量索引默认不上传。
2. 云端 AI 必须由用户主动触发，发送前明确提示将发送的具体内容和范围。
3. 密码库内容永不进入任何 AI 请求；代码层面禁止 AI 上下文构建函数接受 `vault_item` 类型。
4. 日程、记账是否开放给 AI 由设置控制，默认关闭。
5. AI 代理只校验 token、限流、保管上游 API Key 并流式转发；不得记录请求和响应正文，仅记录必要用量计数。
6. 首批场景：便签整理、每日安排、便签摘要与改写、自然语言快速记账与建日程、当前选中范围内的便签问答。
7. AI 只输出建议，不直接写入业务数据。返回结构化 JSON，由客户端校验并预览，用户确认后才写入。
8. 用户拒绝确认时不得产生任何写入；AI 返回非法 JSON 时提示重试，不得损坏本地数据。
9. 发送前展示具体发送范围，不默认携带历史数据。
10. 设置中提供关闭云端 AI 或仅使用设备端模型的选项。

---

## 12. 备份、导出与运维

### 12.1 备份

- 业务记录密文与 Blob 文件必须成对备份。
- 至少保留一份独立于主服务商的异地加密备份。
- 备份清单包含记录范围、文件清单、版本、校验值和创建时间等必要元数据。
- 提供恢复流程和恢复校验工具。
- 定期执行恢复演练；只检查“备份任务成功”不够，必须实际抽样恢复。
- 备份任务失败必须产生告警。
- 备份介质不得包含明文主密钥或明文业务内容。

### 12.2 用户导出

- 全量加密备份包：包含所有记录密文、文件、元数据和必要密钥包裹材料；可通过恢复密钥或独立口令恢复。
- 明文导出：便签 Markdown / JSON、日程与纪念日 ICS（纪念日可导出为全天事件）、记账 CSV、密码库加密 JSON。
- 密码库导出前二次确认，默认加密。
- 必须能够从导出包恢复到全新设备；跨服务商迁移不得依赖原服务商专有接口。

### 12.3 运维

- 配置通过环境变量或独立配置文件管理。
- 日志仅记录 request_id、路径、状态码、耗时和必要错误码。
- 审计日志记录登录、设备变更、密码修改、恢复、导出等安全事件，不记录业务正文。
- 提供只读管理页或 CLI：健康状态、用户与设备数、存储用量、同步失败统计、备份任务状态。
- 数据库和对象存储实现可替换；部署拓扑由项目所有者另行确定。

---

## 13. 开发阶段与测试验收标准

### 13.1 测试原则

**Windows 检查纯 Swift 核心和 Go；Codemagic 编译完整 iOS App 并提供 Preview；阶段性未签名 IPA 经万能签后在真机验收。**

- 业务模型、金额与日期计算、导入导出协议、同步状态机等放入 NookCore，在本机快速测试。
- SwiftUI 页面、iOS Repository 和系统适配代码由云端 Xcode 实际编译；涉及这些代码的改动必须在该阶段交付前取得云端验证结果。
- UI 调整按页面或小批变更触发模拟器构建，用 App Preview 检查真实界面与交互；优先验收首页和统一组件，再展开其他页面。
- 真机 IPA 按功能里程碑集中生成和安装，减少反复签名安装；发现影响使用或安全的问题时修复并补测。
- App Preview 中的 `localhost` 不指向 Windows 电脑，真机也不能直接访问电脑的 `localhost`。联调地址通过环境配置注入，按实际网络条件提供可达的开发服务；首版本地 MVP 不依赖后端。
- 日常链路采用 Codemagic；GitHub Actions 不作为必需的另一套构建平台。仓库托管与云端编译是不同职责。

### 13.2 Windows 本地基础检查

以下客户端命令在 P0 建立 `packages/NookCore/Package.swift` 后执行。纯 Swift 检查只覆盖核心包，iOS App 的检查见第 13.3 节。

```powershell
swift --version
swift package --package-path packages/NookCore resolve
swift build --package-path packages/NookCore
swift test --package-path packages/NookCore
```

Go 服务端：

```powershell
Push-Location server
try {
    go test ./...
    go vet ./...
} finally {
    Pop-Location
}
```

P0 将本地命令封装为 `scripts/test-local.ps1`，确保任一步失败时脚本返回失败。Swift 格式检查工具随工具链固定后写入脚本，不以 Go 测试代替客户端检查。Apple 框架与实际 GRDB 测试放入 iOS 测试 Target，不为 Windows 测试加入空实现冒充功能完成。

### 13.3 Codemagic 云端编译、Preview 与未签名 IPA

P0 建立 `codemagic.yaml` 与构建脚本。以下是目标工程建立后的 macOS 构建命令，不在 Windows 执行；Xcode / Swift、XcodeGen 与依赖版本固定后，通过 Codemagic 构建 API 从命令行触发。API Token 使用凭据存储或环境变量，不提交到仓库。

**工作流 A：iOS 模拟器构建与 App Preview**

```bash
xcodegen generate --spec ios/project.yml
xcodebuild build \
  -project ios/Nook.xcodeproj \
  -scheme Nook \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ios-simulator \
  CODE_SIGNING_ALLOWED=NO
```

- 将 `build/ios-simulator/Build/Products/Debug-iphonesimulator/Nook.app` 列为构建产物，按 Codemagic 的 App Preview 入口启动；可同时保留下载用压缩包。
- 云端选择可用的 iPhone 模拟器运行 `xcodebuild test`，执行数据层、交互及截图测试，并保存日志与测试结果。
- Preview 用于检查布局、导航、输入、键盘、空状态和数据持久化；Face ID 硬件、实际通知到达及重签后的权限行为在真机验收。

**工作流 B：iPhone 真机未签名 IPA**

```bash
xcodegen generate --spec ios/project.yml
xcodebuild build \
  -project ios/Nook.xcodeproj \
  -scheme Nook \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/ios-device \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

mkdir -p build/unsigned/Payload
cp -R build/ios-device/Build/Products/Release-iphoneos/Nook.app \
  build/unsigned/Payload/
(cd build/unsigned && zip -qry ../Nook-unsigned.ipa Payload)
```

- 收集 `build/Nook-unsigned.ipa`，用户下载后通过万能签重新签名并安装到自己的 iPhone；不在 CI 配置签名证书或 Provisioning Profile，也不把 App Store / TestFlight 作为当前测试前置条件。
- 模拟器 `.app` 和真机 IPA 分别构建；不能把模拟器产物重新压缩后当作真机包。
- 若包含 Extension、嵌入框架或动态库，按完整 App Bundle 保留文件，并在最终重签与真机安装后验证其可用性。
- P0 将上述操作封装为 `scripts/build-ios-simulator.sh` 与 `scripts/build-ios-device-unsigned.sh`；确认产物类型、目录和启动结果后，再标记工作流可用。

平台依据：[原生 iOS 构建](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/)、[未签名模拟器构建](https://docs.codemagic.io/yaml-code-signing/ios-simulator-builds/)、[App Preview](https://docs.codemagic.io/yaml-distributing/app-preview/)、[构建 API](https://docs.codemagic.io/rest-api/builds/)。

### 13.4 测试分层

| 测试层 | 运行位置 | 主要内容 |
|---|---|---|
| 核心包编译与单元测试 | Windows / 云端 | 数据模型、业务规则、协议、同步状态机 |
| Go 检查与服务测试 | Windows / CI | go test、go vet、API 契约、权限与幂等 |
| 完整 App 编译 | Codemagic macOS + Xcode | SwiftUI、Apple 框架、GRDB、资源与依赖集成 |
| iOS 数据层与集成测试 | 云端 iOS Simulator | SQLite 迁移、持久化、加密实现、文件与同步 |
| UI 自动化与截图 | 云端 iOS Simulator | XCUITest、组件状态、关键交互与视觉回归 |
| 页面人工检查 | Codemagic App Preview | 对照参考图、导航、表单、主题、键盘和安全区 |
| 双设备同步测试 | 两个 iOS 模拟器或测试设备 | 新设备同步、离线修改、冲突和设备撤销 |
| iOS 平台测试 | 最终重签后的真实 iPhone | Keychain、Face ID、文件保护、通知及可用扩展 |
| 发布前测试 | 真实 iPhone | 安装、升级、恢复、离线、后台锁定、耗电和稳定性 |

### 13.5 加密协议测试

`/testvectors` 保存固定测试向量，至少覆盖：

- Argon2id 输入、salt、参数与输出。
- HKDF 输入、salt、info 与输出。
- XChaCha20-Poly1305 加密、解密、错误密钥和篡改检测。
- AAD 与 record_id / type / key_version 绑定。
- X25519 设备配对与密钥封装。
- 文件分块加密、块序号绑定、乱序与缺块检测。
- 恢复密钥包裹和解包。
- 密钥版本升级和旧版本兼容。

客户端与服务端必须通过同一组向量。生产 nonce 必须随机生成；测试固定 nonce 只用于确定性测试。

### 13.5.1 首版范围与上线顺序

完整规格按阶段建设，不要求首版一次包含全部模块。按以下门槛交付：

1. **本地 MVP**：先交付 SwiftUI iOS 本地版，完成便签、基础日程和基础收支记录的核心操作，保证主要页面符合参考图、日常操作顺手，并提供本地数据备份/导出。通过 Preview 检查交互，再以未签名 IPA + 万能签完成真机验证。此版本不提供账号和云同步；密码库、AI 与高级自动化先不进入首版。
2. **Go 服务端与加密同步**：本地 MVP 稳定后再开放账号和跨设备同步，对应 P6。业务数据上传前，密钥派生、设备配对、恢复、轮换和备份协议必须完成审查，客户端与 Go 服务端通过同一套测试向量；先以便签验证完整同步闭环，再逐步开放日程和记账同步。未通过审查前，云端不得接收业务明文。
3. **密码库**：P3 为独立的后置安全阶段，可在日程和记账核心模块之后实施，不阻塞本地 MVP。在威胁模型、密钥存储、自动锁定、剪贴板清理和 iOS Keychain / 生物识别真机验证完成后再交付；普通记录同步已可用，不代表密码库通过安全验收。
4. **AI 与其他可选能力**：按本规格书的隐私规则和各自验收条件后置，不阻塞本地 MVP。

本地 MVP 是可先行使用的产品版本；它不代表云同步或密码库已达到发布条件。

### 13.6 P0：Swift 工程骨架与云端验证链路

内容：
- 按第 2.5 节建立原生工程目录；旧原型在 archive 下保留作迁移参考。
- SwiftUI App、统一 Design Token 与首页 / 五个主入口骨架。
- NookCore Swift Package、业务协议与基础单元测试。
- XcodeGen 工程定义、SPM 依赖与版本记录。
- Windows 本地检查脚本和开发说明。
- Codemagic 模拟器 Preview、未签名真机 IPA 两个独立工作流，以及命令行调用构建 API 的说明。
- API 契约与测试向量目录骨架；此阶段不实现账号或云同步。

验收：
1. Windows 上 `swift build`、`swift test` 可验证 NookCore，Go 服务端测试通过。
2. Codemagic 可从工程定义生成 Xcode 工程，完整 SwiftUI App 编译成功。
3. 模拟器 `Nook.app` 在 App Preview 成功启动；首页实际截图与参考图对照，五个主入口和主题 Token 正常。
4. 云端生成 `Nook-unsigned.ipa`；用户经万能签重签后可在自己的 iPhone 安装并启动。
5. 构建日志、测试结果与产物可获取；真机 IPA 以关闭代码签名的参数生成，交由用户的万能签完成重签。
6. 分别记录 Windows 核心包测试、云端 App 编译、Preview 和真机验证的结果；尚未执行的项保留待验收状态。

### 13.7 P1：本地数据层与导出

内容：建立 NookCore 数据模型与 Repository 协议，在 iOS 数据层实现 GRDB / SQLite 持久化、迁移和本地导出；为各功能模块提供离线优先的数据基础，此阶段不要求账号或云端服务。

验收：
1. 业务数据写入本地后，重启应用仍可读取。
2. 数据库 schema 升级有迁移并覆盖测试。
3. 本地数据可导出并在干净安装中恢复。
4. 无网络时核心读写流程可用。

### 13.8 P2：便签与文件

内容：便签全功能、本地附件管理与预览、回收站、本地 FTS 搜索。云端 Blob 上传下载在 P6 实施。

验收：
1. 便签增删改查、标签、置顶、自动保存正常。
2. 图片和附件在本地受应用数据保护，并可正常预览。
3. 同一文件可被多个业务记录引用。
4. 删除引用不应误删仍在使用的文件。
5. 本地搜索只索引允许索引的已解密字段。
6. 在 iOS 模拟器 / App Preview 完成离线创建、读取和附件预览，并在真机确认文件访问和持久化。

### 13.9 P3：密码库（后置安全阶段）

内容：条目管理、生成器、强度和重复检测、Face ID、自动锁定、剪贴板清理。

验收：
1. 未解锁时无法读取密码条目。
2. 后台超过设定时间自动锁定。
3. 密码复制后按设定时间清理剪贴板。
4. AI 路径无法引用密码库。
5. Windows 测试锁定状态机、密码生成规则和 AI 访问限制；云端测试 iOS 集成与界面交互。
6. Keychain 生物识别访问控制、Face ID、后台锁定和任务切换遮罩使用最终重签后的真机 App 验收。
7. 自动填充扩展属于可选能力：仅在万能签实际提供所需 Entitlement 且扩展可正确签名时实施；否则明确标记为暂缓，不影响密码库核心功能。

自动填充扩展启用后的专项验收：
- Safari 登录页可调起密码库，经 Face ID 后填充匹配域名的账号。
- Chrome / Bitwarden 等 CSV 导入后条目和字段正确，重复条目有提示。
- 抓取 favicon 时仅客户端访问目标网站，服务端日志中没有域名。
- 锁定状态下扩展不返回任何凭据。

### 13.10 P4：时间管理（日历、日程、行程、纪念日）

内容：日历三视图、普通事件、待办截止日期、重复事件、行程父子结构、纪念日管理与倒计时、本地通知、可选系统日历导入/导出。跨设备同步在 P6 实施。

验收：
1. 月视图、周视图、日视图和 Agenda 时间线显示正确。
2. 全天事件、跨天事件、时区变化和重复规则正确。
3. 编辑重复事件时，单次修改与整个系列修改的作用范围正确。
4. 行程父级和子事件关系正确；缩短或延长行程时，对超出范围的子事件给出明确处理选项，不静默删除。
5. 纪念日支持生日、周年、个人和项目类型；过去日期、未来日期、每年重复及闰年策略计算正确。
6. 普通日程、行程区间和纪念日可以在同一日历日期中同时显示。
7. 离线创建和修改后数据不丢失，重启应用后仍可读取。
8. Windows 核心包覆盖日期、时区、重复规则和纪念日计算；App Preview 检查日历视图、行程与纪念日交互。
9. iOS 系统日历授权、EventKit 读写和本地通知必须在真实 iPhone 上验证；拒绝授权时 APP 内功能仍完整可用。
10. 将加密事件导出到 Apple Calendar 前展示隐私提示；用户取消时不得写入系统日历。

### 13.11 P5：记账与统计

验收：
- 收入、支出、转账计算正确。
- 金额使用整数最小货币单位，无浮点精度错误。
- 分类、账户、预算、图表正确。
- 周期账单与订阅提醒正确。
- 订阅可生成关联日程。
- CSV 导出数据完整。
- 统计在本地解密数据上计算，不将明文金额上传给服务端进行统计。

### 13.12 P6：Go 服务端、加密同步与长期维护

内容：Go 服务端与存储抽象、认证和设备管理、密钥/恢复协议、通用记录与文件同步、冲突处理、加密备份包与导入；完成协议审查和共享测试向量后，先打通便签同步，再逐步开放日程和记账同步。另包括 AI、明文导出、历史版本、云端提醒（可选）、TOTP、安全审计、密钥轮换工具，以及通过签名权限验证后可选启用的 Widget、Share Extension、密码自动填充、APNs 和 Live Activities。

验收：
- Go 服务端与客户端通过同一套加密协议测试向量。
- 服务端存储中不存在明文业务内容、主密钥或可直接解密用户数据的材料。
- 先完成便签的注册、设备授权、双设备同步、离线重连、冲突和幂等验收，再开放其他业务类型同步。
- 使用密码或恢复密钥在新设备恢复；撤销设备后，其后续请求被拒绝。
- cursor 过期时触发全量同步；文件断网重连可续传且不损坏。
- 拒绝 AI 建议时不产生写入。
- AI 非法 JSON 不损坏本地数据。
- 全量加密备份可以在干净环境恢复。
- 便签 Markdown、日程/纪念日 ICS、记账 CSV 导出正确。
- 密码库默认加密导出并二次确认。
- 备份恢复演练通过。
- 密钥轮换后新旧数据可按版本正确解密。

### 13.13 iOS 系统能力专项验证（按签名权限决定是否实施）

首版基础能力优先验证：

- Face ID / Touch ID。
- 本 App Keychain 存储与生物识别访问控制。
- 本地通知。
- 相机、照片选择器和文件选择器。
- EventKit 系统日历读写（用户授权后）。
- 剪贴板与密码复制后的清理策略。

扩展能力先检查万能签实际提供的签名权限，再决定是否开发：

- WidgetKit 小组件（需要对应 Extension 签名；共享数据时还需要 App Groups）。
- Share Extension。
- Credential Provider 密码自动填充。
- APNs 远程推送。
- Live Activities / 灵动岛。
- App Groups / Shared Keychain。

验收规则：

1. 对实际签名 IPA 检查主 App 与每个 Extension 的签名 Entitlements 和 Provisioning Profile。
2. 不能仅凭 Xcode 工程已配置、编译成功或模拟器显示正常，就判定万能签环境可用。
3. 必须使用当前万能签兑换码签名后的 IPA 安装到真实 iPhone，逐项验证安装、启动、系统设置入口、授权流程和实际功能。
4. 若某项 entitlement 缺失，该项标记为「当前签名不可用/待更换签名方式」，不得阻塞基础 APP 发布。
5. 本地通知与 APNs 远程推送分别验收；本地通知可用不代表 APNs 可用。
6. Live Activities 的本地更新与远程推送更新分别验收；不能把其中一种成功等同于全部能力可用。

### 13.14 iOS 专项验证安排

当前开发环境为 Windows，按以下节奏使用云端构建与真机：

1. 日常逻辑修改先执行 Windows 核心包和 Go 测试，尽早发现可在本机定位的问题。
2. 首页与统一组件先触发模拟器构建并用 App Preview 对照参考图；视觉方向确认后逐页扩展。
3. iOS 页面、数据层和系统适配修改按小批变更执行云端编译与相应测试，不把完整 App 的错误留到最后一次打包。
4. P0 安装冒烟、本地 MVP、通知 / 文件、密码库安全、同步恢复及正式自用等里程碑集中生成真机 IPA；根据实际启用的功能选择验收内容。
5. 首版本地 MVP 验证安装、离线 CRUD、重启持久化、导出恢复与文件访问；开放密码库后增加 Face ID、后台锁定，开放账号与同步后增加登录、设备授权、冲突和恢复。
6. Preview 不替代最终签名后的真机验证；无需每次代码修改都签名安装 IPA。

---

## 14. 威胁模型与安全检查清单

- **服务器被完全攻破**：攻击者仅获得密文和必要不透明元数据，无法解密；但可能看到记录数量、类型、大小、时间等元数据，需在隐私说明中告知。
- **数据库被拖库后离线爆破**：认证材料必须使用经过审查的密码派生和服务端验证方案；AuthKey 与 PasswordKek 必须进行密钥分离。
- **设备丢失**：系统数据保护、生物识别、远程撤销和可选密钥轮换。
- **中间人攻击**：强制 TLS；证书固定作为可选增强，必须考虑证书轮换和紧急回退机制。
- **重放与篡改**：幂等 op_id、AAD 绑定记录 ID 与类型、Blob 整体哈希校验。
- **用户丢失全部凭据**：不可恢复，注册和恢复流程明确告知。
- **恶意或越权文件访问**：每次上传、下载、删除都校验用户与文件归属；文件地址不能作为长期公开凭证。
- **日志泄露**：禁止记录密码、主密钥、恢复密钥、明文便签、账单详情和文件内容。

发布前检查：依赖漏洞扫描、日志脱敏检查、备份恢复演练、加密测试向量、越权访问测试、文件上传边界测试、隐私说明与 App Store 加密合规声明。

---

## 15. 暂不做（避免范围膨胀）

- 多用户共享与协作。
- 网页端。
- 服务端全文搜索。
- 跨用户文件去重。
- 高可用多主和复杂分布式架构。
- 实时协同编辑。
- Passkey 管理。
- TOTP（密码库首版后置）。
- 农历纪念日与复杂历法支持（首版先支持公历，后续按需求扩展）。
- 需要额外签名 Entitlement 的 iOS 扩展，在万能签实际权限验证前不作为首版硬性依赖。
- 复杂云端提醒。
- Android 客户端及正式发布；当前原生方案专注 iPhone，未来单独评估。

数据模型和同步协议应为后续扩展保留空间，但首版不得因此过度设计。

---

## 16. 交付给 Codex 的执行要求

1. 先阅读本规格书，整理实施计划和风险清单，不要立即一次性生成全部代码。
2. 首先完成 P0：Windows 核心包检查、Codemagic 完整 iOS 编译、App Preview 和未签名 IPA 真机安装链路。
3. 每阶段提交前输出：修改文件列表、实现内容、运行过的命令、测试结果、未完成事项和已知风险。
4. 不得声称某项测试通过，除非实际执行并得到成功结果。
5. Windows 可验证的核心逻辑先在本机测试；SwiftUI、GRDB 和 Apple 平台代码在阶段交付前取得云端实测结果。
6. 分别记录本地核心包测试、云端编译、Preview 和真机结果。iOS 专属功能未验收时标记“待真机验证”；依赖 Entitlement 的扩展使用当前万能签最终重签的 IPA 验证。
7. 所有协议和数据结构变更必须同步更新 docs 与 testvectors。
8. 对安全、加密、恢复和同步的破坏性变更，必须先解释迁移影响并获得项目所有者确认。
