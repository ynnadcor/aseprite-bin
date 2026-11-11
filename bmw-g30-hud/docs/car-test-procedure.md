# First car test: read-only identify (about 10 minutes)

**What this test does:** connects the BMW Link app to your car over the ENET
cable and *reads* identification data: VIN, identification records from the
gateway, head unit, cluster and HUD, and the head unit's stored fault codes.

**What it cannot do:** write, code, clear fault codes, flash, or change any
setting. Non-read requests are refused in two places in the code before
anything reaches the car, and tests check this. Nothing here touches the engine,
DME, tune, brakes, airbags or the head unit's software.

**Before you start:** the app must be installed on your iPhone
([`install-on-iphone.md`](install-on-iphone.md)). No computer to install it with?
The same test runs free in the a-Shell app:
[`phone-only-car-test.md`](phone-only-car-test.md). To practise first, open the
app's **Diagnostics** tab, pick **Simulated car**, and run steps 2–4. Nothing
goes on the network.

---

## Step 0: Set up (2 minutes)

1. Park somewhere safe. Parking brake on, transmission in **P**.
2. Turn the **ignition on**: press Start/Stop *without* the brake. Running the
   engine is also fine, but don't drive while connected.
3. Plug the **ENET cable** into the OBD port (driver's footwell) and the
   **USB‑C Ethernet adapter** into the iPhone.
4. Optional but recommended: switch the iPhone's **Wi‑Fi off** for the test. Some
   iPhones only reach the car once Wi‑Fi is off. The app also pins its traffic to
   the cable, so this is a belt‑and‑braces step. Wireless CarPlay will drop while
   Wi‑Fi is off, which is expected.

## Step 1: Cable check (Diagnostics tab → "1 · Cable")

- Wait about 10 seconds after plugging in, then tap **Refresh**.
- ✅ Good: a green line like `en7  169.254.x.x`. iOS has given the adapter an
  address on the cable.
- ⚠️ "No wired Ethernet yet": re‑seat the adapter, check the ignition is on, wait
  and refresh. If it never appears, the adapter isn't recognised. Note which
  adapter it is; that alone is useful to send back.

## Step 2: Find the car ("2 · Find the car")

Try these in order and stop at the first that finds the car:

1. **Automatic search** (2 seconds). iOS may first ask for **Local Network**
   access: tap **Allow** and run it again. If you get "iOS blocked the
   broadcast", that's expected for this build (Apple's multicast permission isn't
   granted yet), so go to option 2 or 3.
2. **Check** an address, if you know the car's gateway address (another app or
   tool may show it). Type it as `169.254.a.b`.
3. **Search the cable (slow, up to ~4 min).** The app sends one small "who are
   you" message to each possible address on the cable, about 250 per second, and
   stops as soon as the car answers. The car only ever receives the standard
   BMW vehicle-identification message that every BMW tool broadcasts. You can
   tap **Stop** at any time.

When found, you'll see something like `169.254.x.x · HSFZ (TCP 6801) · VIN WBA…1234`.
**Note whether it says HSFZ or DoIP.** That answers an open question about your
car. The working address is remembered for next time.

## Step 3: Read identification ("3 · Read identification")

1. Tap **Run read-only identify**. It sends about 10 read requests, one at a
   time, and takes about 10–40 seconds. An ECU that doesn't answer costs a few
   seconds of waiting, then is skipped.
2. Results appear per ECU:
   - normal text = the ECU answered,
   - orange "ECU declined" = it answered "not supported" (normal for some
     records),
   - red "No answer" = nothing came back (expected for addresses we're unsure
     of, such as the HUD's).

## Step 4: Send the log back ("Session log")

- Tap **Share log (VIN hidden)** and save or send the file. **Copy log** also
  works if you'd rather paste it.
- The VIN and the car's network MAC address are masked in the file. Glance at it
  before sending anything publicly.

## Step 5: Finish

Unplug the cable, switch Wi‑Fi back on (CarPlay reconnects), and switch the
ignition off. Nothing on the car has changed, so there's nothing to undo.

---

## What to send back

1. The shared log file.
2. One line: did steps 1–3 work, and if not, where did it stop?
3. Which USB‑C Ethernet adapter you used (brand/model), in case it matters.

## If something goes wrong

| Symptom | Likely cause / what to try |
|---|---|
| No wired interface in step 1 | Adapter not recognised; ignition off; cable not seated |
| "Local Network" prompt never appeared and nothing is found | Settings → Privacy & Security → Local Network → BMW Link: on |
| Automatic search: "iOS blocked the broadcast" | Expected without Apple's multicast entitlement; use Check or Search the cable |
| Found the car, identify says "no acknowledgement" | Car may have gone to sleep: turn the ignition on again and retry |
| "connection closed by the car" | Gateway dropped the session: wait 30 s, retry once. Don't loop retries |
| Several failed attempts in a row | Stop. Leave the car locked for ~20 min (it resets its diagnostic state), then try once more. Send the log either way |

**Safety notes.** The test only reads. A long session with the ignition on (engine
off) drains the battery slowly; the test is short, but if you repeat it many
times, run the engine or use a battery maintainer. Don't drive with the cable
plugged in.
