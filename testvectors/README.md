# 测试向量

Swift 客户端（`packages/NookCore`）和 Go 服务端（`server/`）共用的已知答案测试（规格书 13.5）。现在只有目录约定，向量文件会在实现加密（P2）时补上。

## 规则

- 向量用成熟的参考实现生成（例如 libsodium），**不手写加密算法**，也不从自己的实现反推结果。
- 每个文件写明生成工具和版本。
- 两端的测试都读同一份文件，任何一端结果不同都算失败。
- 字节一律用无填充 Base64URL，和线上格式一致（见 `docs/api/README.md`）。

## 计划中的文件

| 文件 | 覆盖内容 |
|---|---|
| `crypto/argon2id.json` | 口令派生：参数、盐、输出 |
| `crypto/hkdf-sha256.json` | 子密钥派生 |
| `crypto/xchacha20poly1305.json` | 加解密，包括错误密钥和密文被篡改时必须失败 |
| `crypto/aad-binding.json` | AAD 绑定记录 ID、类型、版本：换了任意一项都必须解密失败 |
| `crypto/x25519.json` | 设备间密钥交换 |
| `files/chunked-encryption.json` | 文件分块加密、块顺序、截断检测 |
| `keys/recovery-key-wrap.json` | 恢复密钥包裹与解包 |
| `keys/key-version-upgrade.json` | 密钥版本升级后，旧记录仍可解密、新记录用新版本 |

## 文件格式

```json
{
  "description": "XChaCha20-Poly1305 known-answer tests",
  "generator": "libsodium 1.0.20",
  "cases": [
    {
      "name": "tampered ciphertext is rejected",
      "input": { "key": "…", "nonce": "…", "aad": "…", "ciphertext": "…" },
      "expected": { "error": "authentication_failed" }
    }
  ]
}
```
