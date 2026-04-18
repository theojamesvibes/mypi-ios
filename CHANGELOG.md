# Changelog

All notable changes to MyPi iOS are documented here.

---

## [0.0.5] — 2026-04-18

### Fixed

- Query Log tab failed to load with "The data couldn't be read because it is missing." Root cause: `QueryPage` required a `pages` field in `init(from:)`, but the MyPi server's `/api/queries` endpoint never returns it — the server ships `{total, page, page_size, items}` only. `pages` is now computed from `total` and `pageSize` and removed from the decoded fields, so the decode succeeds against the real API shape.

---

## [0.0.4] — 2026-04-18

### Fixed

- Dashboard repeatedly failing with "Not authenticated" on iOS Simulator. Root cause: on an unsigned simulator build (as produced by `xcodebuild … CODE_SIGN_IDENTITY=""`) the Keychain rejects every `SecItemAdd` with `errSecMissingEntitlement`, so the API key saved at the end of the setup sheet never actually landed in the Keychain and subsequent authenticated requests went out with no `X-API-Key` header. The documented way to build for simulator is now ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), which produces a signed binary the simulator Keychain accepts.

### Added

- `MyPi/MyPi.entitlements` with a `keychain-access-groups` entry, wired via `CODE_SIGN_ENTITLEMENTS` in `project.yml` so signed builds (simulator ad-hoc or future signed device builds via an Apple Developer Team) apply the correct entitlements.
- `KeychainStore` now transparently falls back to `UserDefaults` when `SecItemAdd` fails (e.g. fully unsigned builds). On properly signed builds the Keychain path succeeds and the fallback is never used — so there's no security regression on real device installs.

### Changed

- `.github/workflows/build.yml` — CI now builds with `CODE_SIGN_IDENTITY="-"` (ad-hoc) to match the recommended simulator build flags and to exercise the entitlements wiring.

---

## [0.0.3] — 2026-04-18

### Fixed

- Setup sheet now validates the API key before saving the site. Previously it only called the unauthenticated `/api/health` endpoint, so pasting a wrong/inactive key was silently accepted and the user only saw "Not authenticated" later when the dashboard tried to load. The sheet now also probes `/api/stats/summary` with the pasted key and surfaces `"API key rejected: <detail>"` inline if the server returns 401. Both the standard and self-signed/TOFU code paths perform the check.

### Added

- `APIClient.verifyAPIKey(_:)` — lightweight helper that probes an authenticated endpoint without having to persist the key to the Keychain first. Used by the setup sheet.

---

## [0.0.2] — 2026-04-18

### Fixed

- Cached API response types (`AggregatedSummary`, `HistoryResponse`, `TopStatsResponse` and their nested types) are now `Codable` so `DiskCache` can actually serialise them.
- `DiskCache.write(_:key:)` / `read(key:as:)` generic constraints raised to `Codable` to match `CachedResponse<T: Codable>`.
- `MyPiApp.handleBackgroundRefresh` now correctly invokes the static `scheduleBackgroundRefresh()` via `Self.`; removed the dead private free-function workaround at file scope.
- `DashboardView` stat card: replaced `LocalizedStringKey`-style `format:` interpolation (invalid in plain `String` context) with `Double.formatted(.number.precision(...))`.

### Changed

- Minimum deployment target raised from iOS 17 to iOS 18 to match the `Tab { }` API used by `ContentView`. Supported device set is unchanged (iPhone XS and later).

### Added

- `.github/workflows/build.yml` — CI workflow that builds the app for the iOS Simulator on push / pull request / release, and re-runs on every published release.

---

## [0.0.1] — 2026-04-14

### Added

- Initial project scaffold — all Swift source files, XcodeGen project spec, assets.
- **Multi-site model** — users can configure multiple MyPi server "sites" (e.g. home, office). Each site stores its base URL and API key in the Keychain.
- **Dashboard view** — stat cards (total queries, blocked, % blocked, domains on blocklist, cached, forwarded), per-instance systems table, query history chart (Swift Charts), top permitted/blocked domains, top clients.
- **Query log view** — paginated list with client, domain, status, and timestamp; filter by type (all / permitted / blocked / cached).
- **Onboarding sheet** — first-launch wizard for adding the first site (URL, API key, TLS options).
- **TLS security** — full validation by default; opt-in self-signed support with TOFU certificate pinning (SHA-256 fingerprint stored in Keychain).
- **Offline resilience** — disk cache of last successful response shown when network is unavailable; stale-data banner turns red after 2 missed poll cycles.
- **Network monitoring** — `NWPathMonitor` pauses polling when offline, resumes immediately on reconnect.
- **Background refresh** — `BGAppRefreshTask` keeps data reasonably fresh while app is backgrounded.
- **Settings** — per-site and global settings in an iOS Settings-style view (API key, hostname, TLS options, poll interval override).
- **Pushover notifications** — placeholder for future notification support (MVP uses server-side Pushover).
