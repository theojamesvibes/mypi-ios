# Changelog

All notable changes to MyPi iOS are documented here.

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
