# Changelog

All notable changes to MyPi iOS are documented here.

---

## [0.2.1] — 2026-04-24

### Fixed

- **Main-only iOS Sites against multi-site MyPi servers were showing every site's Pi-hole instances mixed together.** The `/api/stats/summary` legacy alias is implemented server-side as cross-site aggregation (`site_id=None → all active instances across every site`), not Main-only as the design doc had implied. So an iOS Site with `mypiSiteSlug = nil` against a multi-site server saw the aggregate, not Main's data.
  - **For new sites:** the SetupSheet's "Use Main only" choice now resolves Main from the discovered site list and stores its slug. Routing then goes through `/api/sites/{main-slug}/...`, which the server scopes correctly. The user's chosen server name stays clean (no `– Main` suffix) on this path so the switcher entry doesn't get visually heavier than it needs to be.
  - **For sites already on disk:** `AppState.init` kicks off a background pass after launch — for each non-demo site with no slug, it probes `/api/sites`; if the server returns ≥ 2 sites, it adopts Main's slug and name in place. One-time, transparent, runs through the existing `updateSite` path so the per-site `APIClient` and view models reset cleanly. Single-site / legacy / unreachable servers are left alone — the legacy alias is correct for them, and the migration is a no-op.

---

## [0.2.0] — 2026-04-24

First minor-version bump — adds support for the multi-site backend feature shipping in MyPi 1.11.

### Added

- **Multi-site backend support.** A single MyPi server can now host up to ten "backend sites," each with its own collection of Pi-hole instances. The iOS app understands this without changing how users think about its own site list — the existing iOS Site abstraction stays one-MyPi-server-per-entry, with two new optional fields (`mypiSiteSlug`, `mypiSiteName`) carrying the backend-site identity.
  - **Default behavior (no slug):** legacy un-prefixed routes (`/api/stats/summary`, etc.) — server resolves to its Main site automatically. Existing iOS Sites configured against a server that later upgrades to multi-site keep working with zero changes; they just see Main's data.
  - **Per-backend-site routing (with slug):** `APIClient` rewrites every site-scoped request to `/api/sites/{slug}/...`. `/api/health` and `/api/sites` stay server-global and aren't rewritten. URLSession follows the server's slug-history 301s automatically when a backend slug is renamed, so no client-side migration is needed.
- **`MyPiSitePicker` sheet** — three-way choice presented when the SetupSheet detects a multi-site server (≥ 2 entries from `GET /api/sites`):
  1. **Use Main only** (recommended default — saves with `mypiSiteSlug = nil`)
  2. **Pick one specific site** — saves with the chosen slug
  3. **Add all N sites** — creates one iOS Site per backend site, activates Main, leaves the rest secondary in `sortOrder`
  Single-site / legacy servers (`/api/sites` returns 404, empty array, or a single row) bypass the picker entirely — their setup flow is unchanged.
- **Discover Other Sites on This Server** action in `SiteFormView`. Re-fetches `/api/sites`, filters out backend sites already configured under the same URL, and presents `MyPiSitePicker` (with the Main-only option hidden) so users who originally chose Main can pull in siblings later. Failed fetches are interpreted as "single-site server" and surfaced as a soft note rather than an error.
- **Connection card → MyPi Site row** in Settings and SiteFormView's Server section, shown only when `mypiSiteSlug` is set. Displays the friendly name plus the slug in monospaced caption type. Site switcher entries created via the multi-site path are auto-named `"{server} – {backend site}"` so the dropdown is unambiguous on devices with both Main and a sibling configured.
- **`MyPiSite` model** — decoded shape of `GET /api/sites` (id, name, slug, isMain, isActive, sortOrder, instanceCount, activeInstanceCount, createdAt). Hashable + Identifiable for use in pickers.

### Changed

- **`Site.init(from:)`** decodes the new `mypiSiteSlug` / `mypiSiteName` fields with `decodeIfPresent`, so existing `sites.json` from 0.1.x keeps loading cleanly without a migration. Memberwise `init` adds the two as optional defaulted parameters.
- **`SiteFormView.commit`** now preserves `mypiSiteSlug` and `mypiSiteName` on edit, fixing the same drop-on-the-floor pattern that bit `isDemo` in 0.1.6.

