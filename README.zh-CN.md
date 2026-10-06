# Steam Game Launcher

[English](README.md) · 简体中文

使用 SwiftUI 构建的原生 macOS 游戏启动器，集中打开 Steam 游戏与本地应用。

[下载](https://github.com/lopleec/Steam-Game-Launcher/releases/latest) · [反馈问题](https://github.com/lopleec/Steam-Game-Launcher/issues) · [MIT 许可证](LICENSE)

## 功能

- 扫描 Mac 上的 Steam 游戏库，支持外置磁盘，并标记已安装游戏。
- 启动游戏，跳转 Steam 商店、游戏库、社区、成就、指南与创意工坊。
- 搜索、排序、收藏和自定义合集；同步游戏库后支持 Windows、Linux 分类与平台角标。
- 添加 Steam App ID、本地 `.app`、脚本、`.command`、`.jar` 等文件；移除的快捷入口可以恢复。
- 隐藏游戏，并可设置查看密码。
- 全屏动态海报墙，支持横向、竖向、倾斜滚动、闲置自动进入和时钟显示。
- 首次启动引导与还原默认设置。

## 安装

需要 **macOS 14 或更高版本**，DMG 同时支持 **Apple Silicon 和 Intel Mac**。启动 Steam 游戏及使用 Steam 链接需要安装 Steam 客户端。

从 [Releases](https://github.com/lopleec/Steam-Game-Launcher/releases/latest) 下载并打开 DMG，将 **Steam Game Launcher** 拖入 **Applications**。

当前版本使用临时签名，尚未经过 Apple 公证。首次打开时，macOS 可能要求在 **系统设置 → 隐私与安全性** 中批准打开。

## Steam 游戏库同步

可选的 **登录 Steam** 会在应用内打开 Steam 官方页面。登录后可同步账号游戏库、保存到本机，再根据本地扫描结果标记已安装游戏。无需开发者 API 密钥或独立服务器；下载与社交功能交由 Steam 处理。

账号同步目前为 **实验功能**，依赖 Steam 网页会话接口。未登录时也能扫描本地游戏。

应用数据保存在 `~/Library/Application Support/SteamGameLauncher/`。Steam 网页会话保存在本应用的本地 WebKit 存储中，游戏库文件不保存密码或登录令牌。海报优先读取 Steam 本地缓存，在线海报与游戏资料请求可在设置中关闭。

## 构建

需要带有 **Swift 5.10 或更高版本**的 Xcode 命令行工具，以及用于打包的 Python 3。

```sh
./script/build_and_run.sh --verify  # Debug 构建并启动
swift test                        # 单元测试
./script/package_dmg.sh            # 通用 Release DMG，输出至 dist/
```

包名和版本号统一配置在 [`script/app_config.sh`](script/app_config.sh)，应用包名为 `com.lopleec.SteamGameLauncher`。

## 许可证

采用 [MIT 许可证](LICENSE)。Steam 与游戏原画归各自权利人所有，本项目与 Valve 无关联。
