# App Store Connect submission metadata — draft

Everything App Store Connect asks for on submission day, pre-filled so you can copy-paste without writing under pressure. Adjust anything that's wrong before submitting.

Version drafted against: **0.1.10**. Character counts are Apple's hard limits, not soft guidance.

---

## App Information (stable across versions)

**Name** (30 chars max):
```
MyPi Companion
```
*14 chars.*

**Subtitle** (30 chars max):
```
Pi-hole aggregator dashboard
```
*28 chars. Appears under the name on the product page.*

**Bundle ID**: `net.myssdomain.mypi` (already registered in `project.yml`).

**SKU** (internal, not user-visible): `mypi-ios-001` — anything unique within your developer account.

**Primary Language**: English (U.S.)

**Primary Category**: `Utilities`
**Secondary Category**: `Developer Tools`
*Developer Tools is a defensible secondary because MyPi is network-infrastructure-adjacent. If App Review pushes back, fall back to `Productivity`.*

**Content Rights**: "No, it does not contain, show, or access third-party content." (MyPi only shows the user's own server's data.)

**Age Rating**: **4+**. Run through Apple's questionnaire — every checkbox should be "None" because the app shows only DNS statistics the user's own server observed.

---

## Contact Information

App Store Connect asks for a contact for the review team and for user support. Both can be the same.

