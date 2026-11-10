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

## Route A: free, with a borrowed computer

1. **Get the app file.** In the GitHub app or Safari: repository → **Actions** →
   newest green **bmw-g30-hud CI** run → **Artifacts** → `BMWLink-unsigned-ipa`.
   Unzip it to get `BMWLink-unsigned.ipa`. On the computer it's easiest to
   download it there directly.
2. **On the computer**, install a sideloading tool that signs with a free Apple ID,
   for example **Sideloadly** (Windows/macOS). If the computer is a Mac with Xcode,
   Xcode can build and install from source instead (`ios-app/README.md`).
   - Honest caveat: these tools are third‑party. Sideloadly passes your Apple ID to
     Apple to create the free 7‑day certificate. Some people use a separate Apple
     ID for this. Your choice.
3. Connect the iPhone by USB, choose the `.ipa`, sign in, install.
4. **On the iPhone:**
   - Settings → Privacy & Security → **Developer Mode** → on (the phone restarts).
   - Settings → General → **VPN & Device Management** → your Apple ID → **Trust**.
5. Open **BMW Link**. After 7 days it stops opening until you repeat steps 2–3.

## Route B: TestFlight, no computer ($99/yr, only if you choose it)

One‑time setup, all doable in Safari on the iPhone:

1. Enroll in the **Apple Developer Program** (Apple Developer app or
   developer.apple.com).
2. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** →
   register the App ID **`io.github.ynnadcor.bmwlink`**.
3. appstoreconnect.apple.com → **Apps → New App**: name "BMW Link", that bundle ID.
4. App Store Connect → Users and Access → **Integrations → App Store Connect API**
   → generate a team key with **Admin** access. Note the **Issuer ID** and **Key ID**
   and download the `.p8` file (you can only download it once).
5. GitHub → this repository → Settings → **Secrets and variables → Actions** → add:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: the full text of the `.p8` file
   - `APPLE_TEAM_ID`: your 10‑character Team ID (Membership details)
6. GitHub → Actions → **bmw-g30-hud TestFlight** → **Run workflow**. It runs the
   tests, signs with your key ("cloud signing") and uploads to TestFlight.
7. iPhone: install **TestFlight** from the App Store, accept the internal‑testing
   invite, install **BMW Link**. New builds arrive over the air.

**Optional, for automatic car search:** request Apple's *multicast networking*
entitlement for `io.github.ynnadcor.bmwlink` (free form on developer.apple.com,
describing it as "discovering the car's diagnostic gateway on a local Ethernet
link"). After approval, enable it under Identifiers → the App ID → Capabilities,
then run the TestFlight workflow with **"Include the multicast entitlement"**
ticked.

> Route B's workflow has not been run yet, because it can't be without an
> account. Expect its first run to possibly need a small fix. Its log will show
> exactly what.
