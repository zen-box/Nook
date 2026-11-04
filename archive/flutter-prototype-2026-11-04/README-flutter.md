# Nook

Nook 是一个私密、离线优先的个人生活空间。当前仓库包含 Flutter 客户端和 Go 服务端骨架。

## 当前版本

- Flutter 本地 MVP：首页、便签、基础日程、收支记录、共享的本地存储。
- Go 服务端骨架：`/healthz` 健康端点，暂不接收业务数据。
- 密码库、账号、云同步和 AI 仍按规格书中的后置阶段实施。

## 本地运行

客户端：

```powershell
cd app
flutter pub get
flutter run
```

服务端：

```powershell
cd server
go run .
```

服务端启动后访问 `http://localhost:8080/healthz`。

## 检查与构建

```powershell
cd app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

开发顺序和安全边界见 `Personal-Hub-开发规格书-v2.md`。
