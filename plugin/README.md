# dsh-remote — Host Plugin for DeepSeek Harness

> **A versioned JSON & WebSocket API surface for native macOS and iOS companion apps.**
> For the French documentation, see [`README.fr.md`](README.fr.md).

The `dsh-remote` plugin exposes a structured, real-time JSON and WebSocket interface to the DeepSeek Harness (DSH) running on a host Mac. It does not replace the harness web UI; instead, it allows native companion apps (macOS, iOS, iPadOS) to observe agent sessions, monitor tool executions, inspect logs, and send prompts.

It also embeds a web panel into the harness browser interface: the host displays a pairing QR code (and plain-text code) that securely configures the companion app with one scan. What travels over the air during pairing is a **single-use 2-minute pairing code**, never the permanent device token. Each client exchanges this code for its own scoped device token, which can be revoked at any time from the web panel.

---

## Key Capabilities

- **JSON API Surface**: Versioned `/v1/*` routes providing access to active and loaded sessions, detailed session logs, workspace metadata, and state machines.
- **Real-Time WebSocket Stream (`/v1/flux`)**: Low-latency event streaming for turn lifecycle, step transitions, tool invocations, and live model output chunking.
- **Secure Pairing**: Zero manual secret copy-pasting. Single-use QR codes with a 2-minute TTL generate isolated per-device tokens.
- **Zero External Exfiltration (Rule #0)**: Operates purely over local loopback (`127.0.0.1`) or private mesh networks (Tailscale). No third-party servers, telemetry, or analytics.
- **Fine-Grained Scopes**: Default `lecture` (read-only) scope prevents unauthorized modifications; `ecriture` (read-write) is strictly required for `/prompt` and `/annuler`.

---

## Architecture & File Layout

```text
plugin/
├── dynamic/
│   ├── host.js             # Cordis module loaded by the DSH profile
│   ├── client.js           # Companion web panel injected into harness UI
│   ├── auth.js             # Authentication, token registry, and scope guards
│   ├── appairage.js        # Pairing logic (single-use code exchange)
│   ├── codes-appairage.js  # Short-lived pairing code generator and TTL
│   ├── appareils.js        # Known device registry and revocations
│   ├── journal.js          # Session log parsing and frame extraction
│   ├── trames.js           # Event frame formatting for WebSocket
│   ├── tailscale.js        # Tailscale MagicDNS and local IP resolution
│   └── reponse.js          # Normalized JSON HTTP response helpers
├── tests/                  # Automated test suite (147+ tests using Node.js test runner)
├── ANNEXE-MESURES.md       # Benchmarks, protocol timings, and design log (French)
├── README.md               # This English documentation
└── README.fr.md            # In-depth architectural log and documentation (French)
```

---

## Installation & Configuration

The plugin is a standard ES module loaded directly by Cordis via the DSH profile configuration.

### 1. Register in DSH Profile

Add the plugin to your profile configuration (e.g. `~/.dsh/profiles/default/cordis.patch.yml`):

```yaml
- op: insert
  path: /plugins/-
  value:
    name: 'file:///path/to/dsh-remote/plugin/dynamic/host.js'
    config:
      journaliser: true
```

### 2. Verify Plugin Operation

Run the self-contained test suite without launching DSH:

```bash
node --test plugin/tests/**/*.test.js
```

---

## Protocol & API Surface

### Authentication

All endpoints under `/v1/*` (except pairing negotiation) require an `Authorization` header:

```http
Authorization: Bearer <device-token>
```

Tokens are 43-character base64url random secrets generated during pairing.

### HTTP Endpoints

| Method | Endpoint | Required Scope | Description |
|---|---|---|---|
| `GET` | `/v1/etat` | `lecture` | Server health check and plugin version |
| `GET` | `/v1/sessions` | `lecture` | List of known sessions, statuses, and workspace paths |
| `GET` | `/v1/session/:id` | `lecture` | Detailed session overview and step history |
| `GET` | `/v1/session/:id/journal` | `lecture` | Chronological session events and model outputs |
| `POST` | `/v1/session/:id/prompt` | `ecriture` | Submit a new user prompt to an active session |
| `POST` | `/v1/session/:id/annuler` | `ecriture` | Cancel the current agent turn |
| `POST` | `/v1/appairer` | None | Exchange a 2-minute pairing code for a permanent device token |

### WebSocket Endpoint (`/v1/flux`)

Companion clients establish a WebSocket connection on `/v1/flux` with their device token in the `Authorization` header or query parameter. The stream delivers:
- `turn_start` / `turn_end`: Agent turn transitions
- `step_progress`: Tool execution updates (terminal command, file modifications)
- `session_status`: Changes between idle, working, or awaiting user confirmation
- `ping` / `pong`: Liveness heartbeat every 15 seconds

---

## Pairing Security Model

1. **Host Generation**: The host web panel generates a cryptographically random, single-use 6-character code (or QR code) valid for 120 seconds.
2. **Device Scan**: The native app scans the QR code, which contains `dshremote://pair?addr=<host>&code=<code>`.
3. **Token Exchange**: The device contacts `/v1/appairer` with the code. If valid, the host consumes the code and returns a unique device token.
4. **Independent Revocation**: Each device is tracked in the host's device registry with its creation date and friendly name, allowing instant one-click revocation.

---

## Verification & Testing

To run the automated test suite:

```bash
# Run plugin tests only
node --test plugin/tests/**/*.test.js

# Run full project verification (Rule #0 check + plugin tests + Swift tests)
bash scripts/verifier.sh
```
