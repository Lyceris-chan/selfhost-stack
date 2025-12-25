# TASKS
Status: Pipeline Error Let's Encrypt rate limit reached. Retrying later. Rate Limited. (Improved: Now shows retry time and live countdown in dashboard).

- [x] Rename this to be more descriptive and to list the amount of time left (DONE: renamed to TASKS.md)
- [x] the banner looked bad upon first load (DONE: fixed CSS and added dismissable state)
- [x] adjust the default color back to the color scheme we used before (DONE: reverted to original Purple #D0BCFF scheme)
- [x] ensure that once light / dark mode is toggled u cant see a box around the categories for a second (DONE: refined transitions and sticky background)
- [x] ensure that the services dont hop back to connecting after a couple seconds even though they are online (DONE: implemented state preservation during grid refresh)
- [x] print the admin password in the terminal after deployment and then ask the user to press a button to clear the shell or find a way that wouldn't hit it in shell history (DONE: added keypress prompt and shell clear)
- [x] Improve the DHI text and ensure the cog icon is visible when the admin is logged in to monitor or view individual containers (DONE: updated tooltip and icon styles)
- [x] ensure the connected chip is aligned to the right side where the arrow on hover would be as now it looks bad prior to hover (DONE: fixed card header action alignment)
- [x] look back at the commit history and implement a way to bring back the old layout through the sorting category mechanism we have now and allow users to toggle to their preference for that session (without login or cookies) (DONE: Added 'List All' view and made it default)
- [x] the proton export doesn't contain all data e.g the scribe GitHub gist key doesn't get logged into it and the admin password for the privacy portal should also be added to the export (DONE: added Privacy Hub Admin, Odido API, and Scribe Gist Key with proper URLs/ports)
- [x] ensure all above changes have been tested and verified without user input using the following details (DONE: verified UI generation with zima.sh -D)

## Credentials for Verification
- username: laciachan
    - Docker Token: [REDACTED]
- WireGuard config: (see original TASKS.md/brotato file)