- **Review contact email**: `claude@myssdomain.net` *(swap if you prefer a different address)*
- **Review contact phone**: *(App Store Connect requires one — use any number you're willing to take a call on.)*

**Support URL**: `https://github.com/theojamesvibes/mypi-ios/issues`
**Marketing URL** (optional): `https://github.com/theojamesvibes/mypi-ios`
**Privacy Policy URL**: `https://theojamesvibes.github.io/mypi-ios/privacy`

---

## Copyright

```
© 2026 theojamesvibes
```
*Adjust to the legal name / handle you want displayed on the product page.*

---

## Promotional Text (170 chars max, editable without resubmission)

```
Monitor your Pi-hole aggregations at a glance. Dashboard, query log, and multi-site switching — fully local, nothing phones home.
```
*130 chars. Safe to update between releases since it doesn't require a new binary.*

---

## Description (4000 chars max)

```
MyPi Companion is a native iOS and iPadOS client for MyPi — a self-hosted Pi-hole aggregation server that unifies every Pi-hole you run on your home or office network. If you have more than one Pi-hole instance, MyPi lets you see total query volume, blocks, and per-client activity across all of them in one place. This app is the mobile view.

FEATURES

• Dashboard at a glance — total queries, blocked, cached, forwarded, unique clients, percent blocked. Tap the time-range picker (15 minutes, 1 hour, Today, 24 hours, 48 hours, 7 days, 30 days) to rescope every card, chart, and list on the fly.

• Activity chart with stacked permitted / blocked bars. Full bucket-accurate scale even when a range has only a few minutes of data.

• Top permitted domains, top blocked domains, and top clients — full ten-row lists.

• Query Log with full-text search across domain, client IP, client name, status, and Pi-hole instance name. Filter by All, Permitted, Blocked, or Unique Clients (aggregated client view). Pull-to-refresh keeps the list live.

• Multi-site support. Configure every MyPi aggregator you run — home, office, lab, vacation router. Swipe horizontally to flip between them; each site's dashboard state is cached independently so switching is instant.

• TLS pinning and full trust. Default is strict OS certificate validation. Self-signed servers are opt-in per site with trust-on-first-use SHA-256 fingerprint pinning — once a certificate is pinned, nothing in the UI can bypass it. Legitimate cert rotation goes through an explicit Re-pin Certificate action in Settings.

• Offline-resilient. Every screen shows cached data immediately while fresh data loads in the background; a banner appears only when the data is actually past the server's stale threshold, not on every brief network blip.

• Light, Dark, and System appearance modes.

• Demo mode. Tap Try Demo Mode on the setup screen to explore the full app with synthetic Pi-hole data — every chart, filter, and list works without any server configured. Close the app to exit.

PRIVACY

• No analytics. No telemetry. No third-party SDKs. No advertising identifier access.

• API keys and pinned TLS certificate fingerprints live only in the iOS Keychain, scoped to this app's bundle with no sharing groups.

• Dashboard responses and query log entries are cached in the standard Caches directory so the app is usable offline. They are deleted when you delete the site. Nothing is ever sent off-device — the app only talks to the MyPi server URL(s) you configure.

• Full privacy policy: https://theojamesvibes.github.io/mypi-ios/privacy

REQUIREMENTS

• A running MyPi server — see https://github.com/theojamesvibes/mypi for the server itself. (The app's README at https://github.com/theojamesvibes/mypi-ios walks you through setup.)

• iOS 18 or iPadOS 18, or later.

MyPi Companion and the MyPi server are both open source. Source for this app: https://github.com/theojamesvibes/mypi-ios.
```
*~2500 chars. Rich enough to sell the app without being bloat.*

---

## Keywords (100 chars max, comma-separated, no spaces around commas)

```
pi-hole,dns,network,monitoring,dashboard,adblock,homelab,selfhosted,privacy,pihole
```
*82 chars. Apple matches on these for search but users don't see them. Name + subtitle are weighted more heavily in search, which is why "Pi-hole" appears in the subtitle.*

---

## "What's New in This Version" (per-release release notes, 4000 chars)

Drafted for the first public release. Update per version.

```
First public release of MyPi Companion. Full client coverage of the MyPi aggregation API:

• Dashboard, Query Log, and per-site Settings.
• Multi-site support with horizontal swipe to switch.
• TLS pinning and strict ATS.
• Light / Dark / System appearance modes.
• Demo mode for exploring the app without a server.

See the GitHub repository for source, full changelog, and server setup.
```

---

## Review Notes (shown only to App Review, never to users)

```
MyPi Companion is a client for a self-hosted server (MyPi, https://github.com/theojamesvibes/mypi) that aggregates statistics from one or more Pi-hole DNS servers. Most users will point this app at their own MyPi instance on first launch, but since reviewers won't have one, a full end-to-end test path is built in.

TO TEST THE APP:
1. Launch the app. The setup sheet appears automatically on first run.
2. Tap "Try Demo Mode" in the Demo Mode section at the bottom of the sheet.
3. The app creates a sample site populated with synthetic Pi-hole data. Every feature — dashboard, charts, query log with search and filtering, unique clients drill-down, site switching, settings — works fully against this sample data. No external server is ever contacted; fixtures are bundled into the app.

TO EXIT DEMO MODE:
Swipe up from the bottom of the screen to open the app switcher, then swipe up on the MyPi Companion card to close the app. On next launch the demo site is removed automatically and the setup sheet reappears with Try Demo Mode available again.

This app does not collect data. It has no analytics, no telemetry, no third-party SDKs. The only destinations it contacts at runtime are the MyPi server URLs a user configures. With Demo Mode selected, even that traffic is zero — the entire dashboard renders from bundled sample data.

Source code and privacy policy:
• Source: https://github.com/theojamesvibes/mypi-ios
• Privacy: https://theojamesvibes.github.io/mypi-ios/privacy
• External security audit (Grok, 2026-04-24): https://github.com/theojamesvibes/mypi-ios/blob/main/docs/reviews/2026-04-24-grok-audit.md

Thank you for reviewing.
```

---

## App Privacy questionnaire answers

App Store Connect asks these separately from the `PrivacyInfo.xcprivacy` manifest. The manifest is read by Apple's tooling at upload; the questionnaire is a human declaration on the product page. Answers must be consistent with each other.

**Do you or your third-party partners collect data from this app?** — **No**

*Apple's definition of "collect" is "data leaves the device and is received by the developer or a third party." Everything this app stores lives on the user's device and is deleted on site deletion. Caching dashboard data locally isn't "collecting" under this definition.*

Because the answer is No to the gate question, every per-category question is skipped. For reference, if Apple ever asks per-category:

| Category | Collect? | Notes |
|---|---|---|
| Contact Info (name, email, address, phone) | No | — |
| Health & Fitness | No | — |
| Financial Info | No | — |
| Location (precise / coarse) | No | — |
| Sensitive Info | No | — |
| Contacts | No | — |
| User Content (photos, audio, customer support, etc.) | No | — |
| Browsing History | No | The app shows DNS query history from the user's own Pi-hole, cached locally. Never transmitted anywhere. |
| Search History | No | — |
| Identifiers (User ID, Device ID, etc.) | No | — |
| Purchases | No | — |
| Usage Data (product interaction, ad data) | No | — |
| Diagnostics (crash, performance) | No | No crash reporter installed. |
| Other Data | No | — |

**Does your app use third-party SDKs?** — **No.**

**Does your app use tracking?** — **No.** `NSPrivacyTracking = false` is declared in `PrivacyInfo.xcprivacy` and `NSPrivacyTrackingDomains = []`.

---

## Export compliance

Already declared in code: `ITSAppUsesNonExemptEncryption = false` in `Info.plist` (added 0.1.6).

App Store Connect will not re-prompt on upload.

---

## Screenshots checklist

Apple requires the "highest-resolution size for each supported device family" at minimum. For iOS 18 that's:

- **iPhone 6.9"** (iPhone 16 Pro Max / 17 Pro Max) — 1320 × 2868 portrait, 2868 × 1320 landscape. 3-10 per orientation.
- **iPad 13"** (iPad Pro 13" M4 / M5) — 2064 × 2752 portrait, 2752 × 2064 landscape. 3-10 per orientation.

*The app supports portrait and landscape on both. Apple lets you skip landscape if the app supports portrait only, but we support both, so they'll want at least a portrait set.*

Recommended shot list (reuses demo mode for deterministic framing):

1. **Dashboard** with demo data — shows stat cards, activity chart, top lists in one frame.
2. **Query Log** with filter set to Blocked — one filter chip visible + a populated list.
3. **Unique Clients** — drill-down showing per-client row breakdown.
4. **Multi-site switcher menu open** — optional but shows off multi-site support.
5. **Settings → Connection** — shows TLS version, Status chip, Re-pin Certificate row.

Generate via **Simulator → File → New Screenshot** (⌘+S) or `xcrun simctl io booted screenshot out.png`.

---

## Submission-day checklist

1. Populate the seven `.github/workflows/archive.yml` secrets in repo Settings → Secrets.
2. Stamp `DEVELOPMENT_TEAM` into `project.yml` (or let the workflow's `sed` step do it).
3. Run **Archive** workflow manually with `upload: true`.
4. Wait for Apple's processing (~5–15 min).
5. In App Store Connect: paste this document's fields in, attach screenshots, submit the App Privacy form, submit for review.
6. Respond to any reviewer questions within 24h — they're usually fast.

Typical first-review time for a utility app with clean manifests: 24–72 hours.
