# App Store submission checklist

End-to-end checklist for getting **MyPi Companion** from the current state (code at `v0.2.2`, Apple Developer account just approved) into App Review.

The text content of every App Store Connect field is in [`appstore-metadata.md`](appstore-metadata.md) — this doc is the ordered runbook; that one is the copy-paste source.

---

## 1. Apple Developer portal setup

One-time. Do these in [developer.apple.com](https://developer.apple.com) → Account.

- [ ] **App ID** — Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App → **Explicit**, description `MyPi Companion`, Bundle ID `net.myssdomain.mypi`. No capabilities to enable (no push, no iCloud, no app groups).
- [ ] **Distribution certificate** — Certificates → **+** → **Apple Distribution**. Generate a CSR on your Mac (Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority → save to disk). Upload the CSR, download the resulting `.cer`, double-click to install.
- [ ] **Export the cert as `.p12`** — Keychain Access → My Certificates → right-click the `Apple Distribution: …` entry → **Export** → set a strong password. Keep both the file and the password — they become two GitHub secrets.
- [ ] **App Store provisioning profile** — Profiles → **+** → **App Store** (Distribution) → App ID `net.myssdomain.mypi` → certificate from step above → profile name **`MyPi App Store`** (verbatim, you'll reference it in a secret) → download.
- [ ] **Team ID** — Membership tab → note the 10-character Team ID.

## 2. App Store Connect setup

- [ ] **App Store Connect API key** — [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users and Access → Integrations → Team Keys → **+** → role **App Manager** → download the `.p8` (only available once). Note the **Key ID** (10 chars) and **Issuer ID** (UUID shown on that page).
- [ ] **App record** — My Apps → **+** → New App → Platform iOS, Name `MyPi Companion`, Primary language English (U.S.), Bundle ID `net.myssdomain.mypi` (from the App ID created above), SKU `mypi-ios-001`, Full Access. (The first upload fails if this doesn't exist yet.)

## 3. GitHub Actions secrets

Repo Settings → Secrets and variables → Actions → New repository secret. All eight are required by [`archive.yml`](../.github/workflows/archive.yml).

- [ ] `APPLE_DEVELOPMENT_TEAM` — 10-char Team ID from step 1.
- [ ] `DISTRIBUTION_CERT_P12_BASE64` — output of `base64 -i cert.p12 | pbcopy` against the `.p12` from step 1.
- [ ] `DISTRIBUTION_CERT_PASSWORD` — the export password you set on the `.p12`.
- [ ] `PROVISIONING_PROFILE_BASE64` — output of `base64 -i MyPi_AppStore.mobileprovision | pbcopy`.
- [ ] `PROVISIONING_PROFILE_NAME` — `MyPi App Store` (or whatever you named the profile in step 1; must match exactly).
- [ ] `APP_STORE_CONNECT_API_KEY_ID` — from step 2.
- [ ] `APP_STORE_CONNECT_API_ISSUER_ID` — from step 2.
- [ ] `APP_STORE_CONNECT_API_KEY_P8` — full contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines.

## 4. Dry-run the archive workflow

- [ ] Actions tab → **Archive** → **Run workflow** → set **`upload: false`** → Run. (Dry run: exercises keychain import, profile install, manual signing, IPA export. Doesn't talk to App Store Connect.)
- [ ] Workflow finishes green. If it fails on a signing step, the secret values are wrong — re-check the cert/profile/team-ID triple before continuing.
- [ ] Download the `MyPi-archive` artifact and confirm an `.xcarchive` is inside.

## 5. Real upload

- [ ] Actions → Archive → Run workflow → **`upload: true`** → Run.
- [ ] Wait for Apple to finish processing — typically 5–15 minutes. App Store Connect → My Apps → MyPi Companion → TestFlight tab should eventually show the build.

## 6. Generate screenshots

iPhone 6.9" and iPad 13" are both required for iOS 18. Demo mode gives deterministic framing — no real Pi-hole data needed in the screenshots.

- [ ] Open the iOS Simulator → **iPhone 17 Pro Max** (or 16 Pro Max — whichever the installed runtime has). Boot the simulator.
- [ ] Build & run from Xcode (or `xcrun simctl install` an IPA). Launch MyPi.
- [ ] Tap **Try Demo Mode** on the setup sheet.
- [ ] Take ≥ 3 screenshots from the shot list in [`appstore-metadata.md`](appstore-metadata.md#screenshots-checklist) — Dashboard, Query Log (filter = Blocked), Unique Clients drill-down, multi-site switcher menu, Settings → Connection. `xcrun simctl io booted screenshot ~/Desktop/iphone-1.png`.
- [ ] Repeat for **iPad Pro 13" M4** (or M5).
- [ ] (Optional but easy) one landscape shot per device for the variety.

## 7. Fill in the App Store Connect product page

All copy is in [`appstore-metadata.md`](appstore-metadata.md). Paste verbatim unless you want to tweak.

- [ ] **App Information** — Name, Subtitle, Category (Utilities primary, Developer Tools secondary), Content Rights ("does not contain third-party content"), Age Rating questionnaire (everything **None** → 4+).
- [ ] **Pricing and Availability** — Free, all territories. (Or set restrictions if you have any.)
- [ ] **App Privacy** — answer the gate question **"No, we do not collect data from this app."** That skips every per-category question.
- [ ] **Version Information** (the per-version tab, currently 0.2.2):
  - [ ] What's New in This Version
  - [ ] Promotional Text
  - [ ] Description
  - [ ] Keywords
  - [ ] Support URL (`https://github.com/theojamesvibes/mypi-ios/issues`)
  - [ ] Marketing URL (`https://github.com/theojamesvibes/mypi-ios`)
  - [ ] Privacy Policy URL (`https://theojamesvibes.github.io/mypi-ios/privacy`)
  - [ ] Copyright
  - [ ] Sign-In Information: **Sign-in not required** (the app reaches a self-hosted server the reviewer can't access; demo mode is the test path).
  - [ ] Contact Information — review-team contact name, email, phone (Apple requires a phone).
  - [ ] Notes — paste the **Review Notes** block from `appstore-metadata.md` so the reviewer knows to tap "Try Demo Mode".
  - [ ] Screenshots — upload the sets from step 6.
  - [ ] Build — attach the build uploaded in step 5 (dropdown of available TestFlight builds).

## 8. Submit

- [ ] **Save** at the top of the version page.
- [ ] **Add for Review** → **Submit to App Review**.
- [ ] Apple's two extra prompts during submission:
  - [ ] **Export Compliance** — pre-declared via `ITSAppUsesNonExemptEncryption=false` in Info.plist; no prompt expected, but if asked, the answer is "Yes, only HTTPS / standard TLS."
  - [ ] **IDFA / Advertising Identifier** — No.
- [ ] Confirm the version's state flips to **Waiting for Review**.

## 9. Wait, then respond

- [ ] First review for a utility this clean typically completes in 24–72 hours.
- [ ] If App Review flags anything, the message lands in App Store Connect → Resolution Center **and** by email. Most common asks: a screenshot of the app working without a server (demo mode covers this — point them at the review notes); a precise privacy clarification (the wording in `appstore-metadata.md` is already tuned for this).
- [ ] On approval: pick **Manually release this version** (default) and ship when ready, or **Automatically release**.

---

## Reference

- **Workflow**: `.github/workflows/archive.yml`
- **Metadata source-of-truth**: [`docs/appstore-metadata.md`](appstore-metadata.md)
- **Privacy policy** (served via GitHub Pages): [`docs/privacy.md`](privacy.md) → `https://theojamesvibes.github.io/mypi-ios/privacy`
- **External security audit referenced in Review Notes**: [`docs/reviews/2026-04-24-grok-audit.md`](reviews/2026-04-24-grok-audit.md)