### Server compatibility

- Built against MyPi `1.11.0-dev.x` (multi-site branch). Works against earlier server versions — `/api/sites` returns 404, the SetupSheet treats that as "legacy server, save normally," and every other API call uses the unchanged legacy path.

---

## [0.1.10] — 2026-04-24

### Added

- **Appearance preference (Light / Dark / System).** New `AppColorScheme` enum persisted via `@AppStorage("appColorScheme")`; `ContentView` reads it and applies `.preferredColorScheme(theme.colorScheme)` at the root so splash, sheets, and tab content all follow the choice. `AppSettingsView` gains an **Appearance** section with a Picker. `.system` returns `nil` from `colorScheme`, which means "defer to the OS" — the default behavior — and selecting Light or Dark forces the scheme across the whole hierarchy without individual views needing to know about it.
- **`docs/appstore-metadata.md`** — draft of every copy-paste field App Store Connect asks for on submission: name, subtitle, description, keywords, promotional text, review notes, App Privacy questionnaire answers, screenshots checklist, and a submission-day runbook. Ready to lift verbatim the moment the Developer Program activates.

---

## [0.1.9] — 2026-04-24

Response to the external Grok architecture + security audit of 0.1.6 (filed at [`docs/reviews/2026-04-24-grok-audit.md`](docs/reviews/2026-04-24-grok-audit.md) with per-recommendation disposition). No critical findings from that review; this release folds in the small-but-worth-it suggestions.

### Added

- **Re-pin Certificate** button on the Settings TLS row for self-signed sites. Reruns a one-shot TOFU handshake against the live server (temporary `APIClient` with `allowSelfSigned: true` and no pin, captures the presented leaf via `TLSDelegate.onUntrustedCertificate`), shows the new SHA-256 fingerprint in `CertTrustSheet`, and on explicit approval writes the new pin to Keychain via `AppState.updateSite`. Covers legitimate server-cert rotation without forcing a delete + re-add. Hidden on demo sites (no real cert to pin) and on sites that aren't self-signed.
- **Read-only API key hint** in the `SetupSheet` API Key section footer. Least-privilege nudge since the app only ever reads data — a read-only key is sufficient and limits blast radius if the key is disclosed.
- **README Security section** (distinct from Privacy) documenting Keychain scope + accessibility class, TOFU pin behavior, strict ATS, and the clean-on-delete guarantees. Linked to the Grok audit for anyone who wants the outside-review context.
- **`docs/reviews/2026-04-24-grok-audit.md`** — full audit text plus a per-recommendation "implemented / deferred / declined with reason" table.

### Fixed

- **iPad Query Types donut legend wraps to two lines.** `Forwarded`, `Cached`, and `Blocked` were pushing the percent column and wrapping the label onto a second line because the legend fought a `Spacer()` for width in the ~130pt iPad card slot. Switched to a two-column `Grid` with `lineLimit(1)` + `minimumScaleFactor(0.85)` on the label: percents line up cleanly on the right, labels stay single-line even on the narrowest card size, and at worst the label shrinks 15% which is imperceptible.

---

## [0.1.8] — 2026-04-24

### Added

- **`DemoModeBanner`** — visible indicator shown above every tab's content when the active site is a demo site. Reads "Demo Mode · Showing sample data · Close the app to exit." Wired into Dashboard (phone + iPad layouts), Query Log, and a top-of-form section in Settings. Keeps demo state unambiguous and documents the exit path.
- **Demo mode is session-scoped** — `AppState.init` now sweeps every `isDemo` site on cold launch (via `SiteStore.delete`, which already handles the Keychain + disk-cache cleanup from 0.1.3). Force-quitting the app from the app switcher is the "exit demo mode" affordance — on next launch the demo site is gone and, if it was the only site, the SetupSheet reappears with **Try Demo Mode** ready to go again. Backgrounding and returning does *not* reset — `AppState` stays alive in that case, so a background → foreground cycle keeps you in demo mode as expected.

