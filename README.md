# DSH Remote

> **A native macOS and iOS companion for DeepSeek Harness.**
> Monitor active AI sessions, inspect tool executions, track token consumption, and interact with running agents from your Mac, iPhone, or iPad.

---

> [!NOTE]
> **Disclaimer**: This is an independent open-source project and is not affiliated with, endorsed by, or sponsored by DeepSeek.

---

## Highlights

- **Real-Time Monitoring**: Live WebSocket stream tracking active turns, tool calls (file edits, command executions), and model generation progress.
- **Native macOS & iOS Apps**: Fluid SwiftUI interfaces tailored for both platforms — responsive keyboard shortcuts on Mac, gestures and carousels on iOS.
- **Widgets & Live Activities**: Track running agent sessions directly on your iOS Lock Screen, Dynamic Island, and macOS Notification Center.
- **Secure by Design**:
  - Zero external telemetry or third-party cloud servers.
  - Default read-only token scope (`lecture`); write operations require explicit opt-in.
  - Instant pairing via short-lived QR codes with per-device token revocation.
- **Mesh Network Ready**: Seamless discovery and connection over Tailscale private networks or local LAN.

---

## Repository Structure

DSH Remote is organized as a monorepo containing both the harness host plugin and the native Apple clients:

```text
dsh-remote/
├── plugin/            # Host plugin for DeepSeek Harness (Node.js ESM)
│   ├── dynamic/       # Host module and harness browser panel bundle
│   ├── tests/         # Automated test suite (150+ tests)
│   ├── README.md      # Technical documentation (English)
│   └── README.fr.md   # Architectural log and measurements (French)
│
├── macos-ios/         # Native Apple client application (Swift / SwiftUI)
│   ├── Sources/       # Core networking, protocol parsing, and state machine (DSHRemoteKit)
│   ├── App/           # macOS and iOS SwiftUI application
│   ├── Widgets/       # WidgetKit extensions and Live Activities (DSHRemoteWidgets)
│   ├── Tests/         # Swift test suite (360+ tests)
│   ├── README.md      # Architectural documentation (English)
│   └── README.fr.md   # In-depth architectural journal and measurements (French)
│
└── scripts/           # Security audit and verification scripts
```

---

## Getting Started

### 1. Enable the Plugin in DeepSeek Harness

1. Clone or place this repository on the machine running DeepSeek Harness.
2. In your DSH profile configuration (e.g. `~/.dsh/profiles/default/cordis.patch.yml`), register the host plugin:

   ```yaml
   - op: insert
     path: /plugins/-
     value:
       name: 'file:///path/to/dsh-remote/plugin/dynamic/host.js'
       config:
         port: 3000
   ```

3. Restart DeepSeek Harness. The plugin exposes `/dsh-remote/v1/*` endpoints and registers a pairing tab in the harness browser interface.

### 2. Connect from macOS or iOS

1. **Over Tailscale (Recommended)**: Ensure both your harness machine and your Apple device are connected to your Tailscale network.
2. **Launch DSH Remote**:
   - Open DSH Remote on macOS or iOS.
   - Scan the pairing QR code displayed in the harness web interface, or enter the short 6-character pairing code.
   - The app exchanges the code for an individual device bearer token stored securely in your Apple Keychain.

---

## Security & Permissions

DSH Remote adheres to strict least-privilege principles:

| Token Scope | Permissions | Default |
|---|---|---|
| `lecture` (Read-only) | View sessions, inspect tool logs, stream live activities | **Yes** |
| `ecriture` (Read-write) | Send user prompts (`/prompt`), cancel running turns (`/annuler`) | Requires `DSH_REMOTE_PORTEE=ecriture` |

- **Device Revocation**: Each paired device receives a distinct token. If a device is lost or compromised, access can be revoked individually from the harness browser panel without affecting other clients.
- **Confined Traffic**: All communications travel exclusively between your client and your harness over your encrypted mesh or local connection.

For details, see [SECURITY.md](SECURITY.md).

---

## Development & Verification

### Prerequisites

- macOS 15.0 or later
- Xcode 16.0 or later
- Node.js 22.0 or later
- Python 3 with Pillow (only needed if regenerating app icons)

### Running the Test Suite

Run the full verification suite (secrets audit, host plugin tests, and Swift test suite):

```bash
bash scripts/verifier.sh
```

Or run individual test suites:

```bash
# Security & secret audit (checks working tree and full Git history)
bash scripts/check-secrets.sh

# Host plugin tests (150+ tests)
node --test plugin/tests/

# Swift client tests (360+ tests)
cd macos-ios && swift test
```

---

## Documentation

Comprehensive architectural references and protocol specifications are available:

- [Host Plugin Reference](plugin/README.md) — REST API specification, WebSocket stream contract, and pairing protocol.
- [Swift Client Architecture](macos-ios/README.md) — State machine, cache management, offline resilience, and Live Activity lifecycles.
- [Contributing Guidelines](CONTRIBUTING.md) — Pull request guidelines and code style.
- [Security Policy](SECURITY.md) — Security model and reporting instructions.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
