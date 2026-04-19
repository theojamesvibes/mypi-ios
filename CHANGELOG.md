# Changelog

All notable changes to MyPi iOS are documented here.

---

## [0.1.0] — 2026-04-19

First externally-published release. Consolidates every feature, UX pass, and fix from the internal 0.0.6 iteration plus the 0.0.6 → 0.1.0 review cycle (iPad-native Dashboard, cleaner chart + filter UX, proper sync-time source, code review cleanup). A single tagged + published release kicks the GitHub Actions build workflow.

### Added

- **iPad-native Dashboard** (`IPadDashboardView`) — 4-wide stat row, stacked Query Activity bar chart + Query Types donut side-by-side at matched heights, 3-column Top Permitted / Top Blocked / Top Clients row, Pi-hole Instances last. Mirrors the MyPi web dashboard layout.
- **Sidebar tab style on iPad** via `.tabViewStyle(.sidebarAdaptable)` — Dashboard / Query Log / Settings live in a left sidebar; iPhone keeps the bottom tab bar unchanged.
- **Site switcher menu** in the `.principal` toolbar slot of Dashboard, Query Log, and Settings. Renders as plain bold text with a single site; becomes a menu with a chevron when more than one site is configured.
- **Query Log** — new pill-chip controls above the list for Filter (All / Permitted / Blocked / **Unique Clients**) and Time Range; info button opens a legend sheet explaining each status icon; `.searchable` domain / client search (server-side `?domain=` for queries; client-side filter in Unique Clients mode).
- **Unique Clients** view — when the Filter is set to Unique Clients the list switches to per-client rows (name, IP, total queries, blocked count, last seen) backed by the server's `/api/queries/clients` aggregate endpoint.
- **Per-site connection probing** — every configured site is probed with `/api/health` + `/api/stats/summary` on appear and on pull-to-refresh. Sites list shows a colored dot + connection-state label per row (Connected / Unauthorized / Offline / TLS error / Error / Unknown). Settings toolbar exposes a Manage Sites screen; SiteFormView has an explicit Delete Site button with a confirmation dialog.
- **Dedicated Connection section in Settings** — Site URL above Status (color-coded dot + label covering every state), Server Version from `/api/health`, negotiated TLS version (green for CA-validated, yellow + "Self-signed (pinned)" note for self-signed trust).
- **Shared `TimeRange` enum** mirroring the MyPi web dashboard: 15m, 1h, **Today**, 24h, 48h, 7d, 30d. Today is the default. Sub-hour / Today ranges use the server's `since=` ISO parameter so the window is wall-clock-aligned.
- **"Synced X ago"** indicator on each Pi-hole instance row, sourced from `/api/sync/status` (the hourly query-log sync) rather than the minute-by-minute stats poll. Per-instance failure turns the row red with "Sync failed X ago".
- **App icon** — shield-check matching the MyPi web favicon.

### Changed

- **Setup sheet** — blank Name now defaults to "Home" instead of blocking Save. Self-signed TOFU path runs `health()` once instead of twice.
- **Date parsing** — `APIClient` JSON decoder uses a custom `dateDecodingStrategy` trying four shapes (ISO8601 with/without fractional seconds, naive with/without). `HistoryBucket.timestamp`, `QueryEntry.timestamp`, `ClientSummary.lastSeen`, `InstanceSummary.lastSeenAt` are now `Date` / `Date?` decoded directly. Fixes the "2,025 yrs, 3 mths ago" relative-time bug from FastAPI's microsecond-precision timestamps.
- **Query Log refresh** no longer clears the list before fetching — keeps the List mounted during async fetch so the pull-to-refresh gesture stays attached and "Something went wrong" doesn't flash.
- **Query Log filter** — fixed a no-op: server takes `blocked=bool`, not `query_type=`.
- **Pi-hole instance status dot** — `status="online"` now renders green (was previously only `"enabled"`, so every real instance showed red).
- **Refresh cadence** — background `BGAppRefreshTask` plumbing removed. Dashboard polls every ~60s while in the foreground and refreshes on scene-phase `.active` (with a 5-second debounce against triple-firing).
- **Dashboard layout stability** — `StatCardView` pinned to `minHeight: 96` so cards stop resizing with value length; `QueryActivityChart` takes the selected `TimeRange` as an explicit x-axis domain so a single-bucket day (e.g. just after midnight) doesn't reshape the card.

### Fixed

- **URLSession leak** — `APIClient` now invalidates its session in `deinit`; previously every replaced site client leaked its `URLSession` + `TLSDelegate` pair because `URLSession` retains its delegate strongly until invalidated.
- **Dashboard poll retain cycle** — the poll `Task` now captures `self` weakly and the VM cancels it in `deinit`, so switching sites while Dashboard is visible no longer leaks the old VM + its polling task.
- **Foreground double-fetch** — `fetchAll()` guards against triggering within 5 seconds of the previous successful fetch, so scenePhase → poll-tick → tab-re-`onAppear` can't stack three overlapping fetch cycles.
- **Failure backoff** — after N consecutive failed fetches the poll interval doubles (capped at 16×) instead of hammering a down server at 4 req/min. Resets on first success. Also de-duped the per-failure site probe to only fire on the first failure of a streak.
- **Disk-cache leak on site delete** — `SiteStore.delete` now removes the cached summary / history / top files for the removed site.
- **Keychain fallback over-broad** — the `UserDefaults` fallback now only triggers on `errSecMissingEntitlement` (unsigned simulator builds) instead of any `SecItemAdd` failure.
- **Dead code removed** — unused `APIClient.blockedQueries`, `KeychainStore.certFingerprint(for:)` getter, `StatCardView.showsDisclosure`; legacy `SiteListView` that stood alone as a tab was deleted when Sites moved into Settings; `QueryHistoryChart` and `DNSQueriesOverTimeChart` collapsed into the shared `QueryActivityChart`.

### Security

- Review sweep confirmed zero telemetry / analytics SDKs, zero credential logging, TLS pinning cannot be bypassed from the UI, and the API key is only transmitted via the `X-API-Key` header.

---

## [0.0.5] — 2026-04-18

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
