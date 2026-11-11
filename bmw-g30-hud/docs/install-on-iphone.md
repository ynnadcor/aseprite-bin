# Installing BMW Link on your iPhone

Every successful CI run builds the app and publishes **`BMWLink-unsigned-ipa`**
under the run's *Artifacts* (GitHub → Actions → "bmw-g30-hud CI" → latest green
run on this branch). iOS only installs apps **signed** for your phone, so one of
the two routes below is needed. Both are legitimate Apple mechanisms. Neither
needs a jailbreak.

| | Route A: free | Route B: $99/yr |
|---|---|---|
| Cost | $0 | Apple Developer Program, $99/yr |
| Needs a computer? | **Yes**, for about 15 minutes each install (borrowed Mac or Windows PC) | **No.** CI signs and uploads; you install from the TestFlight app |
| Lasts | **7 days**, then sign again | 90 days per build; CI can upload a new build any time |
| Automatic car search (broadcast) | ❌ not available; use "Search the cable" or Check | ✅ once Apple grants the multicast entitlement (free request form) |
| Status in this repo | ✅ ready now (unsigned `.ipa` from CI) | 🟡 workflow prepared, **not yet run**: needs your account |

> We won't enroll or spend anything without your explicit OK. Credentials never
> go in chat or the repository; Route B uses GitHub **encrypted secrets**.

---

> **No computer at all?** You can still do the read‑only car test today, free:
> [`phone-only-car-test.md`](phone-only-car-test.md) runs it inside the a-Shell
> app. The steps below are for installing the full BMW Link app.

## Route A: free, with a borrowed computer

You need: a Mac or Windows PC for about 15 minutes, a cable from it to your
iPhone (USB‑C, or USB‑A to USB‑C), and your Apple ID.

1. **Get the app file**, easiest on the computer itself: sign in at github.com
   (GitHub only lets signed‑in users download build files) → this repository →
   **Actions** → newest green **bmw-g30-hud CI** run → **Artifacts** →
   `BMWLink-unsigned-ipa`. Unzip it to get `BMWLink-unsigned.ipa`. Sign out of
   GitHub afterwards if the computer isn't yours.
2. **Install Sideloadly** from sideloadly.io (it signs apps with a free Apple ID).
   - **Windows:** it also needs Apple's **iTunes** and **iCloud** installed from
     apple.com, not the Microsoft Store versions.
   - **Mac:** nothing else is needed. If the Mac has Xcode, Xcode can also build
     and install from source instead (`ios-app/README.md`).
   - Honest caveat: Sideloadly is third‑party. It says your Apple ID goes only to
     Apple, to create the free 7‑day certificate. Some people use a spare Apple ID
     for this. Your choice.
3. Connect the iPhone with the cable, unlock it, and tap **Trust** on the phone.
   In Sideloadly, drag in `BMWLink-unsigned.ipa`, type your Apple ID, click
   **Start**, then enter your password and any 2‑factor code it asks for.
4. **On the iPhone:**
   - Settings → Privacy & Security → **Developer Mode** → on. The phone restarts;
     tap **Turn On** when asked. (This switch only appears once the app is installed.)
   - Settings → General → **VPN & Device Management** → your Apple ID → **Trust**.
5. Open **BMW Link**. After 7 days it stops opening until you repeat steps 2–3.
   A free Apple ID can have at most 3 such apps at once.

## Route B: TestFlight, no computer ($99/yr, only if you choose it)

Having the **TestFlight app** isn't enough on its own: it only installs apps a
developer has invited you to. Uploading this app needs a paid **Apple Developer
Program** membership. To check: developer.apple.com/account → Membership details.

One‑time setup, all doable in Safari on the iPhone. If a page looks cut down,
tap **aA → Request Desktop Website**.

1. Enroll in the **Apple Developer Program** (Apple Developer app or
   developer.apple.com). Skip this if you're already a member.
2. developer.apple.com/account → Certificates, IDs & Profiles → **Identifiers** →
   **+** → App IDs → App → description "BMW Link", explicit bundle ID
   **`io.github.ynnadcor.bmwlink`** → Register. No capabilities are needed.
3. appstoreconnect.apple.com → **Apps → + → New App**: iOS; a name nobody else
   has used on the App Store (e.g. "G30 Link Dev"; "BMW Link" is probably taken);
   English; the bundle ID from step 2; SKU `bmwlink`; Full Access. This name only
   shows in App Store Connect and TestFlight. On the home screen it stays "BMW Link".
4. App Store Connect → **Users and Access → Integrations → App Store Connect API**
   → Team Keys → **+** (the first time you may need **Request Access**): name
   "GitHub CI", access **Admin** → Generate. Note the **Issuer ID** (top of the
   page) and the key's **Key ID**, then **Download** the key. You can only download
   it once. It lands in Files → Downloads as `AuthKey_XXXXXXXXXX.p8`.
5. Copy the key's text: in **Files**, long‑press the `.p8` file → **Rename** →
   change the ending to `.txt` → open it → long‑press the text → **Select All** →
   **Copy**. If the text can't be selected, say so in chat; there are other ways.
6. GitHub (Safari, desktop website) → this repository → **Settings → Secrets and
   variables → Actions → New repository secret**, four times:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: the key text from step 5, including the BEGIN and END lines
   - `APPLE_TEAM_ID`: your 10‑character Team ID (developer.apple.com/account →
     Membership details)

   Stray spaces or lost line breaks from copying on a phone are cleaned up by the
   workflow. Afterwards, delete the `.txt` key from Files. Never paste it in chat.
7. Tell Claude in chat that the secrets are in. Claude starts a build by adding a
   line to `bmw-g30-hud/ios-app/testflight-requests.md`: any change to that file
   starts the **bmw-g30-hud TestFlight** workflow, and you can also edit it
   yourself on GitHub. (GitHub's **Run workflow** button for it only appears once
   the workflow is on the repository's main branch.) The workflow runs the tests,
   signs with your key ("cloud signing") and uploads to TestFlight.
8. When Apple has processed the build (usually 5–30 minutes, and you get an email):
   App Store Connect → your app → **TestFlight** → Internal Testing → **+** →
   create a group (e.g. "Me"), add yourself, and turn on automatic distribution.
9. iPhone: install **TestFlight** from the App Store if needed, accept the invite,
   and install **BMW Link**. Later builds arrive over the air.

**Optional, for automatic car search:** request Apple's *multicast networking*
entitlement for `io.github.ynnadcor.bmwlink` (free form on developer.apple.com,
describing it as "discovering the car's diagnostic gateway on a local Ethernet
link"). After approval, enable it under Identifiers → the App ID → Capabilities,
then change `multicast_entitlement: no` to `yes` in
`bmw-g30-hud/ios-app/testflight-requests.md` (that also starts a build).

> Route B's workflow has not been run yet, because it can't be without an
> account. Expect its first run to possibly need a small fix. Its log will show
> exactly what.
