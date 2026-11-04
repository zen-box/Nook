# API 约定

P0 阶段**不实现**账号和云同步（规格书 13.6），这里先把客户端与服务端都要遵守的格式固定下来。服务端代码在 `server/`，客户端的对应实现在 `packages/NookCore`。

## 通用规则

- 所有接口以 `/api/v1` 开头，请求和响应都是 UTF-8 JSON。
- 时间：RFC 3339，UTC，带毫秒，例如 `2026-11-03T16:00:00.250Z`。不带时间的日期写 `YYYY-MM-DD`。
- 二进制（nonce、密文等）：Base64URL，**不带** `=` 填充。
- 记录 ID：UUIDv7，线上一律用小写。
- 每个响应都带 `X-Request-ID` 头；客户端请求里带了就原样返回，没带就由服务端生成。

## 错误格式

```json
{
  "error": {
    "code": "record_conflict",
    "message": "The record was changed on another device.",
    "request_id": "0190a5b2-c3d4-7e5f-8a6b-1c2d3e4f5a6b"
  }
}
```

`code` 是给程序判断的固定字符串，`message` 只给人看，客户端不要解析它。

## 同步信封 `RecordEnvelope`

服务端只保存信封，看不到业务内容；业务字段（规格书 6.2）加密后放在 `ciphertext` 里。

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | UUIDv7，小写 |
| `type` | string | 见下方记录类型 |
| `rev` | integer | 客户端每次修改加 1 |
| `seq` | integer，可省略 | 服务端分配的全局顺序号 |
| `key_version` | integer | 加密这条记录用的密钥版本 |
| `nonce` | string | Base64URL |
| `ciphertext` | string | Base64URL |
| `deleted` | boolean | 删除标记（墓碑） |
| `updated_by_device` | string，可省略 | 最后修改的设备 ID |
| `server_updated_at` | string，可省略 | 服务端写入时间 |

记录类型：`note`、`vault_item`、`event`、`plan`、`anniversary`、`transaction`、`account`、`budget`、`subscription`、`file`、`tag`、`category`。

可省略的字段缺失或为 `null` 时都视为没有值；客户端编码时直接省略未设置的字段。下面这条示例与 `RecordEnvelopeTests` 的断言逐字一致（键名排序）：

```json
{"ciphertext":"AQIDBA","deleted":false,"id":"0190a5b2-c3d4-7e5f-8a6b-1c2d3e4f5a6b","key_version":1,"nonce":"-_8A","rev":3,"seq":42,"server_updated_at":"2026-11-03T16:00:00.250Z","type":"vault_item","updated_by_device":"0190a5b2-0000-7000-8000-00000000000d"}
```

## 健康检查

- 现在：`GET /healthz`（`server/main.go`）。
- 待做：规格书要求的 `GET /api/v1/system/health`，在开始做同步时补上，`/healthz` 保留给部署平台探活。

## 注意

App Preview 和真机里的 `localhost` 都不是你的 Windows 电脑。以后联调服务端时，要用局域网 IP 或公网地址。
