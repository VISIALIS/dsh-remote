# DSH Remote — Native Apple Companion (macOS & iOS)

> **A native Swift / SwiftUI client for DeepSeek Harness (DSH).**
> For the original French measurement journal and technical notes, see [`README.fr.md`](README.fr.md).

DSH Remote provides a fast, responsive, and secure native interface to monitor and interact with DeepSeek Harness agents running on your Mac. It shares a core Swift framework (`DSHRemoteKit`) between macOS, iOS, iPadOS, and WidgetKit extensions.

---

## Architectural Highlights

- **Shared Core (`DSHRemoteKit`)**: Implements protocol models, WebSocket streaming with auto-reconnect, state machine, Keychain credential store, and shared WidgetKit views.
- **Native SwiftUI Apps**:
  - **macOS (`DSHRemoteMac` / `DSH Remote.app`)**: Multi-column window, keyboard navigation, menu bar integration, and Notification Center widgets.
  - **iOS (`DSHRemote`)**: Touch-optimized interface, QR scanner for pairing, Lock Screen widgets, and Dynamic Island Live Activities.
- **WidgetKit Widgets (`DSHRemoteWidgets`)**:
  - **Small (2x2)** & **Medium (4x2)** widgets displaying real-time agent status, active sessions, and quiet-state ambiance.
  - Platform-adaptive backgrounds (`containerBackground` API) and App Group shared snapshots (`InstantaneWidget`).
- **Bilingual & Localization**:
  - **Primary / Default Language**: English (`en`).
  - **Localized Language**: French (`fr`), automatically activated whenever the host operating system language is French.
  - Zero hardcoded English-only or French-only fallbacks in user-facing views; 100% string parity enforced by automated test suites.
- **Security First (Rule #0)**:
  - Tokens and sensitive host credentials stay inside Apple Keychain.
  - Widgets operate exclusively on sanitized, synthetic display snapshots (`InstantaneWidget`) with zero secrets or private paths.

---

## Repository Structure

```text
macos-ios/
├── Package.swift                  # SwiftPM package definition (DSHRemoteKit, DSHRemoteCtl, DSHRemoteApp)
├── DSHRemote.xcodeproj            # Xcode project for iOS app, macOS app, and Widget extensions
├── Config/
│   ├── Base.xcconfig              # Versioned common build settings (bundle IDs, default App Group)
│   ├── Local.xcconfig             # (Gitignored) Developer Apple Team ID and local overrides
│   ├── DSHRemote.entitlements     # Main app capabilities (App Groups, etc.)
│   └── DSHRemoteWidgets.entitlements # Widget extension capabilities (App Groups)
├── Sources/
│   ├── DSHRemoteKit/              # Core library (Network, Protocol, State, Persistence, Widgets UI)
│   │   ├── Ressources/
│   │   │   ├── en.lproj/          # English localization table (Primary)
│   │   │   └── fr.lproj/          # French localization table (OS language fallback)
│   │   ├── VuesWidget.swift       # Widget SwiftUI views (Small, Medium, Zen ambiance)
│   │   └── ...
│   └── DSHRemoteApp/              # macOS SwiftUI entry point and application delegate
├── App/                           # iOS SwiftUI views, QR scanner, and application lifecycle
├── Widgets/                       # WidgetKit timeline provider and widget bundle
├── Tests/
│   └── DSHRemoteKitTests/         # 360+ automated unit and integration tests
├── Scripts/
│   ├── construire-app-ios.sh      # Compiles, provisions, and signs iOS app
│   ├── empaqueter-app-macos.sh    # Bundles, signs, and installs macOS .app with widgets
│   ├── generer-icone.py           # Generates application icons and ICNS files
│   └── traduire.py                # Synchronizes and verifies en/fr localization parity
├── README.md                      # This English documentation
└── README.fr.md                   # In-depth architectural journal and device measurements (French)
```

---

## Language & Localization Philosophy

The application follows standard Apple internationalization guidelines:

1. **Development Region**: Set to English (`en`). Non-French devices default to English.
2. **French Localization**: When an iPhone, iPad, or Mac runs with French as its system language (`fr` or `fr-FR`), all labels, buttons, error messages, and widgets render in French.
3. **Parity Enforcement**: `TraductionTests.swift` inspects the compiled bundle during test runs to guarantee that every single localized key in French has an exact counterpart in English, and vice versa.

To update or audit translations after adding new strings:

```bash
# Verify translation parity
python3 Scripts/traduire.py --verifier

# Synchronize tables
python3 Scripts/traduire.py
```

---

## Building and Running

### 1. macOS Application

To build and package the native macOS app with its embedded WidgetKit extension into `/Applications/DSH Remote.app`:

```bash
bash Scripts/empaqueter-app-macos.sh --installer
```

To run directly from SwiftPM during development:

```bash
swift run DSHRemoteMac
```

### 2. iOS Application (iPhone / iPad)

#### On Physical Device

1. Configure your personal Apple Development Team ID in `Config/Local.xcconfig`:
   ```xcconfig
   DSH_TEAM = <YOUR_APPLE_TEAM_ID>
   DSH_BUNDLE_ID = fr.visialis.DSHRemote
   DSH_APP_GROUP = group.fr.visialis.DSHRemote
   ```
2. Build with provisioning:
   ```bash
   bash Scripts/construire-app-ios.sh --provisionnement
   ```
3. Install to your connected device using `devicectl`:
   ```bash
   xcrun devicectl device install app --device <DEVICE_UUID> ".build/iphone/Build/Products/Release-iphoneos/DSHRemote.app"
   ```

#### On iOS Simulator

```bash
bash Scripts/construire-app-ios.sh --simulateur
```

---

## WidgetKit Widgets & Live Activities

The companion provides interactive home screen and notification center widgets:

- **Medium Widget (4x2)**: Displays current server connection state, active session counters, and the latest running session step.
- **Small Widget (2x2)**: Compact glanceable card displaying server status and active work counts.
- **Zen Disconnected State**: When no agent turn is running or the server is disconnected, the widget displays an elegant, calming message ("All is quiet" / "Tout est calme") with subtle moon/stars iconography and a tap-to-sync action.

---

## Verification & Testing

Every commit and change is validated against Rule #0 (security) and full test suites:

```bash
# Run Swift package tests
(cd macos-ios && swift test)

# Run complete repo verification
bash scripts/verifier.sh
```
