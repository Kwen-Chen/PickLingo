# PickLingo
English documentation see [README.md](./README.md).

PickLingo 是一个插件优先的 macOS 高度自定义桌面助手。
你在支持辅助功能取词的应用里选中文本后，它会在光标附近弹出轻量提示面板，让你立即调用 AI 或本地动作插件完成处理。


## 为什么用 PickLingo

- 选中即处理：不用频繁切应用、复制粘贴
- 插件化架构：AI 插件和本地命令插件统一管理
- 交互轻量：提示面板 + 结果面板，链路短、反馈快
- 默认即好用：翻译、解释、润色、总结、提问、打开、定位路径
- 可深度定制：模型预设、主题、快捷键、黑名单、插件行为

## 核心工作流

1. 在任意支持应用中选中文本。
2. PickLingo 检测到选区后弹出 Tooltip 插件条。
3. 点击插件立即执行；如插件需要额外输入，会先弹输入面板。
4. 在结果面板中查看内容，并可复制、插入、替换、重新生成、追问。

## API 协议

使用 OpenAI 标准 Chat Completions（`/v1/chat/completions`），支持普通 JSON 响应和 SSE 流式输出，以及自行配置的 HTTP/HTTPS 网关。普通请求不发送厂商私有 `reasoning` 字段，也不强制设置采样温度；Think Mode 使用标准 `reasoning_effort: medium`，需要模型支持。输出上限使用 `max_completion_tokens`。

API 基础地址可以带网关路径前缀，也可以直接填写完整的 `/chat/completions` 地址。连接测试会完整显示错误，支持选择复制。HTTP 不加密，请仅用于可信的本地或内网服务。

## 选中与复制兼容性

自动取词通过辅助功能接口读取文本。启动和切换应用时会按能力自动启用接口，兼容 Chromium/Electron；接口尚未就绪时有限重试一次，无需逐个配置应用。取词不模拟 ⌘C、不修改剪贴板，也不会在选中后恢复旧剪贴板，因此 Ghostty 的选中自动复制、VS Code 的复制粘贴可由原应用正常处理。

若某个应用无法自动取词，请正常复制，再选择菜单栏的 **处理已复制文本**。菜单栏也支持一键在当前应用中禁用自动取词；黑名单会在重启后保留。

结果面板中，⌘C 用于原生选区复制；**复制**按钮或 ⇧⌘C 复制完整结果。输出中可点击**停止**，阅读和选择结果时不会自动聚焦追问输入框。**插入／替换会将结果保留在剪贴板**，不再延迟恢复旧内容。

## 默认插件配置

### 默认启用

- `Translate`：多语言翻译，支持源/目标语言控制
- `Explain`：解释文本（默认 Prompt 输出中文解释）
- `Polish`：润色表达，修正文法与语气
- `Summarize`：提炼重点（默认 Prompt 输出中文总结）
- `Ask`：基于选中文本提问，也可通过 Quick Ask 直接提问

### 默认内置但关闭

- `复制`（自定义本地动作）：`echo {selected_text} | pbcopy`
- `打开目录`（内置 `open-resource`）：`open {selected_text}`
- `搜索`（内置 `reveal-path` 插槽）：`open 'https://www.google.com/search?q='{selected_text}`

上述默认插件名称会随界面语言（English / 简体中文）自动切换。

## 安装方式

### 方式 A：源码运行（开发者推荐）

1. 用 Xcode 打开 `PickLingo.xcodeproj`。
2. 选择 `PickLingo` Scheme。
3. 编译并运行。
4. 首次启动按引导授予 Accessibility（辅助功能）权限。

### 方式 B：

1. 打开 `.dmg`，把 `PickLingo.app` 拖到 `Applications`。
2. 首次打开如果提示“无法验证开发者”，属于未签名应用的常见行为。
3. 前往 `系统设置 -> 隐私与安全性`，点击对应的“仍要打开”。
4. 或在 Finder 中对 App 执行一次 `Control + 点击 -> 打开`。

## 构建与打包命令

在项目根目录执行：

