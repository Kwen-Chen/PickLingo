# PickLingo

PickLingo is a plugin-driven macOS productivity tool built with SwiftUI. It provides a lightweight desktop workflow where multiple capabilities (including translation) can be added and managed through plugins.

中文说明请见：[README.zh-CN.md](./README.zh-CN.md)

## Features

- SwiftUI-based macOS app (`PickLingo.app`)
- Plugin-first architecture for multiple tool capabilities
- Translation is one built-in capability, not the only one
- Extensible services and domain models for future plugins
- Settings, onboarding, and result/tooltip panels
- Localized resources (`en`, `zh-Hans`)

## Project Structure

```text
.
├── PickLingo/                    # App source code
│   ├── App/                      # App lifecycle and menu bar logic
│   ├── UI/                       # SwiftUI views and panels
│   ├── Services/                 # Plugin, translation, and core helper services
│   ├── Models/                   # Domain models and settings
│   ├── Resources/                # Assets and localization resources
│   ├── Info.plist
│   └── SelectTranslate.entitlements
├── PickLingo.xcodeproj/          # Xcode project
├── README.md                     # Default documentation (English)
├── README.zh-CN.md               # Chinese documentation
└── .gitignore
```

## Requirements

- macOS
- Xcode 16+ (recommended)
- Swift 5.9+

## Build & Run

1. Open `PickLingo.xcodeproj` in Xcode.
2. Select target `PickLingo`.
3. Build and run.

## Notes

- User-specific Xcode files and build outputs are ignored via `.gitignore`.
- Chinese documentation: `README.zh-CN.md`.

## License

Please add a `LICENSE` file if you plan to open-source this project.
