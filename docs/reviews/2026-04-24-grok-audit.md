# External architecture + security audit — Grok, 2026-04-24

Audit performed on commit `ca09707` (v0.1.6, "App Store prep: splash, demo mode, privacy policy, archive workflow"). Refinements made after this audit are tracked in [`CHANGELOG.md`](../../CHANGELOG.md) — notably the 0.1.7 demo-mode persistence fix, 0.1.8 demo-mode indicator + cold-launch exit, and 0.1.9 read-only-key hint, Re-pin Certificate flow, and README Security section.

## Overall verdict

> Architecturally sound and security-strong — easily one of the cleaner self-hosted companion clients I've reviewed. With the small set of recommendations below, you can push it to v0.2.0 feeling very confident for wider testing or even TestFlight distribution.

**No critical or high issues found.**

## Strengths confirmed

- **Secrets handling.** API keys and cert fingerprints live only in Keychain (`kSecAttrAccessibleWhenUnlocked`, bundle-scoped). Never in `sites.json` or UserDefaults on real devices; the simulator fallback is explicit and safe.
- **TLS / certificate validation.** Strict App Transport Security (`NSAllowsArbitraryLoads: false`). Default path is full OS trust evaluation. Self-signed mode uses TOFU + SHA-256 leaf fingerprint pinning in `TLSDelegate` — once trusted, no bypass is possible. Negotiated TLS version (e.g. 1.3) is shown in Settings.
- **Network communication.** `X-API-Key` header only (matches the backend's mobile/automation path). No cookies, no persistent auth tokens beyond the key.
- **Data at rest.** Cache uses standard protected directories; site deletion fully cleans Keychain + cache.
- **Privacy.** Zero analytics, telemetry, or third-party frameworks. Privacy policy stub present and linked.
- **Error surfacing.** TLS errors, 401s, connection issues are clearly shown in UI without leaking sensitive details.
- **Entitlements & signing.** Minimal and correct for Keychain access. App Store prep (archive workflow) landed in the audited commit.

## Recommendations & how they were addressed

### Exponential backoff + retry wrapper
**Grok:** create a `RetryableRequest` extension with 3 attempts + jitter.
**Response:** Declined. `DashboardViewModel.startPolling` already does `2^consecutiveFailures` with a 16× ceiling, covering the "transient flap" case. Per-request retry would delay pull-to-refresh failure feedback without adding signal the poll loop doesn't already provide.

### Enhanced TOFU pinning
**Grok:** add a "Re-verify Cert" affordance; log cert changes.
**Response:** Partially implemented in 0.1.3 (`SiteFormView.retrustRequired` forces a fresh TOFU handshake whenever the URL or `allowSelfSigned` flag changes). 0.1.9 adds an explicit **Re-pin Certificate** button in Settings for the cert-rotation case where the URL hasn't changed.

### Background refresh improvements
**Grok:** have `BGAppRefreshTask` check `/api/health` + sync status first before a full dashboard pull; make refresh interval user-tunable.
**Response:** Not applicable. `BGAppRefreshTask` was removed in 0.1.0 — refresh is now scene-phase-driven (foreground polling + refresh on `.active`). The poll interval is server-driven from `HealthResponse.stats_poll_interval` to avoid letting a client hammer the server; a user override would invite abuse. Declining both.

### Least-privilege prompt
**Grok:** prompt users to pick a read-only API key during onboarding.
**Response:** Implemented in 0.1.9. The API Key section in `SetupSheet` now carries a footer recommending a read-only key where the server supports one.

### App Store / distribution polish
**Grok:** add ATS exceptions for self-signed; `UIBackgroundModes` for background refresh; a README Security section.
**Response:**
- No ATS exceptions needed — self-signed is handled by the custom `URLSessionDelegate`, and keeping `NSAllowsArbitraryLoads: false` is stricter.
- No `UIBackgroundModes` needed — we don't use background modes.
- README Security section added in 0.1.9.

### Optional future-proofing
**Grok:** adopt Swift 6 actors for `SiteStore` / `NetworkMonitor`.
**Response:** Deferred. `AppState` is `@Observable` and main-actor-confined; the singletons are only touched from the main actor. Adding explicit actor isolation is motion without a current correctness benefit. Strict Swift 6 concurrency is already enabled (`SWIFT_STRICT_CONCURRENCY: complete`).

## Known limitation from the audit

The audit described "BackgroundTasks for refresh" as a strength. This was incorrect at the audited commit — `BGAppRefreshTask` had already been removed in 0.1.0. Related recommendations that relied on that assumption (user-tunable refresh, UIBackgroundModes) are therefore moot.
