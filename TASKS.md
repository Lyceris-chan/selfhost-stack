- anonoverflow name is cut off in admin mode due to the cog 
- when i go into admin mode system logs isnt toggled on by default its because it shows up after login fix this
- all services doesnt properly toggle all categories and should also be a category on its own as well representing the state of all categories enables at the same time
- dedyn cert status is no longer being tracked
- include better ways to go portainer instantly from the admin service chips without cluttering up the chip
- ensure the service status chip stays where the arrow would be till hover as the arrow itself isnt visible till hover anyways 
- updates available banner still persists after dismissal 
- these logs need to be humanized too ensure everything else is covered as well 
lan
"POST /verify-admin HTTP/1.0" 200 -
2025-12-26 02:14:03
lan
UI theme preferences updated
2025-12-26 02:14:04
lan
System health telemetry synchronized
2025-12-26 02:14:16
lan
System health telemetry synchronized
2025-12-26 02:14:31
lan
"POST /toggle-session-cleanup HTTP/1.0" 200 -
2025-12-26 02:14:33
lan
"POST /toggle-session-cleanup HTTP/1.0" 200 -
2025-12-26 02:14:34

- adress these console logs
:8081/api/theme?_=1766715134842:1  Failed to load resource: the server responded with a status of 502 (Bad Gateway)
(index):3739 Failed to load settings from server Error: Server responded with 502
    at loadAllSettings ((index):3688:36)
loadAllSettings @ (index):3739
:8081/odido-api/api/config:1  Failed to load resource: the server responded with a status of 401 (Unauthorized)



 

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