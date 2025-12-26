- the theme resets after I toggle light and dark mode ensure that once -c is used everything is removed and set back to defaults so that once the user runs the script its like the first time
- when togging the theme you can see a box around the categories section
- the VPN information looks awesome! but its not clear which VPN its linked to figure out a better way to show the gluetun / wg-easy information without needing users to hover over the icons to know as there isnt even a hover tooltip explaining it now 
- portainer and admin password appears to still be same same everything should have its own unique password 
- the Update banner doesnt stretch across the width of the categories bar like its supposed to
- auto scaling chips only applies after a reload 
- the category info bar saying things like VPN protected Direct access and Infrastructure and the ones for the other groups should also be used to split them in all services view it should look like the user has all options toggled on
- ensure empty headers which wouldnt be populated for non admins dont display for regular users e.g WireGuard Profiles



 

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