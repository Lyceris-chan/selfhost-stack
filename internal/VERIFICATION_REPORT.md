# 🛡️ Privacy Hub Verification Report

Generated on: 2025-12-23T02:50:43.736Z

## UI & Logic Consistency (Puppeteer)

| Check | Status | Details |
| :--- | :--- | :--- |
| API Status Text (Desktop) | ✅ PASS | "Found: Connected" |
| Console Errors (Desktop) | ✅ PASS | [] |
| Layout Overlap (Desktop) | ✅ PASS | "No overlaps detected" |
| Autocomplete Attributes | ✅ PASS | {"domain":true,"token":true,"odidoKey":true,"odidoToken":true} |
| Event Propagation (Chip vs Card) | ✅ PASS | "Chip click should not trigger card navigation" |
| Label Renaming (Safe Display Mode) | ✅ PASS | "Found: Safe Display Mode" |
| DNS DOQ Inclusion | ✅ PASS | - |
| API Status Text (Mobile) | ✅ PASS | "Found: Connected" |
| Console Errors (Mobile) | ✅ PASS | [] |
| Layout Overlap (Mobile) | ✅ PASS | "No overlaps detected" |
| Portainer Telemetry Disabled (UI) | ✅ PASS | {"found":true,"checked":false,"label":"Community Edition2.33.6 LTS SettingsSettingsportainerApplication settingsSnapshot interval*Edge agent default poll frequency5 seconds10 seconds30 seconds5 minutes1 hour1 dayUse custom logoAllow the collection of anonymous statisticsYou can find more information about this in our privacy policy.Login screen bannerBusiness FeatureYou can set a custom banner that will be shown to all users during login.App TemplatesYou can specify the URL to your own template definitions file here. See Portainer documentation for more details.The default value is https://raw.githubusercontent.com/portainer/templates/v3/templates.jsonURLSave application settingsKubernetes settingsHelm repositoryYou can specify the URL to your own Helm repository here.URLKubeconfigKubeconfig expiryNo expiryDeployment optionsEnforce code-based deploymentBusiness FeatureRequire a note on applicationsBusiness FeatureAllow stacks functionality with Kubernetes environmentsSave Kubernetes settingsBusiness FeatureCertificate Authority file for Kubernetes Helm repositoriesProvide an additional CA file containing certificate(s) for HTTPS connections to Helm repositories.CA fileSelect a fileActionsApply changesSSL certificateForcing HTTPs only will cause Portainer to stop listening on the HTTP port. Any edge agent environment that is using HTTP will no longer be available.Force HTTPS onlyProvide a new SSL Certificate to replace the existing one that is used for HTTPS connections.SSL/TLS certificateSelect a fileSSL/TLS private keySelect a fileSave SSL settingsHidden containersYou can hide containers with specific labels from Portainer UI. You need to specify the label name and value.NameValueAdd filterNameValueNo filter available.Back up PortainerBackup configurationThis will back up your Portainer server configuration and does not include containers.Download backup fileBusiness FeatureStore in S3Define a cron scheduleSecurity settingsPassword ProtectDownload backup"} |

## API & Infrastructure Audit

- [x] **hub-api entrypoint**: Verified `python3` usage.
- [x] **Nginx Proxy**: Verified direct service name mapping (hub-api:55555).
- [x] **Portainer Auth**: Verified `admin` default for bcrypt hash.
- [x] **Shell Quality**: Verified `shellcheck` compliance.
