# Repository Rules — DSH Remote

This repository contains the host plugin and native macOS/iOS companion client for DeepSeek Harness (DSH).
These rules apply to all AI coding agents and human contributors working in this repository.

---

## RULE #0 — SECURITY FIRST (ABSOLUTE RULE)

Security overrides features, convenience, speed, and elegance.
In any conflict between a security rule and any other consideration, security wins.

### Why this rule is first

**A DSH plugin runs with the full privileges of the user process.**
There is no sandbox boundary between a plugin and the harness hosting it.
The harness holds high-value secrets: browser authentication tokens, API keys, session histories, and local file access.

### Key Rules

1. **Never commit secrets, real tokens, or personal paths.** No API keys, no bearer tokens, no real tailnet domains, no personal Apple team IDs, no `/Users/<username>/` paths.
2. **Zero external data exfiltration.** No telemetry, no external network calls containing session content or code.
3. **Synthetic test fixtures only.** All tests use explicitly artificial names and mock data.
4. **All endpoints enforce authentication and scope.** Write actions (`/prompt`, `/annuler`) require `ecriture` scope.
5. **Always verify before proposing changes:**
   ```bash
   bash scripts/verifier.sh
   ```
   Must pass (`exit 0`).

---

## RULE #1 — Architecture

- `plugin/`: The backend host plugin loaded by DeepSeek Harness.
  - `plugin/dynamic/host.js`: ES module loaded into the DSH profile.
  - `plugin/dynamic/client.js`: Web panel bundle served to the harness UI.
  - `plugin/tests/`: Automated Node.js test suite (`node --test`).
- `macos-ios/`: Native Swift / SwiftUI application for macOS and iOS.
  - `macos-ios/Sources/DSHRemoteKit/`: Core networking, protocol decoding, state machine, and keychain storage.
  - `macos-ios/App/`: SwiftUI views, navigation, and menu commands.
  - `macos-ios/Widgets/`: WidgetKit extensions and Dynamic Island Live Activities.
  - `macos-ios/Tests/`: Swift package test suite (`swift test`).

---

## RULE #2 — Verification

All changes must pass:
1. `bash scripts/check-secrets.sh`
2. `node --test plugin/tests/`
3. `(cd macos-ios && swift test)`
Or simply `bash scripts/verifier.sh`.
