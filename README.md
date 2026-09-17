# PickLingo
中文文档，请参阅 [README.zh-CN.md](./README.zh-CN.md)。


PickLingo is a plugin-first highly customizable macOS assistant that appears right where you work.
Select text in almost any app, trigger the floating tip panel, and run AI or local action plugins in seconds.


## API protocol

PickLingo uses standard OpenAI Chat Completions (`/v1/chat/completions`), including JSON responses and SSE streaming. It supports user-configured HTTP/HTTPS gateways and preserves URL path prefixes. Normal requests omit vendor-specific `reasoning` objects and forced sampling temperatures. Think Mode sends standard `reasoning_effort: medium` to supported reasoning models, and output limits use `max_completion_tokens`.

Connection errors are displayed in full and can be selected and copied. HTTP is unencrypted and is intended for trusted local/internal services.

## Selection and clipboard compatibility

Automatic selection detection reads text through Accessibility APIs. It enables supported accessibility interfaces when you switch apps, including Chromium/Electron, and retries once if the text interface is still initializing. It never sends Cmd+C or writes/restores the clipboard, allowing terminal copy-on-select and editor copy/paste to remain under the source app's control.

If an app does not expose selected text, copy normally and choose **Process Copied Text** from the menu bar. You can also disable automatic detection in the current app; exclusions survive restarts.

In the result panel, Cmd+C uses native text selection. Use **Copy** or Shift+Cmd+C for the full result. **Stop** cancels generation without moving focus to follow-up input. **Insert/Replace leave the result on the clipboard** instead of restoring older contents later.

Run regression tests with `./scripts/test.sh`. See [verification notes](docs/verification.md) for coverage and the Ghostty/VS Code manual checks.

## Why PickLingo

- Selection-first workflow: no app switching, no copy-paste loops
- Plugin architecture: AI plugins and local command plugins in one system
- Built for speed: tooltip trigger, quick result panel actions, and Quick Ask shortcut
- Practical defaults: translation, explain, polish, summarize, ask, open, reveal path
- Fully configurable: model presets, theme, shortcut, app blacklist, and per-plugin behavior

## Core Workflow

1. Select text in any supported foreground app.
2. PickLingo detects the selection and shows a tooltip plugin bar.
3. Click a plugin to execute immediately, or provide extra input when required.
4. Read results in the result panel and apply actions like copy/insert/replace/regenerate/follow-up.

## Default Plugin Configuration

### Enabled by default

- `Translate`: translate between supported languages with source/target controls
- `Explain`: explain selected content (default prompt returns Chinese explanation)
- `Polish`: improve wording, grammar, and clarity
- `Summarize`: summarize selected content (default prompt outputs Chinese summary)
- `Ask`: ask custom questions about selected text or ask directly via Quick Ask

### Included but disabled by default

- `Copy` (custom local action): `echo {selected_text} | pbcopy`
- `Open Folder` (built-in `open-resource`): `open {selected_text}`
- `Search` (built-in `reveal-path` slot): `open 'https://www.google.com/search?q='{selected_text}`

Default plugin names above automatically follow your interface language (English / Simplified Chinese).

## Installation

### Option A: Run from source (recommended for contributors)

1. Open `PickLingo.xcodeproj` in Xcode.
2. Select the `PickLingo` scheme.
3. Build and run.
4. On first launch, grant Accessibility permission when prompted.

### Option B:

1. Open the `.dmg` and drag `PickLingo.app` into `Applications`.
2. On first launch, macOS may block the app because it is unsigned.
3. Go to `System Settings -> Privacy & Security`, then choose `Open Anyway` for PickLingo.
4. Alternatively, in Finder use `Control-click -> Open` once.

## Build & Package Commands

From project root:

```bash
# Archive
xcodebuild -project PickLingo.xcodeproj \
  -scheme PickLingo \
  -configuration Release \
  -archivePath dist/PickLingo.xcarchive \
  archive
```

Create an unsigned DMG with drag-to-Applications layout:

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

## Settings Reference

### General

- `Enable PickLingo`: global on/off switch
- `Auto-detect source language`: detect source language from selected text
- `Launch at login`: start PickLingo automatically at macOS login

### Interface

- `Interface language`: system / English / Simplified Chinese
- `Theme`: system / light / dark

### Translation

- `Default target language`: default target for translation-oriented flows

### Tooltip

- `Tooltip delay`: debounce delay before showing tooltip after selection
- `Auto-hide tooltip when mouse moves away`
- `Tooltip auto-hide distance`: configurable distance threshold when auto-hide is enabled

### Result Panel

- `Result panel font size`: adjustable preview and reading size
- Panel controls include pin/unpin and keyboard-friendly action chips

### Quick Ask

- `Enable Quick Ask shortcut`
- `Quick Ask shortcut` supports:
- `cmd+cmd` for double-Command tap
- key combos like `cmd+shift+k`, `cmd+return`, `cmd+space`

### OpenAI API

- Preset-based config for `API Key`, `API Base URL`, and `Model`
- Save/update/delete reusable presets
- Test connection directly in settings

### Streaming & Think Mode

- `Enable streaming output`
- `Enable Think Mode` (requires streaming)

### App Scope (Blacklist)

- PickLingo is enabled in all apps by default
- Add apps to blacklist to disable PickLingo only in those apps

## Plugin System

### Plugin Types

- `AI`: runs prompts against your configured OpenAI-compatible endpoint
- `Local Action`: runs local command templates on macOS shell

### Plugin Configuration

- Name and icon (SF Symbols)
- Prompt template with placeholders:
- `{selected_text}` `{user_input}` `{source}` `{target}`
- Requires user input toggle and custom placeholder
- Show/hide result panel for local actions
- Show/hide language controls in result header
- Per-plugin action buttons: copy, insert, replace, regenerate, follow-up

### Plugin Management

- Enable/disable per plugin
- Reorder plugin list
- Reset plugin to default
- Add custom plugins
- Delete custom plugins
- Reset all plugins to the default profile above

## Data & Privacy

- Configuration is stored locally under `~/.picklingo/`
- Main files:
- `~/.picklingo/config.json`
- `~/.picklingo/plugins.json`
- API keys are stored as part of local settings/presets on your machine

## Requirements

- macOS
- Accessibility permission (required for cross-app text selection)
- Xcode 16+ for development

## Project Structure

```text
.
├── PickLingo/                    # App source code
│   ├── App/                      # Lifecycle, monitoring, and menu bar logic
│   ├── UI/                       # Settings, onboarding, tooltip, result panels
│   ├── Services/                 # OpenAI service, plugin execution, local actions
│   ├── Models/                   # Plugin and settings models
│   ├── Resources/                # Assets and localization resources
│   └── Info.plist
├── PickLingo.xcodeproj/
├── README.md
└── README.zh-CN.md
```

## Contributing

1. Fork and create a feature branch.
2. Keep changes focused and testable.
3. Open a PR with screenshots or screen recordings for UI changes.

## License

This project is licensed under the GNU General Public License v3.0 (`GPL-3.0`).
See [LICENSE](./LICENSE) for details.
