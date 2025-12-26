- [x] Not all services are listed on the dashboard e.g scribe is still missing
- [x] im unable to dismiss the update banner and it should be the same width as the category bar same thing goes for the MAC address warning ensure both show up after -c is ran as it shouldnt retain any data
- [x] session auto cleanup toggle looks messed up and clips out the box 
- [x] the text in the System Information chips like update all shouldnt be two rows and all other chips have their text cut off 
- [x] saying status unknown or certificate missing is incorrect in our case as the main button says rate limited and so does the banner which is correct so the hover tooltips should be dynamic
- [x] ensure chips properly scale to take up the remaining space on their row without looking weird e.g Endpoint Provisioning has a ton of empty space next to it as its the only chip on that row
- [x] the adguard allowlist doesnt get setup properly and has no entries in it
- [x] ensure the adguard rewrite for our certificate thing is setup properly
- [x] test all user interactions click and toggle and login and do everything and check everything to see if everthing works update the verification suite as you go
- [x] ensure that all services mentioned in the readme properly work and show up 
- [x] write a report about your findings
- [x] clean up the repo
- [x] push and commit

- [x] I dont see the DNS rewrite setup for our certificate stuff in adguard to allow us to use the cert without a VPN
- [x] the updates available message doesnt stay dismissed 
- [x] the default view should be as if all categories are toggled on by default not the all services category and when the all services category is toggled it should still show the headers like this above said services and list them in a proper 3x3 4x4 grid vpn_lock VPN Protected lan Direct Access hub Infrastructure same for the rest
- [x] the updates available message doesnt stretch across the category bar like it and the mac address message should
- [x] dont have the Session Auto-Cleanup toggle move upon toggle have the warning be displayed prior to toggling it as well in a different way so the user is aware of the risk and so the button doesnt keep changing position
- [x] Change the update all button to be shaped like the Save Theme button and have all buttons be listed under each other for this card
- [x] address these console logs
- [x] add more spacing to Drive Health: Healthy 91.9% Health
- [x] ensure images and all other things we do are also tracked under Project Size 116.8 MB 
(index):1 [DOM] Password forms should have (optionally hidden) username fields for accessibility: (More info: https://goo.gl.qjz9zk/9p2vKq) <form onsubmit=​"submitLogin()​;​ return false;​">​…​</form>​
:8081/api/theme?_=1766708523987:1  Failed to load resource: the server responded with a status of 502 (Bad Gateway)
(index):3587 Failed to load settings from server SyntaxError: Unexpected token '<', "<html>
<h"... is not valid JSON
loadAllSettings @ (index):3587


 

 │   user input username laciachan                                                                                                                                                                                                                 │
 │   docker token [REDACTED]                                                                                                                                                                                             │
 │                                                                                                                                                                                                                                                 │
 │   [Interface]                                                                                                                                                                                                                                   │
 │   # Bouncing = 1                                                                                                                                                                                                                                │
 │   # NAT-PMP (Port Forwarding) = off                                                                                                                                                                                                             │
 │   # VPN Accelerator = on                                                                                                                                                                                                                        │
 │   PrivateKey = [REDACTED]                                                                                                                                                                                     │
 │   Address = 10.2.0.2/32                                                                                                                                                                                                                         │
 │   DNS = 10.2.0.1                                                                                                                                                                                                                                │
 │                                                                                                                                                                                                                                                 │
 │   [Peer]                                                                                                                                                                                                                                        │
 │   # NL-FREE#157                                                                                                                                                                                                                                 │
 │   PublicKey = V0F3qTpofzp/VUXX8hhmBksXcKJV9hNMOe3D2i3A9lk=                                                                                                                                                                                      │
 │   AllowedIPs = 0.0.0.0/0, ::/0                                                                                                                                                                                                                  │
 │   Endpoint = 185.107.56.106:51820     