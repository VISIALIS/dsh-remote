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
   - Each paired device receives its own bearer token. The token is not bound to a
     hardware fingerprint, an attestation, or an expiry date: anyone who copies it
     can use it until it is revoked. The value shown as a fingerprint in the panel
     is a truncated hash of the token, used only to name the row to revoke.
   - A stored scope is honored only when it is exactly `lecture` or `ecriture`.
     A record with no scope field is legacy and remains `ecriture`. Any other
     value is ignored: that token does not authenticate.
   - Revoking a device from the harness browser panel rejects later HTTP calls
     and closes that device's open WebSocket streams. Other devices keep working.
4. **Network Exposure**:
   - DSH Remote is designed for private mesh networks (such as Tailscale) or localhost.
   - Never expose the harness port directly to the public internet without an encrypted,
     authenticated VPN or overlay network.
   - The native client will not send a bearer token over cleartext HTTP to a public
     IP address. Loopback, private ranges, and Tailscale's CGNAT range
     (`100.64.0.0/10`) remain allowed, because that is the supported path.

## What is NOT a Security Vulnerability

- An authorized token holder with `ecriture` scope submitting prompts to a session
  (this is the intended functionality of the remote client; revoke the device token
  from the harness web UI to cut access).
- DSH running tools or file modifications authorized by the user/agent in a session.

## Reporting a Vulnerability

If you discover a potential security vulnerability in DSH Remote, please report it
responsibly via GitHub Private Vulnerability Reporting on this repository.

All valid reports will be promptly acknowledged and addressed.
