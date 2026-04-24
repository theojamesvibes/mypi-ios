# Changelog

All notable changes to MyPi iOS are documented here.

---

## [0.1.3] — 2026-04-24

### Changed

- **Interactive sliding tab transitions** — Dashboard / Query Log / Settings now page horizontally with a real interactive swipe (half-swipe peek, spring snap) instead of the instant cross-fade the old `.sidebarAdaptable` `TabView` emitted on selection change. Backed by `TabView(.page(indexDisplayMode: .never))` (UIPageViewController under the hood), with a custom `BottomTabBar` replacing the chrome that `.page` style strips. Tap-to-switch animates with the same curve so taps and swipes feel identical.
- **Swipe enabled on iPad.** The previous iPhone-only swipe existed because `.sidebarAdaptable` put a sidebar on iPad and the sidebar's own horizontal drag conflicted. With `.page` style and the unified bottom bar there's no sidebar to fight, so iPad gets the same swipe behavior as iPhone. The old manual `DragGesture` in `ContentView` is removed — `UIPageViewController` handles paging natively, including interactive drag-from-mid-swipe cancellation.
- **User-facing error messages sanitized.** A new `ErrorMessage.userFacing(_:)` helper maps `URLError` codes to plain-English strings ("The device is offline", "Couldn't find the server — check the URL", etc.) and passes `APIError.detail` through unchanged. Replaces raw `error.localizedDescription` in the SetupSheet form, SiteFormView edit form, QueryLogViewModel error state, and the Dashboard cold-failure view. Error banners in the `SiteStatusBanner` and Settings Connection panel still use the richer underlying description because that's where diagnostic detail is valuable.

### Fixed

- **Orphaned cache files on site delete.** `SiteStore.delete(id:)` only cleaned up the three legacy `dashboard-*` cache keys. The disk cache expanded in 0.1.2 to include `-sync` and a set of `querylog-*` files per filter × time-range; those leaked after a site was removed. Added `DiskCache.deleteAll(withPrefix:)` that enumerates the cache directory and sweeps every file whose sanitized name starts with the given prefix, and `SiteStore.delete` now calls it for both `dashboard-{id}` and `querylog-{id}`.
- **Silent Keychain write failures.** `KeychainStore.saveAPIKey` / `saveCertFingerprint` used to ignore any `SecItemAdd` status other than success or `errSecMissingEntitlement`, so transient failures (e.g. first-unlock timing on a real device) could lose the secret without the UI ever knowing. Both now `throw KeychainError.writeFailed(OSStatus)` for unexpected statuses; SetupSheet and SiteFormView surface the error in the form's red banner and refuse to persist the `Site` record if its secrets couldn't be stored — no more un-authenticatable zombie sites.
- **Self-signed edit path skipped TOFU.** `SiteFormView.save` previously used the stored pin verbatim even after the user changed the URL or flipped "Allow self-signed certificate" back on, which would either accept a cert from the wrong host or cancel every request with a pin mismatch. The form now detects those changes (`retrustRequired`), warns the user inline, and routes Save through a fresh TOFU handshake (`runTOFU` → `CertTrustSheet` → `commitAfterTrust`). Turning self-signed off also clears any stale pin from the Keychain. The SetupSheet path already did this correctly on site creation; this closes the gap on edits.
- **NetworkMonitor launch-race.** `isConnected` defaulted to `true` before `NWPathMonitor`'s first callback fired, so a fetch that raced the first path update could slip past the offline guard. Now defaults to `false` — the monitor flips it to `true` in its path-update handler as soon as the device is confirmed online.

---

## [0.1.2] — 2026-04-21

### Added

