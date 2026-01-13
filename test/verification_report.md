# Verification Report - 1/13/2026, 8:41:08 AM

## Summary
- **Total Tests:** 22
- **Passed:** ✅ 18
- **Failed:** ❌ 4
- **Warnings:** ⚠️ 0

### Connectivity
| Test | Outcome | Details |
|------|---------|---------|
| Dashboard | ❌ FAIL | net::ERR_CONNECTION_REFUSED at http://10.0.1.225:8081 |
| Hub_API | ✅ PASS | Reached http://10.0.1.225:55555/status |
| AdGuard | ✅ PASS | Reached http://10.0.1.225:8083 |
| Portainer | ✅ PASS | Reached http://10.0.1.225:9000 |
| WireGuard_UI | ✅ PASS | Reached http://10.0.1.225:51821 |
| Memos | ✅ PASS | Reached http://10.0.1.225:5230 |
| Cobalt | ✅ PASS | Reached http://10.0.1.225:9001 |
| SearXNG | ✅ PASS | Reached http://10.0.1.225:8082 |
| Immich | ✅ PASS | Reached http://10.0.1.225:2283 |
| Redlib | ✅ PASS | Reached http://10.0.1.225:8080 |
| Wikiless | ✅ PASS | Reached http://10.0.1.225:8180 |
| Invidious | ✅ PASS | Reached http://10.0.1.225:3000 |
| Rimgo | ✅ PASS | Reached http://10.0.1.225:3002 |
| Scribe | ✅ PASS | Reached http://10.0.1.225:8280 |
| Breezewiki | ✅ PASS | Reached http://10.0.1.225:8380 |
| AnonymousOverflow | ✅ PASS | Reached http://10.0.1.225:8480 |
| VERT | ✅ PASS | Reached http://10.0.1.225:5555 |
| Companion | ❌ FAIL | Navigation timeout of 60000 ms exceeded |
| OdidoBooster | ✅ PASS | Reached http://10.0.1.225:8085/docs |

### Invidious
| Test | Outcome | Details |
|------|---------|---------|
| Search | ✅ PASS | Search results found |
| Functionality | ❌ FAIL | Waiting for selector `video, #player, .video-js, #player-container, iframe, .vjs-tech` failed |

### Global
| Test | Outcome | Details |
|------|---------|---------|
| Suite Execution | ❌ FAIL | net::ERR_CONNECTION_REFUSED at http://10.0.1.225:8081 |

