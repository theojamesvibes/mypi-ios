# Changelog

All notable changes to MyPi iOS are documented here.

---

## [0.0.6] — 2026-04-18

### Added

- **Query Log legend** — new info button in the Query Log toolbar opens a sheet explaining what each status icon means (Permitted / Cached / Blocked) and which Pi-hole v6 status codes each one covers.
- **Per-site connection state** — every configured site is now probed with `/api/health` and `/api/stats/summary`. The Sites list shows a colored dot + status label per row (green when reachable and authenticated, red otherwise), and Settings has a dedicated Connection section with a Status field covering all observed states (Connecting / Connected / Unauthorized / Offline / TLS error / Error / Unknown).
- **Server Version field** in Settings — shows the real MyPi server version reported by `/api/health`, distinct from the connection Status.
- **"Today" time range** (midnight-to-now) on Dashboard and Query Log, and it is now the default. The full option set now mirrors the MyPi web dashboard: 15m, 1h, Today, 24h, 48h, 7d, 30d. Sub-hour / "today" ranges use the server's `since=` ISO parameter so the window is wall-clock-aligned instead of drifting.
- **Blocked stat card drill-down** — tapping the Blocked card on the Dashboard opens a list of distinct blocked domains with the latest block time and occurrence count per domain in the current range. Uses a single `/api/queries?blocked=true&page_size=500` call (already timestamp-DESC on the server) and dedupes client-side by keeping the first occurrence, so "latest per domain" falls out of the sort for free. A footer discloses when the 500-row window was truncated.
- **Unique Clients stat card drill-down** — tapping the Unique Clients card opens a list of every client in the range with total queries, blocked queries, and last-seen time. Backed by the server's `/api/queries/clients` aggregate endpoint.

### Changed

- **Setup sheet no longer requires a Name.** Leaving the field blank saves the site as "Home" — matches the field's placeholder and removes a pointless gate on the Save button.
- **TLS display in Settings** now shows the negotiated TLS protocol version (captured via `URLSessionTaskTransactionMetrics.negotiatedTLSProtocolVersion`) in green for CA-validated connections. Self-signed connections show the same version in yellow with a concise "Self-signed" or "Self-signed (pinned)" note below. Previously the row just read "Full validation" / "Self-signed".
- **Sites list rows** now lead with a status dot and show the connection label under the host, so users can see at a glance which configured sites are reachable.
- **APIClient** switched from `hours: Int` parameters to a shared `TimeRange` enum, so UI and wire format stay in sync across views.
- **Query history chart** replaced with a 100% stacked bar chart labeled "Query Composition" — blue permitted / red blocked segments always fill the vertical space so proportions remain readable on phone-sized layouts regardless of absolute query volume. The previous overlaid area-line rendering was hard to parse when blocked queries were a small fraction of the total.

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
