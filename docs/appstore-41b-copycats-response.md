# Resolving Guideline 4.1(b) — Design: Copycats (MyPi Companion)

**Rejection (App Review, build 0.2.2):**

> Guideline 4.1(b) - Design - Copycats. The app or its metadata appears to contain
> potentially misleading content. Specifically, the app includes content that
> resembles **MyPi** without the necessary authorization.
> **Next Steps:** Please demonstrate your relationship with any third-party brand
> owners represented in the app.

## What this actually means

This is **not** a design-clone or icon problem. The reviewer sees an app **branded "MyPi"** published by App Store account **TIA Partners, LLC** and assumes "MyPi" is a *third party's* brand being used without permission. The fix is to **prove first-party ownership**: TIA Partners, LLC *is* the owner of MyPi, so there is no third party at all.

The rejection happened because our public identity was fragmented across four names for one owner — App Store account `TIA Partners, LLC`, App Store copyright `theojamesvibes`, `LICENSE` `Theo James`, GitHub org `theojamesvibes`. A reviewer couldn't connect any of those to "TIA Partners, LLC." We've now standardized everything on **TIA Partners, LLC**.

## Resolution: usually no new binary required

4.1(b) brand-ownership flags are typically cleared by **replying in Resolution Center with verifiable evidence**; Apple re-reviews the existing build. Do the metadata/evidence steps below, then reply. Only upload a new build if the reviewer explicitly asks for one (the in-app About-screen ownership line is ready for whenever the next build ships).

---

## Pre-reply checklist (do these first, then reply)

1. **App Store Connect → App Information → Copyright** — change to `© 2026 TIA Partners, LLC` (was `© 2026 theojamesvibes`). Metadata edit, no binary. *Most important — it makes the product page itself name the account holder as the owner.*
2. **Marketing site (tia-partners.com/#apps)** — confirmed already lists **MyPi** and **MyPi Companion** as TIA Partners products. Make sure it's live/public and the wording explicitly says they are products of TIA Partners, LLC. This is the single piece of evidence the reviewer will click.
3. **Repo consistency (already done in this PR):**
   - `LICENSE` → `Copyright (c) 2026 TIA Partners, LLC`
   - `README.md` → new **Ownership & License** section tying MyPi → TIA Partners, LLC
   - `docs/appstore-metadata.md` → copyright field updated
   - In-app **Settings → About** → Developer "TIA Partners, LLC" + © line (ships in next build)
4. **Sibling server repo (`../mypi`)** — currently has **no LICENSE file**. Add one with `Copyright (c) 2026 TIA Partners, LLC` so the server's public repo names the same owner. (The rejection references "MyPi" the brand, which is the server; an unowned-looking server repo weakens the story.)

---

## Resolution Center reply (paste this)

> Hello, and thank you for the review.
>
> "MyPi" is our own product, not a third-party brand. We are the original
> author and sole owner of MyPi; there is no third party involved, so no
> external authorization exists or is needed. We'd like to demonstrate that
> relationship directly:
>
> 1. **Same legal entity throughout.** This app is published by TIA Partners,
>    LLC. TIA Partners, LLC also owns the MyPi brand and the MyPi server
>    software. Our company website lists both MyPi and the MyPi Companion app
>    as our products: https://www.tia-partners.com/#apps
>
> 2. **MyPi is our open-source project.** Both the MyPi server and this iOS
>    companion app are source-available under the MIT License, authored and
>    maintained by us:
>    • Server: https://github.com/theojamesvibes/mypi
>    • iOS app (this submission): https://github.com/theojamesvibes/mypi-ios
>    The LICENSE files name the copyright holder as TIA Partners, LLC.
>
> 3. **Consistent ownership on the listing.** The app's Copyright field reads
>    "© 2026 TIA Partners, LLC", matching our developer account, and the app's
>    Settings → About screen names TIA Partners, LLC as the developer with a
>    link to our website.
>
> MyPi is a self-hosted Pi-hole aggregation dashboard we built; this app is the
> official mobile client for it. The "MyPi" name, the server, this app, the
> App Store account, and the company website are all the same owner.
>
> Please let us know if any further documentation would help, and we're happy
> to provide it. Thank you.

---

## If the reviewer wants more

Apple sometimes asks for a signed authorization letter even for first-party brands. If so, provide a short letter on TIA Partners, LLC letterhead:

> TIA Partners, LLC is the owner of the MyPi brand and the developer of the
> MyPi Companion iOS application (App Store account: TIA Partners, LLC). We
> authorize the publication of MyPi Companion under our App Store account.
> — [Name], [Title], TIA Partners, LLC, [date]

Upload it via the Resolution Center attachment, or host it at a `tia-partners.com` URL and link it (a same-domain document is itself strong proof).