### Changed

- **`Try Demo Mode` activates the new site.** `AppState.addSite` only auto-selects when no site was previously active; `SetupSheet.addDemoSite` now also sets `activeSiteIndex` to the demo site so a device with existing real sites lands directly on the demo rather than having it appear silently at the end of the site list.

---

## [0.1.7] — 2026-04-24

### Fixed

- **Demo mode actually uses the bundled fixtures now.** `SiteStore.save` reconstructed every incoming `Site` into a new struct to stamp `sortOrder`, but its constructor call didn't pass `isDemo`, so the flag silently reverted to `false` before hitting disk — then `APIClient` saw a "real" site and tried to reach `demo.mypi.invalid` over the network. `SiteStore.delete`'s renumber pass had the same drop-on-the-floor bug, and `SiteFormView.commit` would flip a demo site to "real" on any edit. All three paths now mutate the existing `Site` (setting just the fields that need changing) instead of reconstructing it, which is future-proof against every subsequent new field.
- **Self-heal for already-borked demo sites on disk.** Anyone who tapped **Try Demo Mode** on 0.1.6 has a persisted site with `isDemo: false` and `baseURL: https://demo.mypi.invalid`. `Site.init(from:)` now flips `isDemo` back to `true` on load for any site whose host matches `demo.mypi.invalid` — the `.invalid` TLD is reserved by RFC 2606 and can never resolve on the real internet, so this is safe to coerce. No manual delete + re-add required; just update and the demo site starts working.

---

## [0.1.6] — 2026-04-24

App Store submission prep. Everything that can land pre-approval so the
repo is shovel-ready once the Developer Program activates.

### Added

- **Splash screen** on initial launch — `SplashView` shows the app logo plus "MyPi Companion v{version}" centered, held for 2 seconds over a matched background color, then fades to the main UI. `@State` in `ContentView` means once-per-launch: backgrounding and returning keeps it dismissed.
- **Branded launch screen.** `UILaunchScreen` now references a new `LaunchBackground` color asset (white light / black dark) instead of emitting a default gray flash. Same canvas as `SplashView`, so the OS → SwiftUI handoff is seamless.
- **`AppLogo` image asset** (reuses the 1024×1024 app icon) for use in `SplashView` and anywhere else the logo needs to appear in-app.
- **Demo mode on new install.** SetupSheet gets a "Try Demo Mode" button that creates a synthetic site with the RFC 2606 invalid URL `https://demo.mypi.invalid` and `isDemo = true`. The new `DemoData` module provides Pi-hole-shaped fixtures for every endpoint (summary / history / top / queries / clients / sync / health), scaled roughly by `TimeRange` so the chart still looks alive when users switch ranges. `APIClient` short-circuits to `DemoData` when `site.isDemo`; no network, no Keychain, no API key. Primary use cases: App Store reviewers who don't have a MyPi server, and users exploring the app before committing to a real setup.
- **Privacy policy** at [`docs/privacy.md`](docs/privacy.md). Formatted for GitHub Pages deployment from the `/docs` folder, hosted at `https://theojamesvibes.github.io/mypi-ios/privacy` once Pages is enabled.
- **Archive workflow** at `.github/workflows/archive.yml`. Manually dispatched, imports a distribution cert + provisioning profile from secrets, builds the Release archive, exports an IPA with `method = app-store-connect`, and uploads via `xcrun altool` with an App Store Connect API key. All secret names are documented at the top of the file; the workflow doesn't actually run until they're populated post-approval.
- **`Site.isDemo: Bool`** field with a backward-compatible `init(from decoder:)` that decodes `isDemo` if present and defaults to `false` otherwise — existing `sites.json` from 0.1.5 and earlier keeps decoding cleanly without a one-shot migration.

### Changed

