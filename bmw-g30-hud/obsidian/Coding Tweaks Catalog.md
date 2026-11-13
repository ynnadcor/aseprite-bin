---
tags: [bmw/g30, idrive, coding]
updated: 2026-11-13
---
# Coding Tweaks Catalog

The 20 reversible G30 / NBT EVO coding changes in the [[iDrive Coding Guide]], by category. Apply them in **BimmerCode**; the app never writes coding. Availability depends on your car.

## Apple CarPlay
### Apple CarPlay full-screen
- **What:** Makes CarPlay fill the whole iDrive screen instead of leaving BMW's side band of widgets.
- **Why:** CarPlay maps and apps get the full display, which is easier to read while driving.
- **Where:** BimmerCode -> Head unit (HU) -> look for “Apple CarPlay” / “CarPlay fullscreen” and turn it on.
- **Needs:** Apple CarPlay already active on the car (your car has wireless CarPlay).
- **Undo:** Set it back to the factory value (the split view).
- Module: Head unit (NBT EVO)

### Keep CarPlay from expiring
- **What:** Removes the time limit some cars put on the CarPlay enablement so it stays on for good.
- **Why:** CarPlay keeps working without a renewal or a dealer visit.
- **Where:** BimmerCode -> Head unit (HU): the CarPlay/feature-enablement option. On many G30s CarPlay is already permanent; check first.
- **Caveat:** Only relevant if your CarPlay was ever shown as time-limited. Yours already works, so this may not apply.
- **Undo:** Restore the original value.
- Module: Head unit (NBT EVO)

## Displays & HUD
### Digital speed in the Head-Up Display
- **What:** Adds a digital km/h or mph number to the colour Head-Up Display.
- **Why:** A clear speed readout in your line of sight.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> enable the digital speed field.
- **Needs:** The factory Head-Up Display (your car has it).
- **Undo:** Remove the field in the same place.
- Module: Instrument cluster (KOMBI)

### Digital speed in the cluster
- **What:** Adds a digital speed number to the instrument cluster.
- **Why:** An exact speed without reading the analogue needle.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) -> the digital-speed option.
- **Undo:** Turn it back off.
- Module: Instrument cluster (KOMBI)

### Extra consumption & efficiency views
- **What:** Unlocks extra trip and efficiency readouts in the cluster and iDrive.
- **Why:** More detail on how the car is driving and using fuel.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) / Head unit (HU): the consumption/statistics options.
- **Undo:** Turn the options back off.
- Module: Instrument cluster (KOMBI)

### More content in the Head-Up Display ⚠️
- **What:** Shows extra items in the HUD such as the speed-limit sign, entertainment and phone info.
- **Why:** More at-a-glance information without looking down.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> enable the fields you want.
- **Needs:** The factory Head-Up Display.
- **Caveat:** A busy HUD can be distracting; add fields one at a time and keep what helps.
- **Undo:** Turn the individual fields back off.
- Module: Instrument cluster (KOMBI)

### Sport displays (gauges on iDrive)
- **What:** Turns on BMW's own performance pages: a digital power and torque gauge, plus consumption, on the iDrive screen.
- **Why:** This is the factory way to get real gauges on the iDrive screen — no head-unit modification needed.
- **Where:** BimmerCode -> Head unit (HU) -> “Sport displays” / “M Sport displays” -> on. Then on the car: Menu -> your vehicle -> the Sport/performance view.
- **Needs:** NBT EVO (you have it). The look is BMW's; it isn't a custom gauge you design.
- **Undo:** Turn the option back off.
- Module: Head unit (NBT EVO)

## Media & video
### Play video from USB ⚠️
- **What:** Enables playing video files from a USB stick through iDrive.
- **Why:** Watch your own media without extra hardware.
- **Where:** BimmerCode -> Head unit (HU): the USB/media video option, where present.
- **Caveat:** Same as video in motion: passenger use only while driving.
- **Undo:** Turn it back off.
- Module: Head unit (NBT EVO)

### Video in motion ⚠️
- **What:** Lets the screen play video (and CarPlay video apps) while the car is moving, instead of only when parked.
- **Why:** A passenger can watch video on a drive.
- **Where:** BimmerCode -> Head unit (HU) -> “Video in motion” / “VIM” -> on.
- **Caveat:** For passenger use. Watching video while driving is unsafe and illegal in most places — don't use it in the driver's view while moving.
- **Undo:** Turn it back off.
- Module: Head unit (NBT EVO)

