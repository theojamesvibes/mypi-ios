# MyPi Companion — Privacy Policy

_Last updated: 2026-04-24_

MyPi Companion is an iOS/iPadOS client for [MyPi](https://github.com/theojamesvibes/mypi), a self-hosted Pi-hole aggregation server. This document describes what the app stores, what it doesn't, and why.

## Summary

- **The app does not collect, transmit, or sell any personal information.**
- **No analytics, no telemetry, no third-party SDKs, no advertising, no tracking.**
- Everything the app stores is kept on the device. Nothing is sent anywhere except to the MyPi server _you_ configure.

## What's stored on the device

**Keychain** (iOS Keychain, `kSecAttrAccessibleWhenUnlocked`, scoped to this app bundle):

- API keys you enter for each configured MyPi server.
- SHA-256 fingerprints of TLS certificates you've chosen to pin for self-signed servers.

**Caches directory** (`~/Library/Caches/net.myssdomain.mypi/`, standard iOS file protection):

- The most recent Dashboard response (summary, history, top-N, sync status) for each configured site.
- The first page of Query Log results for each site/filter/time-range combination.
- These caches include the client IP addresses and domain names that your Pi-hole server observed. They never leave the device. They're deleted when you delete the corresponding site, and iOS itself may evict them under storage pressure.

**Documents directory** (`Documents/sites.json`):

- Per-site metadata: display name, base URL, self-signed flag, sort order. API keys are **not** written here — those live in the Keychain.

**UserDefaults** (fallback only):

- On simulator / unsigned builds the iOS Keychain rejects writes without an entitlement, so the app falls back to `UserDefaults` for API keys and cert fingerprints to stay usable for local testing. On properly signed device installs this fallback is never used.

## Network traffic

MyPi Companion talks to one destination: the MyPi server URL(s) you configure. Every request goes over HTTPS, with the API key attached in the `X-API-Key` header. `Info.plist` enforces App Transport Security (`NSAllowsArbitraryLoads = false`), so plain HTTP is rejected by iOS.

Self-signed certificates are opt-in per site; when enabled, the app pins the first certificate it sees (trust-on-first-use) and rejects any subsequent certificate whose SHA-256 fingerprint doesn't match the pin.

## Data sharing

None. The app has no third-party SDKs, no analytics framework, no crash reporter, no advertising identifier access. The only party that receives any data is the MyPi server you've configured, which you operate yourself.

## Children's privacy

MyPi Companion is not directed at children and does not knowingly collect data from anyone — adult or otherwise.

## Changes

If this policy is ever updated, the new version will appear at the same URL with a new "Last updated" date.

## Contact

Questions or concerns can be filed as issues on the [GitHub repository](https://github.com/theojamesvibes/mypi-ios/issues).
