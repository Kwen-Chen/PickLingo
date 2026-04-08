# PickLingo

PickLingo 是一个使用 SwiftUI 开发的 macOS 多插件效率工具。它通过插件机制扩展多种能力（翻译只是其中之一），并以轻量级桌面界面统一承载工作流。

## 功能特性

- 基于 SwiftUI 的 macOS 应用（`PickLingo.app`）
- 插件优先架构，支持多能力扩展
- 翻译能力为内置插件场景之一，而非唯一场景
- 可扩展服务层与领域模型，便于新增插件
- 设置页、引导页、结果面板与悬浮提示面板
- 本地化资源（`en`、`zh-Hans`）

## 项目结构

```text
.
├── PickLingo/                    # 应用源代码
│   ├── App/                      # 应用生命周期与菜单栏逻辑
│   ├── UI/                       # SwiftUI 界面与面板
│   ├── Services/                 # 插件、翻译与核心辅助服务
│   ├── Models/                   # 领域模型与配置
│   ├── Resources/                # 资源与本地化文件
│   ├── Info.plist
│   └── SelectTranslate.entitlements
├── PickLingo.xcodeproj/          # Xcode 工程
├── README.md                     # 默认英文文档
├── README.zh-CN.md               # 中文文档
└── .gitignore
```

## 环境要求

- macOS
- Xcode 16+（推荐）
- Swift 5.9+

## 构建与运行

1. 使用 Xcode 打开 `PickLingo.xcodeproj`。
2. 选择 `PickLingo` target。
3. 编译并运行。

## 说明

- `.gitignore` 已忽略构建产物和用户本地配置文件。
- 默认文档为英文（`README.md`），中文文档见 `README.zh-CN.md`。

## 许可证

如果你计划开源该项目，建议补充 `LICENSE` 文件。