```bash
# 生成 Archive
xcodebuild -project PickLingo.xcodeproj \
  -scheme PickLingo \
  -configuration Release \
  -archivePath dist/PickLingo.xcarchive \
  archive
```

生成可拖拽到 Applications 的未签名 DMG：

```bash
APP_PATH="dist/PickLingo.xcarchive/Products/Applications/PickLingo.app"
STAGE_DIR="dist/dmg"
DMG_PATH="dist/PickLingo-unsigned.dmg"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create -volname "PickLingo" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO "$DMG_PATH"
```

## 设置项总览

### General（通用）

- `Enable PickLingo`：全局开关
- `Auto-detect source language`：自动识别源语言
- `Launch at login`：开机自启

### Interface（界面）

- `Interface language`：跟随系统 / English / 简体中文
- `Theme`：跟随系统 / 浅色 / 深色

### Translation（翻译）

- `Default target language`：默认目标语言

### Tooltip（提示面板）

- `Tooltip delay`：选中文本后触发提示面板的延迟
- `Auto-hide tooltip when mouse moves away`
- `Tooltip auto-hide distance`：启用后可配置鼠标移开距离阈值

### Result Panel（结果面板）

- `Result panel font size`：结果文本字号可调
- 支持固定/取消固定，适配连续阅读与操作

### Quick Ask（快捷提问）

- `Enable Quick Ask shortcut`
- `Quick Ask shortcut` 支持：
- `cmd+cmd`（双击 Command）
- 组合键，例如 `cmd+shift+k`、`cmd+return`、`cmd+space`

### OpenAI API

- 以“预设”管理 `API Key`、`API Base URL`、`Model`
- 支持新建、更新、删除预设
- 支持在设置页一键测试连通性

### Streaming & Think Mode

- `Enable streaming output`
- `Enable Think Mode`（需要支持标准推理参数的模型，不依赖流式输出）

### App Scope（应用范围 / 黑名单）

- 默认在所有应用中可用
- 可将指定应用加入黑名单，仅在这些应用中禁用 PickLingo

## 插件系统

### 插件类型

- `AI`：调用你配置的 OpenAI 兼容接口
- `Local Action`：执行本地命令模板

### 可配置项

- 插件名称与图标（SF Symbols）
- Prompt 模板占位符：
- `{selected_text}` `{user_input}` `{source}` `{target}`
- 是否需要用户输入与输入占位文案
- 本地动作插件是否显示结果窗口
- 是否显示源/目标语言控制
- 底部动作按钮开关：复制、插入、替换、重新生成、追问

### 管理能力

- 启用/禁用插件
- 插件排序
- 重置单个插件到默认值
- 新增自定义插件
- 删除自定义插件
- 一键重置为上述默认配置

## 数据与隐私

- 配置保存在本机 `~/.picklingo/` 目录
- 主要文件：
- `~/.picklingo/config.json`
- `~/.picklingo/plugins.json`
- API Key 会随模型预设一起保存在本机配置中

## 环境要求

- macOS
- 需要授予 Accessibility 权限（跨应用选中文本检测依赖）
- 开发环境建议 Xcode 16+

## 项目结构

```text
.
├── PickLingo/                    # 应用源代码
│   ├── App/                      # 生命周期、监控与菜单栏逻辑
│   ├── UI/                       # 设置、引导、提示与结果面板
│   ├── Services/                 # OpenAI 调用、插件执行、本地动作
│   ├── Models/                   # 插件与配置模型
│   ├── Resources/                # 资源与本地化
│   └── Info.plist
├── PickLingo.xcodeproj/
├── README.md
└── README.zh-CN.md
```

## 回归测试

```sh
./scripts/test.sh
```

测试范围及 Ghostty、VS Code 的人工验收步骤见 [回归验证](docs/verification.md)。

## 贡献方式

1. Fork 仓库并创建功能分支。
2. 保持改动聚焦、可验证。
3. 提交 PR；若涉及 UI，建议附截图或录屏。

## 许可证

本项目采用 GNU General Public License v3.0（`GPL-3.0`）许可证。
详细条款请参阅 [LICENSE](./LICENSE)。
