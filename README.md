# PickLingo

PickLingo is a macOS translation helper app built with SwiftUI. It detects selected text, performs translation with plugin-enabled services, and shows results in a lightweight desktop UI.

## Features

- SwiftUI-based macOS app (`PickLingo.app`)
- Translation service abstraction with plugin support
- Language detection and translation result modeling
- Settings, onboarding, and result/tooltip panels
- Localized resources (`en`, `zh-Hans`)

## Project Structure

```text
.
├── PickLingo/                    # App source code
│   ├── App/                      # App lifecycle and menu bar logic
│   ├── UI/                       # SwiftUI views and panels
│   ├── Services/                 # Translation, plugin, and helper services
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
- Chinese documentation is available in `README.zh-CN.md`.

## License

Please add a `LICENSE` file if you plan to open-source this project.
