# Security Policy

## Core Principle: Safety First

Security takes absolute precedence over features, convenience, and performance.
A plugin running in DeepSeek Harness (DSH) executes with the full permissions of
the host process. There is no sandbox boundary between a plugin and the harness.

## Threat Model & Boundaries

1. **No External Telemetry**: Session data, user source code, local paths, and model
   exchanges never leave the user's machines. No third-party analytics or external network
   calls are ever made.
2. **Access Control & Token Scope**:
   - All HTTP and WebSocket endpoints require bearer token authentication.
   - Newly generated tokens default to `lecture` (read-only) scope.
   - Sending prompts (`/prompt`) or cancelling turns (`/annuler`) strictly requires
     `ecriture` (write) scope (`DSH_REMOTE_PORTEE=ecriture`).
   - Read-only tokens receive `403 Forbidden` on write endpoints without triggering
     session mutation.
3. **Device Pairing & Revocation**:
   - Devices pair via short-lived (2 minutes) single-use pairing codes or QR codes.
   - Each paired device receives an individual bearer token tied to its device fingerprint.
   - Tokens can be revoked individually from the harness browser interface.
4. **Network Exposure**:
   - DSH Remote is designed for private mesh networks (such as Tailscale) or localhost.
   - Never expose the harness port directly to the public internet without an encrypted,
     authenticated VPN or overlay network.

## What is NOT a Security Vulnerability

- An authorized token holder with `ecriture` scope submitting prompts to a session
  (this is the intended functionality of the remote client; revoke the device token
  from the harness web UI to cut access).
- DSH running tools or file modifications authorized by the user/agent in a session.

## Reporting a Vulnerability

If you discover a potential security vulnerability in DSH Remote, please report it
responsibly via GitHub Private Vulnerability Reporting on this repository.

All valid reports will be promptly acknowledged and addressed.
