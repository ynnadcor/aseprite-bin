# Car test from your iPhone alone (free, no computer)

This runs the same **read-only** car test as the BMW Link app, but as a small
Python program inside **a-Shell**, a free App Store app. There's no computer,
no Apple developer account, and no 7‑day expiry.

It does what the app does: finds the USB Ethernet adapter, finds the car's
gateway, reads identification data and the head unit's fault codes, and saves
a log with the VIN and MAC masked. It can only *read*: anything else is refused
twice in the code before it could be sent (the same rules as the app; see
[`safety.md`](safety.md)). Program: [`../tools/bmw_car_test.py`](../tools/bmw_car_test.py).

## 1. Install a-Shell (once)

App Store: <https://apps.apple.com/us/app/a-shell/id1473805438> (free). Open it
once and let it finish setting up.

## 2. Download the test (once, or again to update it)

In a-Shell, paste this line and press return:

```
curl -L -o bmw_car_test.py https://raw.githubusercontent.com/ynnadcor/aseprite-bin/refs/heads/claude/bmw-g30-maps-hud-eyvj50/bmw-g30-hud/tools/bmw_car_test.py
```

## 3. Practice anywhere (1 minute)

```
python3 bmw_car_test.py --practice
```

It checks that Python can use the network on your phone, then runs the whole
test against a **simulated car**; nothing goes on the network. It should end
with `Result: 9 answered, 1 declined, 1 no answer`.

## 4. At the car (about 10 minutes)

1. Park, parking brake on, **P**. Ignition **on** (press Start/Stop without the
   brake).
2. ENET cable in the OBD port (driver's footwell), USB‑C Ethernet adapter in the
   iPhone. Turn the iPhone's **Wi‑Fi off** (wireless CarPlay drops; that's
   expected). Wait about 10 seconds.
3. In a-Shell:

   ```
   python3 bmw_car_test.py
   ```

4. If iOS asks whether a-Shell may use the **Local Network**, tap **Allow**,
   then run the same line again.
5. If the quick searches find nothing, it offers to **search every address on
   the cable**. Answer `y` (or just press return). It takes up to about 4
   minutes and stops as soon as the car answers. Keep a-Shell open with the
   screen on; iOS pauses apps in the background. To stop it, press Ctrl‑C on
   a-Shell's keyboard bar.
6. When it says **It speaks HSFZ** (or DoIP), it reads about 10 records. Next
   time it remembers the address and goes straight there.

## 5. Send the log

The log is saved next to the program as `bmw-log-<date>-<time>.txt`, with the
VIN and MAC masked. Open the **Files** app → **On My iPhone** → **a-Shell** →
tap the log → long‑press the text → **Select All** → **Copy**, and paste it
into the chat. (Or in a-Shell, `cat` the file and copy the output.)

## If something goes wrong

| What you see | What to try |
|---|---|
| `No wired Ethernet address yet` | Ignition on? Adapter firmly in? Wait 10 s and run again. Wi‑Fi off helps. |
| `Local Network` errors | Settings → Privacy & Security → Local Network → **a-Shell** on, then run again. |
| `iOS blocks automatic search` | Normal. It moves on to the next way by itself. |
| Car not found after the cable search | Ignition on? Send the log anyway; it shows what was tried. |
| `no acknowledgement from the gateway` | The car may have gone to sleep: ignition on again, run again once. |
| Several failures in a row | Stop. Lock the car for about 20 minutes, then try once more. Send the log. |

You can also give the address directly, if another tool shows it:
`python3 bmw_car_test.py --host 169.254.a.b`. Run
`python3 bmw_car_test.py --help` for every option.

**Safety:** the test only reads. Don't drive with the cable plugged in. With the
ignition on and the engine off the battery drains slowly; the test is short,
but if you repeat it many times, run the engine.
