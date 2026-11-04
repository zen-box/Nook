# 本地密码库：格式与验收

当前实现位于 `ios/Nook/Data/Vault/`；GRDB 负责 SQLite 持久化，界面通过 `VaultStore` 读写。账号、卡片和自定义字段均存为加密记录。云端统一 MasterKey / HKDF / 恢复密钥 / 设备同步协议留在后续阶段，当前格式仅用于本机。

## 格式 v2

| 项目 | 当前值 |
|---|---|
| 密码库密钥 | 随机 32 字节；由 CryptoKit 的系统随机源生成 |
| 主密码编码 | 原始 UTF-8，不做 Unicode 归一化，保留嵌入的 NUL 字节 |
| 密码派生 | libsodium Argon2id v1.3，输出 32 字节；p=1，t=3，内存 64 MiB；随机盐 16 字节 |
| 加密 | libsodium XChaCha20-Poly1305 IETF，随机 nonce 24 字节，认证标签 16 字节 |
| 密文布局 | nonce（24 字节）＋密文＋标签（16 字节） |
| 条目 AAD | UTF-8 `nook\|<小写 UUID>\|vault\|v2`，绑定记录 ID、类型与格式版本 |
| 库密钥包裹 AAD | UTF-8 `nook.vault.key.v2` |
| 密钥校验 | 用库密钥加密 `nook.vault.key-check.v2`，AAD 为空；用于识别过期的设备密钥副本 |

`vault_key` 保存格式版本、盐、派生操作次数（`rounds`）、内存字节数（`memory_limit`）、加密包裹的库密钥和密钥校验值。主密码及派生密钥不写入数据库。

`vault_record` 的 ID、分类、格式版本及创建 / 更新时间是明文元数据，其他字段在密文内。解密后还检查 ID 和分类与数据库行一致；读取失败的条目保留在库中并显示失败数量。旧格式升级遇到任何无法解密的行时会中止，不覆盖原数据。

应用固定 swift-sodium 0.11.0，调用它提供的 Clibsodium C 接口；不自行实现密码算法。C 接口也避免对中文主密码进行错误的有符号字节转换。依赖源：

- [swift-sodium 0.11.0](https://github.com/jedisct1/swift-sodium/tree/0.11.0)
- [libsodium Argon2id](https://doc.libsodium.org/password_hashing/default_phf)
- [libsodium XChaCha20-Poly1305](https://doc.libsodium.org/secret-key_cryptography/aead/chacha20-poly1305/xchacha20-poly1305_construction)

## 升级、锁定和设备认证

此前开发版本 v1 使用 PBKDF2-HMAC-SHA256 / ChaCha20-Poly1305。现在只保留读取兼容：主密码验证后先解密全部旧记录，再将 v2 密文与新包裹密钥在同一事务内保存。升级失败保留旧数据；所有新写入使用 v2。

快捷解锁的库密钥副本位于 Keychain，访问控制为 `WhenUnlockedThisDeviceOnly` 加 `userPresence`，由系统要求 Face ID、Touch ID 或设备密码。按钮可用性只查询属性，不读取秘密；真正读取在后台任务中调用 Keychain，由其执行认证。旧版无访问控制的副本会删除，主密码成功解锁后可以重建受保护副本。

进入后台会清空库密钥、解密列表和编辑草稿；正在运行的解锁或修改密码任务通过操作序号失效，不能在后台锁定后重新打开密码库。非活跃时主界面和密码编辑弹层均显示隐私遮罩。Swift 值的释放不等于底层内存的可证明安全擦除。

秘密字段复制使用仅限本机、90 秒过期的剪贴板项。万能签重签后，如果 Keychain 项因签名 / 访问组变化不可用，应使用主密码解锁；Bundle ID 保持 `com.nook.personal`。卸载 App 会清除其数据库，JSON 备份不包含密码库，当前没有完整的密码库迁移 / 恢复包。

## 自动测试与真机验收

Windows 可运行 NookCore 的密码生成、模型和编码测试。`ios/NookTests` 的以下测试必须在 Codemagic `ios-tests` 工作流执行：

- SQLite 关闭连接后重新打开，便签、日程、行程、纪念日和账目仍可读取。
- 保存失败时保留旧照片和引用；保存成功后再清理原图与缩略图；行程关联删除失败时事务回滚。
- 密码库加密重开、错误主密码、修改主密码、重置、锁定后的删除 / 覆盖保护。
- v1 数据升级为 v2 后重开；损坏旧记录不会被覆盖。
- Argon2id 中文 / emoji / NUL 测试向量；XChaCha 固定密文；篡改、错误 AAD、未知版本和随机 nonce。

固定向量由 PyNaCl（调用 libsodium）独立生成，输入与期望值直接保存在 `VaultSafetyTests.swift`。Argon2id 测试采用 t=1、8 MiB 降低测试耗时，正式参数保持 t=3、64 MiB。

最新版本还需在自己的 iPhone 检查：

1. 创建普通记录与带照片便签，强制结束 App 后重开，数据和照片完整。
2. 创建密码库、保存账号、锁定，用正确 / 错误主密码解锁；更换主密码后旧密码失效。
3. 启用快捷解锁：查询按钮时不弹认证，点击时由系统认证；取消后仍锁定，主密码仍可用。
4. 在密码详情、编辑和修改主密码页面切到后台，应用切换缩略图被遮盖，回到 App 后密码库锁定。
5. 导出 / 恢复普通 JSON，确认替换提示和排除内容；设置定时日程，在通知授权后验证提醒。

旧提交 `8dd62d0` 的未签名 IPA 构建成功记录不能代替本次依赖与数据库版本的云端检查。
