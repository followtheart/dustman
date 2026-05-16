# Dustman

> 一款安全、可视化的 Windows 桌面端垃圾清理工具。Flutter for Windows Desktop。

清理 Windows 在日常使用中产生的临时文件、浏览器缓存、系统日志、缩略图缓存、
回收站与 DNS 缓存。所有删除前都经过白名单二次校验，绝不动系统关键目录。

## 功能（MVP v0.1）

- 临时文件（`%TEMP%`、`C:\Windows\Temp`）
- 浏览器缓存（Chrome / Edge / Firefox）
- Windows 日志与崩溃转储
- 缩略图 / 图标缓存
- 回收站统计与一键清空（Win32 `SHEmptyRecycleBin`）
- DNS 缓存（`ipconfig /flushdns`）
- Material 3 主题，浅色 / 深色 / 跟随系统

后续路线见 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)，
架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 运行环境

- Windows 10 1809+ / Windows 11
- Flutter SDK ≥ 3.22，Dart ≥ 3.4
- Visual Studio 2022（含 "使用 C++ 的桌面开发" 工作负载）

## 快速开始

仓库初次提交中不包含 `windows/` 原生 runner 目录（由 Flutter 工具链生成）。

```powershell
git clone https://github.com/followtheart/dustman.git
cd dustman

# 1. 生成 Windows 原生 runner（仅首次）
flutter create --platforms=windows .

# 2. 拉取依赖
flutter pub get

# 3. 调试运行
flutter run -d windows

# 4. 发布构建
flutter build windows --release
# 产物：build\windows\x64\runner\Release\
```

## 目录结构

```
lib/
├── main.dart                # 入口
├── app.dart                 # MaterialApp & MultiProvider
├── core/                    # 主题、常量、工具
├── domain/                  # 实体与 Scanner 抽象
├── data/                    # Scanner 实现、Win32 服务
└── presentation/            # screens / widgets / providers
docs/                        # 需求与架构文档
test/                        # 单元测试
```

## 测试

```powershell
flutter test
```

## 安全策略

- 内置 `SafetyGuard` 白名单：System32、SysWOW64、用户 Documents/Desktop 等绝对禁止；
- 所有清理动作前 UI 弹出二次确认；
- 单文件失败不会中断整体流程，而是计入清理报告。

详见 [docs/REQUIREMENTS.md §4.1](docs/REQUIREMENTS.md)。

## 许可

待定。
