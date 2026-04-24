# MyPi iOS

Native iOS/iPadOS companion app for [MyPi](https://github.com/theojamesvibes/mypi) — a self-hosted Pi-hole aggregation dashboard.

## Features

- Dashboard with live stat cards (tap **Blocked** or **Unique Clients** to drill into per-domain / per-client detail), 100% stacked query-composition chart, top domains/clients, and per-instance systems table
- Shared time-range picker on Dashboard and Query Log: **15m, 1h, Today, 24h, 48h, 7d, 30d** — mirrors the MyPi web dashboard, defaults to **Today**
- Query log with filtering (all / permitted / blocked / cached) and an in-app legend for what each status icon means; the search bar filters locally across domain, client IP, client name, status, and instance name
- Multi-site support — manage multiple MyPi servers (e.g. home + office) with per-site connection indicators (green = reachable and authenticated, red = not). Switching sites is instant — Dashboard and Query Log view models are cached per site so the prior state is still on screen
- Always-visible "Updated X ago" label at the top of Dashboard and Query Log; a banner appears when the active site is unreachable, showing the retry cadence
- Swipe left/right (iPhone and iPad) to move between Dashboard / Query Log / Settings — interactive page slide with tap-to-switch on the bottom tab bar
- Secure Keychain storage for API keys and TLS certificate fingerprints
- Full TLS validation by default; opt-in self-signed support with TOFU cert pinning; Settings shows the negotiated TLS protocol version
- Connection Status and Server Version surfaced in Settings, with every observable state (Connecting / Connected / Unauthorized / Offline / TLS error / Error)
- Offline-resilient: cached data shown when connectivity is lost, stale banner after 2 missed syncs
- Background refresh via `BGAppRefreshTask`

## Requirements

- iOS 18+ / iPadOS 18+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A running [MyPi](https://github.com/theojamesvibes/mypi) server (v1.4.6+)

## Getting Started

```bash
brew install xcodegen
git clone https://github.com/theojamesvibes/mypi-ios.git
cd mypi-ios
xcodegen generate
open MyPi.xcodeproj
```

Then select your target device or simulator and press Run.

### Command-line build (optional)

Xcode's Run button handles signing automatically. If you prefer to build from the terminal for the simulator, use ad-hoc signing — a fully unsigned build fails at runtime because the Keychain rejects API-key writes without entitlements:

```bash
xcodebuild -project MyPi.xcodeproj -scheme MyPi -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES \
  build
```

On real devices a fully signed build (with a proper Apple Developer Team) uses the Keychain natively; the `UserDefaults` fallback in `KeychainStore` only kicks in for unsigned builds and is never touched on a signed install.

## Configuration

On first launch the app presents a setup sheet. Enter:

- **Server URL** — e.g. `https://mypi.home.example.com` or `https://192.168.1.10:8080`
- **API Key** — generate one in MyPi → Settings → API Keys
- **Allow self-signed certificates** — enable if your server uses a self-signed or internal CA cert (prompts to trust and pin the cert on first connection)

Additional sites can be added via the Sites button in the navigation bar.

## Project Structure

```
MyPi/
  App/               — App entry point and global state
  Models/            — Data models (Site, API response types, cache)
  Networking/        — URLSession client, TLS delegate, network monitor
  Storage/           — Keychain, site store, disk cache
  ViewModels/        — Observable ViewModels (Dashboard, QueryLog)
  Views/
    Root/            — ContentView, top-level navigation
    Onboarding/      — First-launch setup and cert-trust sheets
    Dashboard/       — Stat cards, chart, systems table, top lists
    QueryLog/        — Query list, row, and filter views
    Sites/           — Site list and site form
    Settings/        — App settings view
    Common/          — Shared error and loading views
```

## Security

- **Secrets in the iOS Keychain only.** Per-site API keys and pinned TLS certificate fingerprints are stored with `kSecAttrAccessibleWhenUnlocked` and scoped to this bundle (no sharing groups). Never written to `sites.json`, never logged. On unsigned simulator builds a UserDefaults fallback is used because the simulator Keychain rejects writes without an entitlement; signed device builds always use the Keychain proper.
- **TLS defaults to full OS trust.** App Transport Security is strict (`NSAllowsArbitraryLoads = false`). Plain HTTP is rejected by iOS itself, not just by the app.
- **Self-signed servers are opt-in per site, with TOFU cert pinning.** When "Allow self-signed" is on, the app pins the first leaf certificate it sees (SHA-256 fingerprint stored in Keychain) and rejects every subsequent certificate whose fingerprint doesn't match. There's no UI bypass once a cert is pinned. Legitimate rotation is handled by the **Re-pin Certificate** button in Settings, which reruns the TOFU handshake explicitly.
- **API key in the `X-API-Key` header only.** No cookies, no bearer tokens, no URL query-string auth.
- **Site deletion is clean.** Removing a site wipes its Keychain entries (API key + pinned fingerprint) and every per-site disk-cache file via prefix match.
- **No third-party SDKs.** No analytics, no telemetry, no crash reporter, no advertising identifier access.

**External audit.** v0.1.6 was reviewed externally by Grok on 2026-04-24 — no critical or high-severity findings. Full audit and per-recommendation disposition: [`docs/reviews/2026-04-24-grok-audit.md`](docs/reviews/2026-04-24-grok-audit.md).

## Privacy

What MyPi stores on the device:

- **Keychain** (`kSecAttrAccessibleWhenUnlocked`, bundle-scoped, no sharing groups): per-site API keys and pinned TLS certificate fingerprints. On unsigned simulator builds a UserDefaults fallback is used because the simulator Keychain rejects writes without an entitlement; real device installs always use the Keychain proper.
- **`~/Library/Caches/net.myssdomain.mypi/`** (standard iOS file protection): the most recent Dashboard summary / history / top / sync payload and the first page of Query Log results per site. This includes the client IPs and domain names visible to your Pi-hole server. Cache files are cleared when the site is deleted.
- **`Documents/sites.json`**: site metadata — display name, base URL, self-signed flag, sort order. API keys are never written here.

What MyPi does **not** do: no analytics, no telemetry, no third-party SDKs, no crash reporters. TLS pinning cannot be bypassed from the UI once a cert is pinned, and the API key is only ever transmitted via the `X-API-Key` request header.

## Version

Current release: **0.1.9**

## Privacy Policy

Live at <https://theojamesvibes.github.io/mypi-ios/privacy> once GitHub Pages is enabled on the `/docs` folder (Settings → Pages → deploy from branch `main`, folder `/docs`). Source in [`docs/privacy.md`](docs/privacy.md).
