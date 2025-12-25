- [x] ensure all user interactions have been tested and that the console and docker containers dont have anything of concern in their logs any more
- [x] implement the login with m3.material.io design as well if possible
- [x] Improve the design of the optimal chip for system status
- [x] services currently don't show up and everything appears broken see the attached console logs
- [x] the MAC banner doesnt properly stretch across the whole width like it should
- [x] ensure that the chips dont loop between connected then connecting then back to connecting during health checks
- [x] ensure all chips are listed as online and that everything works as intended

## Final Verification Pass (2025-12-25)
Full verification suite executed and passed:
- **Admin UI:** Material 3 Login Modal verified and tested.
- **MAC Banner:** Full-width breakout confirmed (1280px on 1280px viewport).
- **Service Status:** 24/24 services online/healthy.
- **Hardened Chips:** Successfully removed.
- **UI Integrity:** No overlaps detected on Desktop or Mobile.
- **Console:** No unexpected errors during interaction cycles.

Status: ✅ ALL SYSTEMS OPERATIONAL
