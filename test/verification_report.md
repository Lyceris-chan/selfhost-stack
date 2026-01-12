# Verification Report - 1/12/2026, 2:23:23 AM

## Summary
- **Total Tests:** 29
- **Passed:** ✅ 26
- **Failed:** ❌ 2
- **Warnings:** ⚠️ 1

### Connectivity
| Test | Outcome | Details |
|------|---------|---------|
| Dashboard | ✅ PASS | Reached http://10.0.0.222:8081 |
| Hub_API | ✅ PASS | Reached http://10.0.0.222:55555/status |
| AdGuard | ✅ PASS | Reached http://10.0.0.222:8083 |
| Portainer | ✅ PASS | Reached http://10.0.0.222:9000 |
| WireGuard_UI | ✅ PASS | Reached http://10.0.0.222:51821 |
| Memos | ✅ PASS | Reached http://10.0.0.222:5230 |
| Cobalt | ✅ PASS | Reached http://10.0.0.222:9001 |
| SearXNG | ✅ PASS | Reached http://10.0.0.222:8082 |
| Immich | ✅ PASS | Reached http://10.0.0.222:2283 |
| Redlib | ✅ PASS | Reached http://10.0.0.222:8080 |
| Wikiless | ✅ PASS | Reached http://10.0.0.222:8180 |
| Invidious | ✅ PASS | Reached http://10.0.0.222:3000 |
| Rimgo | ✅ PASS | Reached http://10.0.0.222:3002 |
| Scribe | ✅ PASS | Reached http://10.0.0.222:8280 |
| Breezewiki | ✅ PASS | Reached http://10.0.0.222:8380 |
| AnonymousOverflow | ✅ PASS | Reached http://10.0.0.222:8480 |
| VERT | ✅ PASS | Reached http://10.0.0.222:5555 |
| Companion | ✅ PASS | Reached http://10.0.0.222:8283/companion |
| OdidoBooster | ✅ PASS | Reached http://10.0.0.222:8085/docs |

### Invidious
| Test | Outcome | Details |
|------|---------|---------|
| Search | ✅ PASS | Search results found |
| Player Loaded | ✅ PASS | Video player element detected |
| Playback Progress | ⚠️ WARN | Video element found but not progressing (might be paused or buffering) |

### Dashboard
| Test | Outcome | Details |
|------|---------|---------|
| Filter Toggle | ❌ FAIL | Infrastructure category activated |
| Admin Login | ✅ PASS | Admin mode activated |
| Update Modal | ✅ PASS | Update selection modal opened |
| Session Policy Toggle | ✅ PASS | Toggled cleanup: true -> false |
| Log Visibility | ✅ PASS | Logs section visible |
| Log Level Filter | ✅ PASS | Filtered INFO logs: 12 entries found |

### Portainer
| Test | Outcome | Details |
|------|---------|---------|
| Integration | ❌ FAIL | Navigation timeout of 30000 ms exceeded |

