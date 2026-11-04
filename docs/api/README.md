# 当前数据协议入口

当前 iOS App 不连接 Nook Go 服务器。`server/` 只保留 `/healthz` 骨架；早期 `/api/v1` 与 `RecordEnvelope` 方案归档于 `archive/Go-API-约定-v3-2026-11-04.md`，不用于现有 S3 同步。

## S3 对象

在用户选择的前缀下保存：

| 路径 | 内容 |
|---|---|
| `library.json` | `nook.library` v1、资料库 UUID、根密钥的认证加密校验值；无明文根密钥 |
| `files/<随机 UUID>.sealed` | 按文件 ID 与资料库绑定的 AES-GCM 附件 |
| `snapshots/<随机 UUID>.sealed` | 按资料库与对象路径绑定的 AES-GCM 快照 |

请求使用 HTTPS、AWS SigV4；列举使用 ListObjectsV2 并处理 continuation token。新对象 PUT 使用 `If-None-Match: *`，不覆盖已存在资料库或历史。当前不依赖桶开启 Versioning；Nook 自己以新对象保留快照。

快照明文模型为 `SyncSnapshot`（`nook.snapshot` v1）：创建时间、`SyncDocument` 与附件描述。`SyncDocument`（`nook.sync` v1）包含资料库 UUID 与记录数组，每条记录可保留多个并发 `SyncVersion`：UUID、设备向量时钟、可空 payload（空表示墓碑）、毫秒编辑时间。合并按时钟因果关系，不能仅用设备时间判定覆盖。

普通记录键为 `<类型>/<UUID>`，另有 `vault/library`（密封密码库）与 `preferences/library`。记录 ID 校验使用真实 UUID；JSON 时间统一 RFC 3339 UTC 毫秒。CryptoKit 加密数据使用 Codable 的 Data 编码，不复用旧信封的 Base64URL 字段约定；恢复码单独采用 `NOOK1.` + Base64URL。

当前实现位置：

- `ios/Nook/Data/Sync/S3Client.swift`：签名、寻址、分页、网络上限。
- `ios/Nook/Data/Sync/SyncCrypto.swift`：根密钥、上下文派生与认证加密。
- `ios/Nook/Data/Sync/SyncCoordinator.swift`：附件 / 快照提交、冲突、历史。
- `packages/NookCore/Sources/NookCore/Sync/SyncDocument.swift`：因果与合并规则。
- `ios/Nook/Data/Sync/PortableDataset.swift`：严格模型校验与事务安装。

## 备份和设备迁移

完整备份文件为 `.nookbackup`，魔数 `NOOKBK01`；认证清单和每个附件独立加密分帧。局域网迁移使用版本化配对二维码、X25519 临时密钥、双端验证码与带方向 / 序号的加密帧，完成导入前不发送成功回执。

具体操作与失败恢复见 [同步与恢复](../sync-and-recovery.md)。这些协议仍需兼容演进，修改版本、加密上下文或编码必须同时更新读取兼容和测试；不能以重新建库处理现有数据。
