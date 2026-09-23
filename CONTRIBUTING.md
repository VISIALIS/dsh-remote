# Contributing to DSH Remote

Thank you for your interest in contributing to DSH Remote.

## Architecture Overview

The repository consists of two integrated components:

1. `plugin/`: The backend host plugin loaded by DeepSeek Harness (Node.js ES module). It exposes REST endpoints and WebSocket feeds for real-time monitoring and control.
2. `macos-ios/`: The native Swift / SwiftUI companion application for macOS and iOS, including Widgets and Live Activities (`DSHRemoteKit`, `DSHRemoteMac`, `DSHRemoteWidgets`).

## Code and Language Policy

- The existing codebase, comments, architectural notes, and commit history are written in French.
- Contributions, issues, and pull requests in either **English** or **French** are welcome.
- Technical documentation under `plugin/README.md` and `macos-ios/README.md` provides in-depth French references for internal mechanics.

## Security Rules (Mandatory)

1. **Zero Secrets**: Never commit real tokens, cookies, API keys, personal email addresses, private Tailscale tailnet names, Apple developer team IDs, or local absolute paths (`/Users/...`).
2. **No Data Exfiltration**: Never add any external network telemetry, analytics, or remote logging.
3. **Synthetic Test Data Only**: All tests must use mock fixtures and explicitly artificial names (`example.com`, `acme-project`, etc.).

## Verification Before Submitting

Before submitting a Pull Request, run the local verification suite:

```bash
bash scripts/verifier.sh
```

This verifies:
1. `scripts/check-secrets.sh`: Full history and working tree secret audit.
2. `node --test plugin/tests/`: Host plugin test suite (147+ tests).
3. `swift test`: Swift package test suite across models and networking (350+ tests).

All checks must pass (`exit 0`) without warnings.

## Commit Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation updates
- `test`: Test suite additions or fixes
- `refactor`: Code refactoring without behavior change
- `security`: Security patches