- **`ITSAppUsesNonExemptEncryption = false`** in `Info.plist` (via `project.yml` `info.properties`). The app only uses HTTPS through `URLSession` (standard TLS, no custom cryptography), which qualifies as exempt. Declaring this up-front skips the App Store Connect export-compliance questionnaire on every upload.
- **Network / Keychain guards skipped for demo sites.** `AppState.probe(site:)` and `DashboardViewModel.fetchAll` both pass straight through the connectivity check when `site.isDemo`, otherwise a device going offline would park the demo site in `.offline` even though its "server" is always local.
- **Splash z-indexed over the root** via `ZStack` — the sites-empty onboarding sheet is still auto-presented underneath, so when splash fades the user lands on the setup sheet with `Try Demo Mode` visible immediately.

---

## [0.1.5] — 2026-04-24

### Fixed

- **Settings tab transition is finally consistent** with Dashboard ↔ Query Log. The 0.1.3 attempt (switching to `TabView(.page)`) slid smoothly for ScrollView/List-backed tabs but snapped instantly into the Form-backed Settings tab — SwiftUI's `TabView(.page)` animation dispatch interacts inconsistently with `Form` children regardless of how the selection mutation is wrapped (verified after 0.1.4's tap-animation + probe-gating fixes didn't land). 0.1.5 replaces SwiftUI's page-style `TabView` with a `UIPageViewController`-backed `PagingTabContainer` (`UIViewControllerRepresentable`). Every tab gets the same native spring slide on both swipe and tap because `setViewControllers(_:direction:animated:true)` is now the only code path that moves between tabs. The wrapper caches `UIHostingController`s by index (so UIPageViewController's `viewControllerBefore/After` callbacks return stable neighbours) and pushes fresh SwiftUI state into each cached host on every parent re-evaluation so site switches propagate without leaking stale VMs into the paged children.

---

## [0.1.4] — 2026-04-24

### Added

- **`PrivacyInfo.xcprivacy`** privacy manifest at the app bundle root. Declares `NSPrivacyTracking = false`, an empty `NSPrivacyTrackingDomains`, and an empty `NSPrivacyCollectedDataTypes` (nothing leaves the device). Also declares the required-reason usage of `UserDefaults` (category `NSPrivacyAccessedAPICategoryUserDefaults`, reason **CA92.1** — "access user defaults to read or write information that is only accessible to the app itself") which covers the `KeychainStore` UserDefaults fallback. Sets the submission up to pass Apple's automated manifest check.
- **`SitesLoadErrorView`** — dedicated recovery screen shown when `SiteStore.load()` throws at launch. Previously a corrupted `sites.json` silently returned `[]` and dropped the user into the onboarding flow, which felt like their sites had vanished and invited them to overwrite the salvageable file. The screen explains what happened and tells them the recovery path (delete + reinstall) without offering a destructive one-tap "reset" that could eat recoverable data.

### Changed

- **`SiteStore.load()` now throws** on decode failure. Missing file is still the fresh-install happy path (returns `[]` cleanly). Callers that write to the file (`save` / `delete`) use a private `loadQuiet()` that falls back to `[]` on error — rewriting from scratch is still worse than propagating a mid-flow error, so the recovery is "start from empty" only in the mutation path; the read path in `AppState.init` is the one that surfaces the error to the user via `loadError`.

### Fixed

- **Settings tab transition no longer flashes abruptly.** Two causes: (1) the `withAnimation(.easeInOut(duration: 0.28))` wrapper on bottom-tab taps was forcing SwiftUI to cross-fade Settings (whose `Form` root doesn't slide as cleanly as the ScrollView roots under Dashboard / Query Log), fighting `TabView(.page)`'s native spring; (2) `AppSettingsView`'s `.task { probe(site:) }` fired on every tab re-appear, flipping `connectionStates[site]` to `.probing` and then back to `.connected` mid-transition, which re-rendered the Form while it was still sliding in. The tap handler now mutates `selected` directly and lets the `.page` style's spring drive the slide; Settings now tracks `lastProbedSiteID` so the on-appear probe only runs once per active-site change, with pull-to-refresh still available for an explicit fresh probe.

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