## Navigation
### Faster screen wake ⚠️
- **What:** Tweaks a start-up delay so the screen and map come up sooner after the car is unlocked.
- **Why:** Less waiting for iDrive after you get in.
- **Where:** BimmerCode -> Head unit (HU): the quick-start / standby options, where present.
- **Caveat:** Keeping the head unit more awake can draw a little more power when parked; fine with regular driving.
- **Undo:** Restore the factory value.
- Module: Head unit (NBT EVO)

### Navigation map in the HUD
- **What:** Shows a small navigation map or richer turn arrows in the Head-Up Display.
- **Why:** Follow directions without glancing at the centre screen.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> navigation.
- **Needs:** Factory navigation and the Head-Up Display (your car has both).
- **Undo:** Turn the navigation HUD content back off.
- Module: Instrument cluster (KOMBI)

## Phone & voice
### Second phone / full Bluetooth
- **What:** Enables pairing a second phone at once and the fuller Bluetooth office/streaming features.
- **Why:** Two phones connected, and more phone features in iDrive.
- **Where:** BimmerCode -> Head unit (HU) -> the telephony / Bluetooth feature options.
- **Undo:** Turn the options back off.
- Module: Head unit (NBT EVO)

## Comfort
### Automatic door locking
- **What:** Locks the doors automatically as you drive off, and/or unlocks when you park or take the key out.
- **Why:** Convenience and a bit of security, set to your taste.
- **Where:** BimmerCode -> Body (BDC) -> the auto-lock / auto-unlock options.
- **Undo:** Set them back to the factory behaviour.
- Module: Body domain controller (BDC)

### Fold mirrors when locking
- **What:** Folds the door mirrors in when you lock the car and unfolds them when you unlock it.
- **Why:** Tidier parking and a little protection in tight spots.
- **Where:** BimmerCode -> Body (BDC) -> the mirror fold-on-lock option.
- **Needs:** Power-folding mirrors.
- **Undo:** Turn it back off.
- Module: Body domain controller (BDC)

### Skip the “I agree” start-up screen
- **What:** Stops iDrive from showing the legal warning you have to confirm every time the car starts.
- **Why:** iDrive goes straight to the map or your last screen.
- **Where:** BimmerCode -> Head unit (HU) -> “Disclaimer” / “Legal disclaimer” -> disable.
- **Undo:** Re-enable the disclaimer.
- Module: Head unit (NBT EVO)

### Windows from the key / comfort access
- **What:** Lets you open or close the windows (and sunroof) by holding the key button or the door handle.
- **Why:** Air the car out before you get in on a hot day.
- **Where:** BimmerCode -> Body (BDC) -> the remote window / comfort-opening options.
- **Undo:** Turn the options back off.
- Module: Body domain controller (BDC)

## Startup & appearance
### Cluster style / lighting
- **What:** Switches between the cluster's built-in looks (e.g. the Sport red/black style) where the car offers them.
- **Why:** A dashboard look you prefer.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) -> the cluster style / background option.
- **Needs:** The cluster must have more than one built-in style.
- **Undo:** Choose the factory style again.
- Module: Instrument cluster (KOMBI)

### Start-up animation
- **What:** Changes the welcome animation shown on the cluster and screen at start-up (e.g. a sportier set).
- **Why:** A nicer greeting that matches your car.
- **Where:** BimmerCode -> Instrument cluster (KOMBI) / Head unit (HU) -> the start-up / welcome animation option.
- **Caveat:** This picks between BMW's built-in animations. A fully custom animation needs head-unit modification (out of scope).
- **Undo:** Choose the factory animation again.
- Module: Instrument cluster (KOMBI)

## Menus
### Hide screens you don't use
- **What:** Lets you turn off iDrive menu tiles and tabs you never open, where the coding allows.
- **Why:** A cleaner iDrive with only what you use.
- **Where:** BimmerCode -> Head unit (HU): the menu / main-menu visibility options, where present.
- **Caveat:** How much can be hidden varies by software version.
- **Undo:** Re-enable the tiles.
- Module: Head unit (NBT EVO)

### More favourite buttons
- **What:** Unlocks extra programmable favourite buttons for iDrive functions, where supported.
- **Why:** One-press access to the screens you use most.
- **Where:** BimmerCode -> Head unit (HU): the favourites / programmable-button options.
- **Undo:** Set the count back to standard.
- Module: Head unit (NBT EVO)
