# MyPi iOS

Native iOS/iPadOS companion app for [MyPi](https://github.com/theojamesvibes/mypi) — a self-hosted Pi-hole aggregation dashboard.

## Features

- Dashboard with live stat cards, query history chart, top domains/clients, and per-instance systems table
- Query log with filtering (all / permitted / blocked / cached)
- Multi-site support — manage multiple MyPi servers (e.g. home + office)
- Secure Keychain storage for API keys and TLS certificate fingerprints
- Full TLS validation by default; opt-in self-signed support with TOFU cert pinning
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

## Version

Current release: **0.0.4**
