# Puppeteer Local Tests

These checks exercise the privacy frontends after a local deployment. They open
real pages and confirm that content renders (wiki pages, images, and video).

## Prereqs

- Stack deployed and running.
- Node.js 18+ and npm.
- Network access for the frontends to reach upstream sources.

## Run

```bash
cd tests/puppeteer
npm install
npm test
```

Reports are written to `tests/puppeteer/reports/` by default.

## Configuration

Use environment variables to point at your host/ports or override the exact test
URLs:

- `TEST_HOST` (default: `http://127.0.0.1`)
- `WIKILESS_PORT` (default: `8180`)
- `BREEZEWIKI_PORT` (default: `8380`)
- `REDLIB_PORT` (default: `8080`)
- `RIMGO_PORT` (default: `3002`)
- `INVIDIOUS_PORT` (default: `3000`)
- `WIKILESS_TEST_PATH` (default: `/wiki/OpenAI`)
- `BREEZEWIKI_TEST_PATH` (default: `/wiki/Talus?wiki=paladins`)
- `RIMGO_TEST_PATH` (default: `/dhc04iu`)
- `INVIDIOUS_TEST_PATH` (default: `/watch?v=dQw4w9WgXcQ`)
- `WIKILESS_TEST_URL`, `BREEZEWIKI_TEST_URL`, `REDLIB_TEST_URL`, `RIMGO_TEST_URL`, `INVIDIOUS_TEST_URL`
  (full URL overrides)
- `WIKILESS_EXPECTED_TEXT` and `BREEZEWIKI_EXPECTED_TEXT`
- `TEST_TIMEOUT_MS`, `TEST_NAVIGATION_TIMEOUT_MS`
- `TEST_REPORT_DIR`
- `TEST_CAPTURE_FAILURE_SCREENSHOTS=true`

If your `TEST_HOST` includes a port, set the service-specific `*_URL` instead of
port variables to avoid double-port URLs.

## Notes

- BreezeWiki URL patterns can vary by wiki. If the default test path does not
  load content, set `BREEZEWIKI_TEST_URL` to a known working page.
- Invidious playback availability depends on upstream availability and your
  configured companion instance.
