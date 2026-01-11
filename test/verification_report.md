# Verification Report - 1/11/2026, 5:55:06 PM

## Summary
- **Total Tests:** 26
- **Passed:** ✅ 24
- **Failed:** ❌ 2
- **Warnings:** ⚠️ 0

### Connectivity
| Test | Outcome | Details |
|------|---------|---------|
| Dashboard | ✅ PASS | Reached http://127.0.0.1:8081 |
| Hub_API | ✅ PASS | Reached http://127.0.0.1:55555/status |
| AdGuard | ✅ PASS | Reached http://127.0.0.1:8083 |
| Portainer | ✅ PASS | Reached http://127.0.0.1:9000 |
| WireGuard_UI | ✅ PASS | Reached http://127.0.0.1:51821 |
| Memos | ✅ PASS | Reached http://127.0.0.1:5230 |
| Cobalt | ✅ PASS | Reached http://127.0.0.1:9001 |
| SearXNG | ✅ PASS | Reached http://127.0.0.1:8082 |
| Immich | ✅ PASS | Reached http://127.0.0.1:2283 |
| Redlib | ✅ PASS | Reached http://127.0.0.1:8080 |
| Wikiless | ✅ PASS | Reached http://127.0.0.1:8180 |
| Invidious | ✅ PASS | Reached http://127.0.0.1:3000 |
| Rimgo | ✅ PASS | Reached http://127.0.0.1:3002 |
| Scribe | ✅ PASS | Reached http://127.0.0.1:8280 |
| Breezewiki | ✅ PASS | Reached http://127.0.0.1:8380 |
| AnonymousOverflow | ✅ PASS | Reached http://127.0.0.1:8480 |
| VERT | ✅ PASS | Reached http://127.0.0.1:5555 |
| Companion | ✅ PASS | Reached http://127.0.0.1:8282/companion |
| OdidoBooster | ✅ PASS | Reached http://127.0.0.1:8085/docs |

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
| Settings Modal | ✅ PASS | Invidious management modal opened |
| Migrate Dialog | ✅ PASS | Confirmation dialog appeared |
| Session Policy Toggle | ✅ PASS | Toggled cleanup: true -> false |

