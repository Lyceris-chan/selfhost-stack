# Verification Report - 1/12/2026, 11:19:35 PM

## Summary
- **Total Tests:** 25
- **Passed:** ✅ 23
- **Failed:** ❌ 1
- **Warnings:** ⚠️ 1

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
| Companion | ✅ PASS | Reached http://10.0.12.167:8283/companion |
| OdidoBooster | ✅ PASS | Reached http://10.0.12.167:8085/docs |

### Invidious
| Test | Outcome | Details |
|------|---------|---------|
| Search | ✅ PASS | Search results found |
| Player Loaded | ✅ PASS | Video player element detected |
| Playback Progress | ⚠️ WARN | Video element found but not progressing (might be paused or buffering) |

### Dashboard
| Test | Outcome | Details |
|------|---------|---------|
| Filter Toggle | ✅ PASS | Infrastructure category activated |
| Admin Login | ✅ PASS | Admin mode activated |

### Global
| Test | Outcome | Details |
|------|---------|---------|
| Suite Execution | ❌ FAIL | Waiting for selector `#update-all-btn` failed |

