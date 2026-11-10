# TestFlight build requests

Any change to this file on GitHub starts the **bmw-g30-hud TestFlight** workflow
(`.github/workflows/bmw-g30-hud-testflight.yml`). It signs BMW Link with your
Apple Developer account and uploads it to TestFlight. It needs the four
repository secrets from [`../docs/install-on-iphone.md`](../docs/install-on-iphone.md)
(Route B). Without them it stops at its first step.

To ask for a build, add a line under **Requests** and commit. Claude does this
when you ask for a build in chat.

multicast_entitlement: no

(Change that to `yes` only after Apple approves the multicast networking
entitlement for this app. It turns on the automatic car search.)

## Requests

- 2026-11-10: file created. No build requested yet.
