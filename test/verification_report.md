# Verification Report - 1/11/2026, 11:39:42 PM

## Summary
- **Total Tests:** 22
- **Passed:** ✅ 14
- **Failed:** ❌ 8
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
| Immich | ❌ FAIL | net::ERR_CONNECTION_RESET at http://127.0.0.1:2283 |
| Redlib | ❌ FAIL | net::ERR_CONNECTION_RESET at http://127.0.0.1:8080 |
| Wikiless | ✅ PASS | Reached http://127.0.0.1:8180 |
| Invidious | ❌ FAIL | net::ERR_CONNECTION_RESET at http://127.0.0.1:3000 |
| Rimgo | ✅ PASS | Reached http://127.0.0.1:3002 |
| Scribe | ✅ PASS | Reached http://127.0.0.1:8280 |
| Breezewiki | ✅ PASS | Reached http://127.0.0.1:8380 |
| AnonymousOverflow | ✅ PASS | Reached http://127.0.0.1:8480 |
| VERT | ❌ FAIL | net::ERR_CONNECTION_REFUSED at http://127.0.0.1:5555 |
| Companion | ❌ FAIL | net::ERR_CONNECTION_RESET at http://127.0.0.1:8283/companion |
| OdidoBooster | ✅ PASS | Reached http://127.0.0.1:8085/docs |

### Dashboard
| Test | Outcome | Details |
|------|---------|---------|
| Filter Toggle | ❌ FAIL | Infrastructure category activated |
| Admin Login | ❌ FAIL | Login modal still visible (Wrong password?) |

### Portainer
| Test | Outcome | Details |
|------|---------|---------|
| Integration | ❌ FAIL | Navigation timeout of 30000 ms exceeded |

