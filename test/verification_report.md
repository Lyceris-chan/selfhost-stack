# Verification Report - 1/13/2026, 3:04:04 AM

## Summary
- **Total Tests:** 28
- **Passed:** ✅ 25
- **Failed:** ❌ 3
- **Warnings:** ⚠️ 0

### Connectivity
| Test | Outcome | Details |
|------|---------|---------|
| Dashboard | ✅ PASS | Reached http://10.0.12.167:8081 |
| Hub_API | ✅ PASS | Reached http://10.0.12.167:55555/status |
| AdGuard | ✅ PASS | Reached http://10.0.12.167:8083 |
| Portainer | ✅ PASS | Reached http://10.0.12.167:9000 |
| WireGuard_UI | ✅ PASS | Reached http://10.0.12.167:51821 |
| Memos | ✅ PASS | Reached http://10.0.12.167:5230 |
| Cobalt | ✅ PASS | Reached http://10.0.12.167:9001 |
| SearXNG | ✅ PASS | Reached http://10.0.12.167:8082 |
| Immich | ✅ PASS | Reached http://10.0.12.167:2283 |
| Redlib | ✅ PASS | Reached http://10.0.12.167:8080 |
| Wikiless | ✅ PASS | Reached http://10.0.12.167:8180 |
| Invidious | ✅ PASS | Reached http://10.0.12.167:3000 |
| Rimgo | ✅ PASS | Reached http://10.0.12.167:3002 |
| Scribe | ✅ PASS | Reached http://10.0.12.167:8280 |
| Breezewiki | ✅ PASS | Reached http://10.0.12.167:8380 |
| AnonymousOverflow | ✅ PASS | Reached http://10.0.12.167:8480 |
| VERT | ✅ PASS | Reached http://10.0.12.167:5555 |
| Companion | ✅ PASS | Reached http://10.0.12.167:8283 |
| OdidoBooster | ✅ PASS | Reached http://10.0.12.167:8085/docs |

### Invidious
| Test | Outcome | Details |
|------|---------|---------|
| Search | ✅ PASS | Search results found |
| Functionality | ❌ FAIL | Waiting for selector `video, #player, .video-js, #player-container, iframe, .vjs-tech` failed |

### Dashboard
| Test | Outcome | Details |
|------|---------|---------|
| Filter Toggle | ❌ FAIL | Infrastructure category activated |
| Admin Login | ✅ PASS | Admin mode activated |
| Update Modal | ✅ PASS | Update selection modal opened |
| Session Policy Toggle | ✅ PASS | Toggled cleanup: false -> true |
| Log Visibility | ✅ PASS | Logs section visible |
| Log Level Filter | ✅ PASS | Filtered INFO logs: 3 entries found |

### Portainer
| Test | Outcome | Details |
|------|---------|---------|
| Integration | ❌ FAIL | Navigation timeout of 30000 ms exceeded |