- **Per-site view model cache** — Dashboard and Query Log view models now persist per site for the lifetime of the app. Switching sites reveals the other site's in-memory state instantly instead of tearing everything down and refetching. Each view is pinned with `.id(site.id)` so SwiftUI fires the correct `.onAppear` / `.onDisappear` pair when the active site changes, so the replaced poll task actually stops.
- **Expanded offline cache** — `loadCachedThenFetch()` now hydrates `history`, `top`, and `syncStatus` from disk in addition to `summary`, and Query Log persists the first page of queries / clients per filter+range. A cold launch against an unreachable site renders the last-known dashboard + query log instead of a spinning wheel.
- **`LastUpdatedLabel`** — always-visible "Updated X ago" label at the top of Dashboard and Query Log. Separate from the existing `StaleDataBanner`, which stays red-and-alarming for the >2× poll-interval case. Gives the user a neutral freshness signal on every pull-to-refresh.
- **`SiteStatusBanner`** — shown on Dashboard and Query Log when `connectionStates[activeSite]` is anything other than `.connected` / `.unknown` / `.probing`. Message reads e.g. "'Home' is currently unreachable — retrying every 60s". The retry cadence is the Dashboard VM's effective poll interval (including failure backoff), so the user sees the real next-attempt time as the backoff doubles.
- **`currentPollIntervalSeconds`** on `DashboardViewModel` — exposes the live `staleThresholdSeconds/2 × backoff` cadence so the banner and future diagnostics can read it without having to replicate the formula.

### Changed

- **Query Log search covers every field** — the search bar is now just labeled "Search" and filters locally across `domain`, `client_ip`, `client_name`, `status`, and `instance_name`. Replaces the previous server-side `?domain=` filter that only matched domains and left "Search domains" as the permanent placeholder. Local filtering means the search covers whatever pages have been loaded; the "load more" sentinel is hidden while a search is active because paginating against the server can't expand a local match set.
- **Query Log refresh failures don't replace the list** — a failed fetch with existing rows keeps the rows visible (and the pull-to-refresh gesture attached) instead of swapping in `ErrorView`. ErrorView only appears on a cold load with no cached data. Mirrors what the Dashboard already does and matches the user expectation that refresh on an unreachable site shouldn't destroy what's on screen.
- **`QueryEntry`, `ClientSummary`, `SyncStatus`, `InstanceSyncResult`** — promoted from `Decodable` to `Codable` so the disk cache can round-trip them.

### Fixed

- **"Spinning wheel on site switch"** — caused by (a) fresh VMs created on every `activeSiteChanged()` losing prior in-memory state, and (b) `loadCachedThenFetch()` only rehydrating `summary` from disk (not `history` / `top`). Now covered by the per-site VM cache + expanded hydration above.
- **"Pull-to-refresh shows orange-exclamation error, then Try Again works"** — the Dashboard already kept cached data on refresh failure, but with no summary cached yet the initial refresh fell through to `.failed` → `ErrorView`. With the expanded hydration this only happens on a first-ever visit with zero prior state.
- **False "unreachable" banner on a single transient failure** — `fetchAll()` used to call `appState.probe(site:)` on the first failure of a streak, which fired two more requests against a possibly-flaky path and flipped `connectionStates[site]` to `.error` / `.offline` / etc. A one-off pull-to-refresh hiccup (DNS blip, transient timeout) therefore painted the unreachable banner until the next successful poll ~60–120s later. Now: (a) `consecutiveFailures` must reach ≥ 2 before we touch the connection state at all, (b) the error is categorized inline from the caught exception — no extra request — and (c) the Dashboard / Query Log banner visibility is gated on `vm.isSiteUnreachable` (the VM-local failure streak) rather than raw connection state, so a stale `.error` left behind by the initial probe can't flash the banner either. `isStale` is also only flipped to `true` on failure if the data is genuinely older than the stale threshold.
- **Banner flash on site switch** — if the cached VM for a site already had `consecutiveFailures >= 2` from a previous session, the banner would paint for one frame on site switch before the fresh fetch landed and cleared it. `DashboardViewModel.start()` now opens a 5-second "startup grace" window during which `isSiteUnreachable` reports false regardless of the failure count, and the UI shows cached data silently while the refresh is in flight. If the site is genuinely still down after the grace + another confirmed failure, the banner appears normally.

---

## [0.1.1] — 2026-04-19

### Added

- **Swipe between tabs on iPhone** — horizontal swipe on the main view switches between Dashboard / Query Log / Settings. Skipped on iPad where the sidebar already handles horizontal drags.

### Changed

- **Server version refresh** — `/api/health` is now re-fetched on every Dashboard poll cycle (and every pull-to-refresh) instead of only at startup, so Settings reflects the live server version after the server is upgraded without needing an app restart. Also keeps the cached connection state fresh.
- **User-script sandboxing enabled** (`ENABLE_USER_SCRIPT_SANDBOXING = YES`). The app has no custom Run Script phases, so this is a no-op flip that silences the Xcode recommendation and pre-empts a future Xcode default change.

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
