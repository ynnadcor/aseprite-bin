# Deployment Path & The Real Blocker (on‑head‑unit HUD output)

This file is the honest answer to: *"what stands between the working simulator and
arrows actually on your windshield?"*

## The chain, and where it breaks

```
[custom MapKit/CarPlay nav app]  →  NavEvent  →  Translator  →  HudFrame
        (feasible, not built)         (done)       (done)        (done)
                                                                   │
                                                                   ▼
                                               [on‑head‑unit agent emits the
                                                factory HUD guidance messages]
                                                   ▲  ◄── THE BLOCKER
                                                   │
                        requires code running on the NBT EVO head unit,
                        which requires modifying the head unit (SSH + RW)
```

Everything to the left of the blocker is either done (simulator, translator, HUD IR)
or a well‑scoped, car‑free next step (the MapKit adapter). The blocker is getting a
small agent **onto the head unit** that can put our `HudFrame` onto the bus the
cluster/HUD already listens to.

## Why this is genuinely hard (and not something we fake)

1. **It needs code on a QNX head unit.** The agent must be built with the QNX 6.5 /
   `armv7le` toolchain and run on NBT EVO. That's a real native‑software effort, and
   the reference project (NBT‑AAD) is the proof it's *possible* — but it is a mature,
   many‑months project, not a weekend port.
2. **It needs the head unit opened for install.** Placing an agent on NBT EVO means
   enabling access to the unit and switching its filesystem to read‑write — a change
   to the car with real risk (it can affect CarPlay, audio, displays, or brick the
   unit). Per `safety.md`, this is **Red tier**: gated on your explicit approval and
   an independent recovery plan, and **this project does not automate or bundle the
   head‑unit unlock**.
3. **The Apple data source still has to exist.** Even with the agent, the maneuvers
   must come from a legal source (custom MapKit/CarPlay nav app — `navigation-data.md`),
   not the stock Apple Maps app.

## What this project does and does NOT do about the blocker

**Does:**
- Build and test everything up to the HUD boundary (simulator, translator, HUD IR).
- Define a narrow, reviewable `HudFrame` contract so the eventual agent has a tiny,
  auditable surface (arrow + distance + short label + optional roundabout exit).
- Keep a read‑only diagnostic app that helps you *characterize* your car safely.

**Does NOT:**
- Reproduce, bundle, or step you through a head‑unit SSH unlock or firewall change.
- Transmit any experimental message onto your car's network.
- Claim the simulator is an in‑car integration. It is a simulator.

## Honest routes past the blocker (your choice, later, with approval)

1. **Reuse the existing community integration as‑is.** The NBT‑AAD project already
   drives the HUD for Android Auto on NBT EVO (incl. a confirmed G31). If your real
   goal is "great maps guidance on the HUD," the lowest‑effort *existing* path is that
   project's Android‑Auto route — but it is **Android Auto + Google Maps/Waze**, uses
   a third‑party head‑unit modification, and is **their** software under a
   noncommercial license, not something we re‑implement here. Evaluate it on its own
   terms and risk.
2. **Build the Apple‑sourced agent (ambitious).** A new on‑head‑unit agent that takes
   our `HudFrame` from a custom MapKit/CarPlay nav app over the phone↔HU link and
   emits HUD messages. This is the "truly your own, Apple‑Maps‑equivalent" path. It is
   a large effort and is **design‑stage only** until (a) you decide to pursue it, (b)
   a vehicle‑specific safety + recovery review exists, and (c) you approve each
   persistent change.

## What would need YOU (user‑dependent), and when

- Nothing yet for the software to progress on the phone/simulator side.
- Later, **only if you choose to pursue on‑car output**: decisions about head‑unit
  access, a recovery plan, and your explicit approval. We will spell out each step and
  its risk *before* anything touches the car, and stop for your go‑ahead.
