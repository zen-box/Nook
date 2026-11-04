# Nook Flutter 原型归档

归档日期：2026-11-04。客户端技术栈切换为 Swift / SwiftUI，后端继续使用 Go。

本目录保存切换前的 Flutter 客户端，以及改为 Swift 版规格前的两份文档快照。后续开发依据根目录的 [Swift / SwiftUI 版开发规格书](../../Personal-Hub-开发规格书-v2.md) 与 [README](../../README.md)；历史规格中的 Flutter / APK 要求仅供查阅。

## 归档内容

- [app/](app/)：原来的项目根目录 `app/`，保留全部源码、测试、依赖锁文件、平台工程、已有构建产物与生成缓存。
- [Flutter 版 v2 规格书](Personal-Hub-开发规格书-v2.md)：切换技术栈前的规格快照。
- [旧 README](README-flutter.md)：切换技术栈前的运行说明。
- Go 后端仍在项目根目录 `server/`，继续用于新方案。

## 查阅入口

- [客户端实现](app/lib/main.dart)：首页、便签、基础日程和收支记录。
- [组件测试](app/test/widget_test.dart)。
- [依赖与版本锁定](app/pubspec.yaml)、[pubspec.lock](app/pubspec.lock)。
- [已有 Android 调试 APK](app/build/app/outputs/flutter-apk/app-debug.apk)。

旧原型使用 shared_preferences 保存本地 JSON，尚未实现 SQLite、加密存储或云同步。页面仅作功能迁移参考；新客户端的视觉以用户提供的参考图为准。

若需继续运行旧原型，从本目录的 `app/` 执行旧 README 中的 Flutter 命令；目录移动后先运行 `flutter pub get` 更新依赖配置。已有 APK 是旧原型产物。
