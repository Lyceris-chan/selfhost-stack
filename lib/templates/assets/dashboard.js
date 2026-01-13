/**
 * @fileoverview Main dashboard logic for ZimaOS Privacy Hub.
 * Adheres to Material Design 3 and Google JavaScript Style Guide.
 */

// Dynamic Service Rendering
let serviceCatalog = {};

/**
 * Humanizes a service ID for display.
 * @param {string} id The service ID.
 * @return {string} The human-readable name.
 */
function humanizeServiceId(id) {
  return id
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/**
 * Loads the service catalog from the API.
 * @return {Promise<Object>} The service catalog.
 */
async function loadServiceCatalog() {
  if (Object.keys(serviceCatalog).length) return serviceCatalog;
  try {
    const res = await apiCall('/services');
    const data = await res.json();
    serviceCatalog = data.services || {};
  } catch (e) {
    console.warn('Failed to load service catalog:', e);
    serviceCatalog = {};
  }
  return serviceCatalog;
}

/**
 * Normalizes service metadata with defaults.
 * @param {string} id Service ID.
 * @param {Object} meta Raw metadata.
 * @return {Object} Normalized metadata.
 */
function normalizeServiceMeta(id, meta) {
  const safe = (meta && typeof meta === 'object') ? meta : {};
  return {
    name: safe.name || humanizeServiceId(id),
    description: safe.description || 'Private service hosted locally.',
    category: safe.category || 'apps',
    url: safe.url || '',
    source_url: safe.source_url || '',
    patch_url: safe.patch_url || '',
    actions: Array.isArray(safe.actions) ? safe.actions : [],
    chips: Array.isArray(safe.chips) ? safe.chips : [],
    order: Number.isFinite(safe.order) ? safe.order : 999
  };
}

/**
 * Handles service-specific actions.
 * @param {string} id Service ID.
 * @param {Object} action Action metadata.
 * @param {Event} event The triggering event.
 */
function handleServiceAction(id, action, event) {
  if (event) {
    event.preventDefault();
    event.stopPropagation();
  }
  if (!action || !action.type) return;
  if (action.type === 'migrate') {
    const mode = action.mode || 'migrate';
    const confirmFlag = action.confirm ? 'yes' : 'no';
    migrateService(id, mode, confirmFlag, event);
    return;
  }
  if (action.type === 'vacuum') {
    vacuumServiceDb(id, event);
    return;
  }
  if (action.type === 'clear-logs') {
    clearServiceLogs(id, event);
  }
}

/**
 * Creates an action button element.
 * @param {string} id Service ID.
 * @param {Object} action Action metadata.
 * @return {HTMLButtonElement} The button element.
 */
function createActionButton(id, action) {
  const button = document.createElement('button');
  button.className = 'chip admin admin-only';
  button.type = 'button';
  const label = action.label || 'Action';
  if (action.icon) {
    const icon = document.createElement('span');
    icon.className = 'material-symbols-rounded';
    icon.textContent = action.icon;
    button.appendChild(icon);
  }
  button.appendChild(document.createTextNode(label));
  button.setAttribute('data-tooltip', label);
  button.onclick = (e) => handleServiceAction(id, action, e);
  return button;
}

/**
 * Creates a chip element.
 * @param {string} id Service ID.
 * @param {Object|string} chip Chip metadata or label.
 * @return {HTMLSpanElement} The chip element.
 */
function createChipElement(id, chip) {
  const chipEl = document.createElement('span');
  const isObject = chip && typeof chip === 'object';
  const label = isObject ? (chip.label || '') : String(chip || '');
  const variant = isObject ? (chip.variant || '') : 'admin';
  const classes = ['chip'];
  if (variant) {
    variant.split(' ').forEach((c) => c && classes.push(c));
    if (variant.includes('admin')) classes.push('admin-only');
  }
  if (isObject && chip.portainer) {
    classes.push('portainer-link');
    chipEl.dataset.container = id;
    chipEl.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      const info = containerIds[id];
      const cid = info ? info.id : null;
      const url = cid ?
        PORTAINER_URL + '/#!/1/docker/containers/' + cid :
        PORTAINER_URL + '/#!/1/docker/containers';
      window.open(url, '_blank');
    };
  }
  chipEl.className = classes.join(' ');
  if (isObject && chip.tooltip) chipEl.setAttribute('data-tooltip', chip.tooltip);
  if (isObject && chip.icon) {
    const icon = document.createElement('span');
    icon.className = 'material-symbols-rounded';
    icon.textContent = chip.icon;
    chipEl.appendChild(icon);
    chipEl.appendChild(document.createTextNode('\u00A0')); // Non-breaking space
  }
  chipEl.appendChild(document.createTextNode(label));
  return chipEl;
}

/**
 * Renders the dynamic grid of service cards.
 */
async function renderDynamicGrid() {
  try {
    const [containerRes, catalog] = await Promise.all([
      apiCall('/containers'),
      loadServiceCatalog()
    ]);
    const data = await containerRes.json();
    const activeContainers = data.containers || {};
    containerIds = activeContainers;

    const helperServices = [
      'companion', 'invidious-db', 'wikiless_redis', 'searxng-redis',
      'immich-db', 'immich-redis', 'immich-ml', 'docker-proxy',
      'redis', 'postgres', 'db'
    ];

    const entries = Object.entries(catalog)
      .filter(([id]) => {
        const info = activeContainers[id];
        if (!info) return false;
        if (helperServices.includes(id)) return false;
        if (id.endsWith('-db') || id.endsWith('_db') || id.endsWith('-redis') || id.endsWith('_redis')) return false;
        return true;
      })
      .map(([id, meta]) => {
        const normalized = normalizeServiceMeta(id, meta);
        normalized.url = getServiceUrl(id, normalized.url);
        return [id, normalized];
      });

    const buckets = { apps: [], system: [], tools: [], all: [] };
    entries.forEach(([id, meta]) => {
      if (!buckets[meta.category]) buckets[meta.category] = [];
      buckets[meta.category].push([id, meta]);
      buckets.all.push([id, meta]);
    });

    const sortByOrder = (a, b) => {
      const orderDelta = (a[1].order || 999) - (b[1].order || 999);
      if (orderDelta !== 0) return orderDelta;
      return a[1].name.localeCompare(b[1].name);
    };

    const syncGrid = (gridId, items) => {
      const grid = document.getElementById(gridId);
      if (!grid) return;
      const sorted = items ? items.sort(sortByOrder) : [];
      const currentIds = new Set(sorted.map((x) => x[0]));

      Array.from(grid.children).forEach((card) => {
        if (!currentIds.has(card.dataset.container)) grid.removeChild(card);
      });

      sorted.forEach(([id, meta]) => {
        let card = grid.querySelector(`[data-container="${id}"]`);
        if (!card) {
          const hardened = activeContainers[id] && activeContainers[id].hardened;
          card = createServiceCard(id, meta, hardened);
          grid.appendChild(card);
        } else {
          card.dataset.url = meta.url || '';
          grid.appendChild(card); // Reorder
        }
      });
    };

    ['apps', 'system', 'tools'].forEach((cat) => syncGrid(`grid-${cat}`, buckets[cat]));

    fetchMetrics();
  } catch (e) {
    console.error('Failed to render dynamic grid:', e);
  }
}

/**
 * Creates a service card element.
 * @param {string} id Service ID.
 * @param {Object} meta Service metadata.
 * @param {boolean} hardened Whether the service is hardened.
 * @return {HTMLDivElement} The card element.
 */
function createServiceCard(id, meta, hardened = false) {
  const card = document.createElement('div');
  card.className = 'card';
  card.dataset.url = meta.url || '';
  card.dataset.container = id;
  card.dataset.check = 'true';
  card.onclick = (e) => navigate(card, e);

  const header = document.createElement('div');
  header.className = 'card-header';

  const title = document.createElement('h2');
  title.className = 'title-large';
  title.textContent = meta.name || humanizeServiceId(id);

  const titleRow = document.createElement('div');
  titleRow.className = 'card-title-row';
  titleRow.appendChild(title);

  const actionsWrap = document.createElement('div');
  actionsWrap.className = 'card-header-actions';

  const indicator = document.createElement('div');
  indicator.className = 'status-indicator';
  const dot = document.createElement('span');
  dot.className = 'status-dot';
  const text = document.createElement('span');
  text.className = 'label-medium';
  text.textContent = 'Connecting...';
  indicator.appendChild(dot);
  indicator.appendChild(text);

  const settingsBtn = document.createElement('button');
  settingsBtn.className = 'btn btn-icon settings-btn admin-only';
  settingsBtn.setAttribute('data-tooltip', 'Service Management & Metrics');
  settingsBtn.onclick = (e) => openServiceSettings(id, e);
  const settingsIcon = document.createElement('span');
  settingsIcon.className = 'material-symbols-rounded';
  settingsIcon.textContent = 'settings';
  settingsBtn.appendChild(settingsIcon);

  const navArrow = document.createElement('span');
  navArrow.className = 'material-symbols-rounded nav-arrow';
  navArrow.textContent = 'arrow_forward';

  actionsWrap.appendChild(indicator);
  actionsWrap.appendChild(settingsBtn);

  if (meta.url && meta.url !== '#' && meta.url !== '') {
    actionsWrap.appendChild(navArrow);
  }

  header.appendChild(titleRow);
  header.appendChild(actionsWrap);

  const desc = document.createElement('p');
  desc.className = 'description body-medium';
  desc.textContent = meta.description || 'Private service hosted locally.';

  const chipBox = document.createElement('div');
  chipBox.className = 'chip-box';

  const pChip = createChipElement(id, {
    label: 'Portainer',
    icon: 'settings',
    variant: 'admin tonal',
    tooltip: 'Direct Container Management',
    portainer: true
  });
  chipBox.appendChild(pChip);

  if (meta.local || id === 'vert') {
    const localChip = createChipElement(id, {
      label: 'Local',
      icon: 'shield',
      variant: 'tertiary',
      tooltip: 'This service is not connected to the internet and all data processing happens locally.',
      portainer: false
    });
    chipBox.appendChild(localChip);
  }

  if (Array.isArray(meta.actions)) {
    meta.actions.forEach((action) => {
      chipBox.appendChild(createActionButton(id, action));
    });
  }
  if (Array.isArray(meta.chips)) {
    meta.chips.forEach((chip) => {
      chipBox.appendChild(createChipElement(id, chip));
    });
  }

  card.appendChild(header);
  card.appendChild(desc);
  card.appendChild(chipBox);

  if (meta.url === '#' || meta.url === '') {
    card.style.cursor = 'default';
    card.onclick = null;
  }

  return card;
}

        // Initialize dynamic grid
        document.addEventListener('DOMContentLoaded', () => {
            initPrivacyMode();
            initLinkMode();
            initTheme();
            renderDynamicGrid();
            initMacAdvisory();
            fetchUpdates();
            
            const sysProjEl = document.getElementById('sys-project-size');
            if (sysProjEl) {
                sysProjEl.parentElement.style.cursor = 'pointer';
                sysProjEl.parentElement.onclick = openProjectSizeModal;
            }

            // Refresh grid occasionally to catch new services
            setInterval(renderDynamicGrid, 30000);
            setInterval(fetchUpdates, 60000);
        });

        const API = "/api"; 
        const ODIDO_API = "/api/odido-proxy";
        
        function filterCategory(cat) {
            const chip = document.querySelector(`.filter-chip[data-target="${cat}"]`);
            if (!chip) return;

            const mainChips = Array.from(document.querySelectorAll('.filter-chip:not([data-target="all"]):not([data-target="logs"])'));
            const allChip = document.querySelector('.filter-chip[data-target="all"]');

            if (cat === 'all') {
                const isActive = chip.classList.contains('active');
                if (!isActive) {
                    // Turn everything ON
                    chip.classList.add('active');
                    mainChips.forEach(c => c.classList.add('active'));
                } else {
                    // Clicking 'All' while active resets to all active.
                    mainChips.forEach(c => c.classList.add('active'));
                }
            } else {
                chip.classList.toggle('active');
                
                // Update 'All' chip state based on main categories
                const allActive = mainChips.every(c => c.classList.contains('active'));
                if (allChip) allChip.classList.toggle('active', allActive);
                
                // Ensure at least one chip is active (except logs)
                const anyActive = document.querySelector('.filter-chip.active:not([data-target="logs"]):not([data-target="all"])');
                if (!anyActive) {
                    chip.classList.add('active');
                }
            }
            
            updateGridVisibility();
            syncSettings(); 
        }

        function updateGridVisibility() {
            const activeChips = Array.from(document.querySelectorAll('.filter-chip.active'));
            const activeTargets = activeChips.map(c => c.dataset.target);
            
            const sections = document.querySelectorAll('section[data-category]');
            sections.forEach(s => {
                const cat = s.dataset.category;
                
                if (activeTargets.includes(cat) || (activeTargets.includes('all') && cat !== 'logs')) {
                    s.style.display = 'block';
                    s.classList.remove('hidden');
                } else {
                    s.style.display = 'none';
                    s.classList.add('hidden');
                }
            });
            
            localStorage.setItem('dashboard_filter', activeTargets.filter(t => t !== 'all').join(','));
        }

        // Global State & Data
        let isAdmin = sessionStorage.getItem('is_admin') === 'true';
        let sessionToken = sessionStorage.getItem('session_token') || '';
        let sessionCleanupEnabled = true;
        let containerMetrics = {};
        let containerIds = {};
        let pendingUpdates = [];

        function updateAdminUI() {
            document.body.classList.toggle('admin-mode', isAdmin);
            const icon = document.getElementById('admin-icon');
            if (icon) {
                icon.textContent = isAdmin ? 'admin_panel_settings' : 'lock_person';
                icon.parentElement.style.background = isAdmin ? 'var(--md-sys-color-primary-container)' : '';
                icon.style.color = isAdmin ? 'var(--md-sys-color-on-primary-container)' : 'inherit';
            }
            const btn = document.getElementById('admin-lock-btn');
            if (btn) btn.dataset.tooltip = isAdmin ? "Exit Admin Mode" : "Enter Admin Mode";

            // Session cleanup UI
            const switchEl = document.getElementById('session-cleanup-switch');
            const warningEl = document.getElementById('session-cleanup-warning');
            if (switchEl) switchEl.classList.toggle('active', sessionCleanupEnabled);
            
            if (isAdmin) {
                // Admin UI updates
            }

            if (warningEl && isAdmin) {
                warningEl.style.display = 'flex';
                const wIcon = document.getElementById('session-warning-icon');
                const wTitle = document.getElementById('session-warning-title');
                const wText = document.getElementById('session-warning-text');
                
                if (sessionCleanupEnabled) {
                    warningEl.style.background = 'var(--md-sys-color-surface-container-highest)';
                    warningEl.style.color = 'var(--md-sys-color-on-surface-variant)';
                    warningEl.style.borderColor = 'var(--md-sys-color-outline-variant)';
                    if (wIcon) wIcon.textContent = 'info';
                    if (wTitle) wTitle.textContent = 'Security Recommendation';
                    if (wText) wText.textContent = 'Session auto-cleanup is currently active. Your admin session will expire automatically for safety.';
                } else {
                    warningEl.style.background = 'var(--md-sys-color-error-container)';
                    warningEl.style.color = 'var(--md-sys-color-on-error-container)';
                    warningEl.style.borderColor = 'var(--md-sys-color-error)';
                    if (wIcon) wIcon.textContent = 'warning';
                    if (wTitle) wTitle.textContent = 'Security Warning';
                    if (wText) wText.textContent = 'Session auto-cleanup is disabled. Administrative access will remain active indefinitely until manually exited.';
                }
            } else if (warningEl) {
                warningEl.style.display = 'none';
            }
        }

        async function toggleSessionCleanup() {
            const newState = !sessionCleanupEnabled;
            try {
                const res = await apiCall("/toggle-session-cleanup", {
                    method: 'POST',
                    body: JSON.stringify({ enabled: newState })
                });
                const data = await res.json();
                if (data.success) {
                    sessionCleanupEnabled = data.enabled;
                    updateAdminUI();
                    showSnackbar(sessionCleanupEnabled ? "Session auto-cleanup enabled" : "Session auto-cleanup disabled (Persistent Mode)");
                }
            } catch (e) {
                showSnackbar("Failed to toggle session cleanup");
            }
        }

        async function toggleAdminMode() {
            if (isAdmin) {
                if (await showDialog({
                    title: 'Exit Admin Mode?',
                    message: "Exit Admin Mode? Management features will be hidden.",
                    confirmText: 'Exit',
                    confirmClass: 'btn btn-tonal'
                })) {
                    isAdmin = false;
                    sessionStorage.setItem('is_admin', 'false');
                    sessionStorage.removeItem('session_token');
                    sessionToken = '';
                    updateAdminUI();
                    syncSettings();
                    showSnackbar("Admin Mode disabled");
                }
            } else {
                openLoginModal();
            }
        }

        function openLoginModal() {
            const modal = document.getElementById('login-modal');
            const input = document.getElementById('admin-password-input');
            if (modal) {
                modal.style.display = 'flex';
                if (input) {
                    input.value = '';
                    setTimeout(() => input.focus(), 100);
                }
            }
        }

        function closeLoginModal() {
            const modal = document.getElementById('login-modal');
            if (modal) modal.style.display = 'none';
        }

        async function submitLogin() {
            const input = document.getElementById('admin-password-input');
            const pass = input.value;
            if (!pass) return;

            try {
                const res = await apiCall("/verify-admin", {
                    method: 'POST',
                    body: JSON.stringify({ password: pass })
                });
                if (res.ok) {
                    const data = await res.json();
                    isAdmin = true;
                    sessionToken = data.token || '';
                    sessionCleanupEnabled = data.cleanup !== false;
                    sessionStorage.setItem('is_admin', 'true');
                    if (sessionToken) sessionStorage.setItem('session_token', sessionToken);
                    updateAdminUI();
                    syncSettings();
                    showSnackbar("Admin Mode enabled. Management tools unlocked.", "Dismiss");
                    closeLoginModal();
                } else {
                    showSnackbar("Authentication failed: Invalid password", "Retry", () => {
                        input.focus();
                        input.select();
                    });
                    input.classList.add('error'); // Assuming you might add error styling later
                    setTimeout(() => input.classList.remove('error'), 500);
                }
            } catch(e) {
                showSnackbar("Error connecting to auth service");
            }
        }
        let realProfileName = '';
        let maskedProfileId = '';
        const profileMaskMap = {};
        let odidoHistory = [];

        async function updateOdidoGraph(rate, remaining) {
            const now = Date.now();
            odidoHistory.push({ time: now, rate: rate, remaining: remaining });
            if (odidoHistory.length > 50) odidoHistory.shift();

            const svg = document.getElementById('odido-graph');
            const line = document.getElementById('graph-line');
            const area = document.getElementById('graph-area');
            const speedIndicator = document.getElementById('odido-speed-indicator');
            if (!svg || !line || !area) return;

            const width = 400;
            const height = 120;
            
            // Smooth the rate for the graph
            const smoothHistory = odidoHistory.map((d, i) => {
                const start = Math.max(0, i - 2);
                const end = Math.min(odidoHistory.length - 1, i + 2);
                const subset = odidoHistory.slice(start, end + 1);
                const avgRate = subset.reduce((acc, curr) => acc + curr.rate, 0) / subset.length;
                return { ...d, smoothRate: avgRate };
            });

            const maxRate = Math.max(...smoothHistory.map(d => d.smoothRate), 0.1);
            
            // Speed indicator (MB/min to Mb/s: * 8 / 60)
            const speedMbs = (rate * 8 / 60).toFixed(2);
            if (speedIndicator) {
                speedIndicator.textContent = speedMbs + " Mb/s";
                speedIndicator.style.display = rate > 0 ? 'block' : 'none';
            }

            if (smoothHistory.length < 2) return;

            let points = "";
            smoothHistory.forEach((d, i) => {
                const x = (i / (smoothHistory.length - 1)) * width;
                const y = height - (d.smoothRate / (maxRate * 1.2)) * height;
                points += (i === 0 ? "M" : " L") + x + "," + y;
            });

            line.setAttribute("d", points);
            area.setAttribute("d", points + " L" + width + "," + height + " L0," + height + " Z");
        }

        async function fetchMetrics() {
            try {
                const res = await apiCall("/metrics");
                if (!res.ok) return;
                const data = await res.json();
                containerMetrics = data.metrics || {};
            } catch(e) { console.error("Metrics fetch error:", e); }
        }

        function getPortainerBaseUrl() {
            if (window.location.hostname !== '$LAN_IP' && !window.location.hostname.match(/^\d+\.\d+\.\d+\.\d+$/)) {
                const parts = window.location.hostname.split('.');
                if (parts.length >= 2) {
                    const domain = parts.slice(-2).join('.');
                    const port = window.location.port ? ":" + window.location.port : "";
                    return "https://portainer." + domain + port;
                }
            }
            return "http://$LAN_IP:$PORT_PORTAINER";
        }

        const PORTAINER_URL = getPortainerBaseUrl();

        function getServiceUrl(serviceId, defaultUrl) {
            const hasDesec = "$DESEC_DOMAIN" !== "";
            const isHttps = window.location.protocol === 'https:';
            const currentHostname = window.location.hostname;
            const useDomainPref = localStorage.getItem('link_mode_domain') === 'true';
            
            // If admin explicitly wants IP links, return default (IP) unless it's empty
            if (isAdmin && !useDomainPref) {
                return defaultUrl;
            }

            if (hasDesec && (currentHostname.endsWith("$DESEC_DOMAIN") || isHttps || (isAdmin && useDomainPref))) {
                const port = window.location.port ? ":" + window.location.port : "";
                // Map service IDs to their subdomain names if different
                const subdomainMap = {
                    'adguard': 'adguard',
                    'portainer': 'portainer',
                    'wg-easy': 'wireguard',
                    'hub-api': 'hub',
                    'odido-booster': 'odido',
                    'anonymousoverflow': 'anonymousoverflow',
                    'invidious': 'invidious',
                    'redlib': 'redlib',
                    'searxng': 'searxng',
                    'immich-server': 'immich',
                    'memos': 'memos',
                    'cobalt': 'cobalt'
                };
                const sub = subdomainMap[serviceId] || serviceId;
                return window.location.protocol + "//" + sub + "." + "$DESEC_DOMAIN" + port;
            }
            return defaultUrl;
        }
        
        let odidoApiKey = sessionStorage.getItem('odido_api_key') || '';

        function getAuthHeaders() {
            const headers = { 'Content-Type': 'application/json' };
            if (sessionToken) headers['X-Session-Token'] = sessionToken;
            return headers;
        }

        async function apiCall(endpoint, options = {}) {
            const baseUrl = options.baseUrl || API;
            const url = endpoint.startsWith('http') ? endpoint : baseUrl + endpoint;
            const headers = { ...getAuthHeaders(), ...(options.headers || {}) };
            
            try {
                const res = await fetch(url, { ...options, headers });
                
                if (res.status === 401) {
                    if (isAdmin) {
                        isAdmin = false;
                        sessionStorage.setItem('is_admin', 'false');
                        sessionStorage.removeItem('session_token');
                        sessionToken = '';
                        updateAdminUI();
                        showSnackbar("Session expired. Please log in again.");
                    }
                }
                
                return res;
            } catch (e) {
                console.error(`API Call failed: ${endpoint}`, e);
                throw e;
            }
        }

        function dismissUpdateBanner() {
            const banner = document.getElementById('update-banner');
            if (banner) banner.classList.add('hidden-banner');
            localStorage.setItem('update_banner_dismissed', pendingUpdates.sort().join(','));
        }

        function dismissMacAdvisory() {
            const banner = document.getElementById('mac-advisory');
            if (banner) banner.classList.add('hidden-banner');
            localStorage.setItem('mac_advisory_dismissed_v2', 'true');
        }

        function initMacAdvisory() {
            const banner = document.getElementById('mac-advisory');
            if (banner) {
                if (localStorage.getItem('mac_advisory_dismissed_v2') === 'true') {
                    banner.classList.add('hidden-banner');
                } else {
                    banner.style.display = 'block';
                    banner.classList.remove('hidden-banner');
                }
            }
        }

        async function fetchUpdates() {
            if (!isAdmin) return;
            try {
                const res = await apiCall("/updates");
                if (!res.ok) return;
                const data = await res.json();
                const updates = data.updates || {};
                pendingUpdates = Object.keys(updates).sort();
                
                const banner = document.getElementById('update-banner');
                const list = document.getElementById('update-list');
                
                if (pendingUpdates.length > 0) {
                    const dismissed = localStorage.getItem('update_banner_dismissed');
                    if (dismissed === pendingUpdates.join(',')) {
                        if (banner) banner.classList.add('hidden-banner');
                    } else {
                        if (banner) {
                            banner.classList.remove('hidden-banner');
                            banner.style.display = ''; // Reset inline style
                        }
                        if (list) list.textContent = "Updates available for: " + pendingUpdates.join(", ");
                    }
                } else {
                    if (banner) banner.classList.add('hidden-banner');
                }
            } catch(e) {}
        }

        async function openServiceSettings(name, e) {
            if (e) { e.preventDefault(); e.stopPropagation(); }
            await showServiceModal(name);
        }

        async function showServiceModal(name) {
            const modal = document.getElementById('service-modal');
            const title = document.getElementById('modal-service-name');
            const actions = document.getElementById('modal-actions');
            title.textContent = name.charAt(0).toUpperCase() + name.slice(1) + " settings";
            
            // Ensure we have the latest IDs
            await fetchContainerIds();
            
            // Basic actions for all
            const containerInfo = containerIds[name];
            const cid = containerInfo ? containerInfo.id : null;
            const portainerLink = cid ?
                PORTAINER_URL + "/#!/1/docker/containers/" + cid :
                PORTAINER_URL + "/#!/1/docker/containers";
            
            actions.innerHTML = ''; // Clear existing

            // Helper for creating modal buttons
            const createModalBtn = (text, icon, onClick, variant = 'tonal', style = '') => {
                const btn = document.createElement('button');
                btn.className = `btn btn-${variant}`;
                btn.style.width = '100%';
                if (style) btn.style.cssText += style;
                btn.onclick = onClick;
                
                const iconSpan = document.createElement('span');
                iconSpan.className = 'material-symbols-rounded';
                iconSpan.textContent = icon;
                
                btn.appendChild(iconSpan);
                btn.appendChild(document.createTextNode(' ' + text));
                return btn;
            };

            // Update Button
            actions.appendChild(createModalBtn('Update service', 'update', (e) => updateService(name, e), 'tonal'));
            
            // Note
            const note = document.createElement('p');
            note.className = 'body-small';
            note.style.cssText = 'margin: 4px 0 12px 0; color: var(--md-sys-color-on-surface-variant);';
            note.textContent = 'Note: Updates may cause temporary high CPU/RAM usage during build.';
            actions.appendChild(note);
            
            // Portainer Button
            actions.appendChild(createModalBtn('View in Portainer', 'dock', () => window.open(portainerLink, '_blank'), 'outlined'));

            // Specialized actions
            if (name === 'invidious') {
                actions.appendChild(createModalBtn('Migrate database', 'database_upload', (e) => migrateService('invidious', e), 'filled'));
                actions.appendChild(createModalBtn('Wipe all data', 'delete_forever', (e) => clearServiceDb('invidious', e), 'tonal', 'color:var(--md-sys-color-error)'));
            } else if (name === 'adguard') {
                actions.appendChild(createModalBtn('Clear query logs', 'auto_delete', (e) => clearServiceLogs('adguard', e), 'tonal'));
            } else if (name === 'memos') {
                actions.appendChild(createModalBtn('Optimize database', 'compress', (e) => vacuumServiceDb('memos', e), 'tonal'));
            }

            modal.style.display = 'flex';
            updateModalMetrics(name);
        }

        function closeServiceModal() {
            document.getElementById('service-modal').style.display = 'none';
        }

        function updateModalMetrics(name) {
            const m = containerMetrics[name];
            if (m) {
                const cpu = parseFloat(m.cpu) || 0;
                document.getElementById('modal-cpu-text').textContent = cpu.toFixed(1) + "%";
                document.getElementById('modal-cpu-fill').style.width = Math.min(100, cpu) + "%";
                
                const mem = parseFloat(m.mem) || 0;
                const limit = parseFloat(m.limit) || 1;
                const memPercent = Math.min(100, (mem / limit) * 100);
                document.getElementById('modal-mem-text').textContent = Math.round(mem) + " MB / " + Math.round(limit) + " MB";
                document.getElementById('modal-mem-fill').style.width = memPercent + "%";
            }
        }

        async function updateAllServices() {
            openUpdateModal();
        }

        let isAllSelected = true;

        function openUpdateModal() {
            const modal = document.getElementById('update-selection-modal');
            modal.style.display = 'flex';
            document.getElementById('start-update-btn').disabled = true;
            
            // Trigger check
            apiCall("/check-updates");
            
            // Poll for results
            const listContainer = document.getElementById('update-list-container');
            const statusLabel = document.getElementById('update-fetch-status');
            
            let attempts = 0;
            const poll = setInterval(async () => {
                attempts++;
                statusLabel.textContent = "Scanning repositories... (" + attempts + ")";
                try {
                    const res = await apiCall("/updates");
                    const data = await res.json();
                    const updates = data.updates || {};
                    const keys = Object.keys(updates);
                    
                    if (keys.length > 0 || attempts > 30) {
                        clearInterval(poll);
                        renderUpdateList(keys);
                        statusLabel.textContent = keys.length > 0 ? keys.length + " updates found." : "No updates found.";
                        document.getElementById('start-update-btn').disabled = keys.length === 0;
                    }
                } catch(e) {}
            }, 2000);
        }

        function closeUpdateModal() {
            document.getElementById('update-selection-modal').style.display = 'none';
        }

        function renderUpdateList(services) {
            const el = document.getElementById('update-list-container');
            el.innerHTML = '';
            if (services.length === 0) {
                const emptyState = document.createElement('div');
                emptyState.style.cssText = 'padding: 24px; text-align: center; opacity: 0.7;';
                emptyState.textContent = 'No updates found. System is up to date.';
                el.appendChild(emptyState);
                return;
            }
            services.forEach(svc => {
                const row = document.createElement('div');
                row.className = 'list-item';
                row.style.cssText = 'margin: 4px 0; background: transparent; border: none;';

                const container = document.createElement('div');
                container.style.cssText = 'display:flex; align-items:center; justify-content:space-between; width:100%;';

                const label = document.createElement('label');
                label.style.cssText = 'display:flex; align-items:center; gap:12px; cursor:pointer; flex-grow:1;';

                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.className = 'update-checkbox';
                checkbox.value = svc;
                checkbox.checked = true;
                checkbox.style.cssText = 'width:18px; height:18px; accent-color:var(--md-sys-color-primary);';

                const text = document.createElement('span');
                text.className = 'list-item-text';
                text.textContent = svc;

                label.appendChild(checkbox);
                label.appendChild(text);

                const actions = document.createElement('div');
                actions.style.cssText = 'display:flex; gap:8px; align-items:center;';

                const btn = document.createElement('button');
                btn.className = 'btn btn-icon';
                btn.style.cssText = 'width:32px; height:32px;';
                btn.setAttribute('data-tooltip', 'View changes');
                btn.onclick = () => viewChangelog(svc);
                
                const icon = document.createElement('span');
                icon.className = 'material-symbols-rounded';
                icon.style.fontSize = '18px';
                icon.textContent = 'description';
                btn.appendChild(icon);

                const chip = document.createElement('span');
                chip.className = 'chip tertiary';
                chip.style.cssText = 'height:24px; font-size:11px;';
                chip.textContent = 'Update available';

                actions.appendChild(btn);
                actions.appendChild(chip);

                container.appendChild(label);
                container.appendChild(actions);
                row.appendChild(container);
                el.appendChild(row);
            });
        }

        async function viewChangelog(service) {
            const modal = document.getElementById('changelog-modal');
            const title = document.getElementById('changelog-title');
            const content = document.getElementById('changelog-content');
            
            title.textContent = "Changes: " + service;
            content.textContent = "Fetching release notes...";
            modal.style.display = 'flex';
            
            try {
                const res = await apiCall("/changelog?service=" + service);
                const data = await res.json();
                
                if (data.error) throw new Error(data.error);
                content.textContent = data.changelog || "No changelog information available.";
            } catch (e) {
                content.textContent = "Failed to load changelog: " + e.message;
            }
        }

        function toggleAllUpdates() {
            const checkboxes = document.querySelectorAll('.update-checkbox');
            const anyUnchecked = Array.from(checkboxes).some(cb => !cb.checked);
            
            checkboxes.forEach(cb => cb.checked = anyUnchecked);
            isAllSelected = anyUnchecked;
            
            const startBtn = document.getElementById('start-update-btn');
            if (startBtn) startBtn.disabled = !anyUnchecked && checkboxes.length > 0;
            // If all were checked and we unchecked all, button should be disabled.
            // If any were unchecked and we checked all, button should be enabled.
            const anyChecked = Array.from(checkboxes).some(cb => cb.checked);
            if (startBtn) startBtn.disabled = !anyChecked;
        }

        async function startBatchUpdate() {
            const checkboxes = document.querySelectorAll('.update-checkbox:checked');
            const selected = Array.from(checkboxes).map(cb => cb.value);
            
            if (selected.length === 0) {
                showSnackbar("No services selected.", "Dismiss");
                return;
            }

            if (!await showDialog({
                title: 'Update Services?',
                message: "Update " + selected.length + " services? This will trigger backups, updates, and rebuilds (Expect high CPU usage).",
                confirmText: 'Update All',
                confirmClass: 'btn btn-filled'
            })) return;
            
            closeUpdateModal();
            showSnackbar(`Batch update initiated for ${selected.length} services. Rebuilding in background...`, "Dismiss");
            
            try {
                const res = await apiCall("/batch-update", {
                    method: 'POST',
                    body: JSON.stringify({ services: selected })
                });
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Batch update request accepted. Check logs for detailed progress.", "OK");
            } catch(e) {
                showSnackbar("Batch update failed: " + e.message, "Error");
            }
        }

        async function updateService(name, event) {
            const btn = event?.target.closest('button');
            const originalHtml = btn ? btn.innerHTML : '';
            if (btn) {
                btn.disabled = true;
                btn.innerHTML = `<span class="material-symbols-rounded" style="animation: spin 2s linear infinite;">sync</span> Updating...`;
            }
            showSnackbar(`Initiating update for ${name}...`, "Dismiss");

            try {
                const res = await apiCall("/update-service", {
                    method: 'POST',
                    body: JSON.stringify({ service: name })
                });
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                
                showSnackbar(`${name} update complete.`, "Success");
                return true;
            } catch(e) {
                showSnackbar(`Update failed: ${e.message}`, "Error");
                return false;
            } finally {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = originalHtml;
                }
            }
        }
        async function migrateService(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            const doBackup = document.getElementById('invidious-backup-toggle')?.checked ? 'yes' : 'no';
            
            if (!await showDialog({
                title: 'Migrate ' + name + '?',
                message: "Run foolproof migration for " + name + "?\n" + (doBackup === 'yes' ? "This will create a database backup first." : "WARNING: No backup will be created."),
                confirmText: 'Migrate',
                confirmClass: 'btn btn-filled'
            })) return;

            try {
                const res = await apiCall("/migrate?service=" + name + "&backup=" + doBackup);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                
                await showDialog({
                    type: 'alert',
                    title: 'Migration Successful',
                    message: "Migration successful!\n\n" + data.output
                });
            } catch(e) {
                await showDialog({
                    type: 'alert',
                    title: 'Migration Failed',
                    message: e.message
                });
            }
        }

        async function clearServiceDb(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            const doBackup = document.getElementById('invidious-backup-toggle')?.checked ? 'yes' : 'no';
            
            if (!await showDialog({
                title: 'Clear Database?',
                message: "DANGER: This will permanently DELETE all subscriptions and preferences for " + name + ".\n" + (doBackup === 'yes' ? "A backup will be created first." : "WARNING: NO BACKUP WILL BE CREATED.") + "\nContinue?",
                confirmText: 'Clear Data',
                confirmClass: 'btn btn-filled'
            })) return;

            try {
                const res = await apiCall("/clear-db?service=" + name + "&backup=" + doBackup);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                
                await showDialog({
                    type: 'alert',
                    title: 'Database Cleared',
                    message: "Database cleared successfully!\n\n" + data.output
                });
            } catch(e) {
                showSnackbar("Action failed: " + e.message);
            }
        }

        async function clearServiceLogs(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            
            if (!await showDialog({
                title: 'Clear Logs?',
                message: "Clear all historical query logs for " + name + "? This cannot be undone.",
                confirmText: 'Clear',
                confirmClass: 'btn btn-tonal'
            })) return;

            try {
                const res = await apiCall("/clear-logs?service=" + name);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Logs cleared successfully!");
            } catch(e) {
                showSnackbar("Failed to clear logs: " + e.message);
            }
        }

        async function vacuumServiceDb(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            showSnackbar("Optimizing database... please wait.");
            try {
                const res = await apiCall("/vacuum?service=" + name);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Database optimized successfully!");
            } catch(e) {
                showSnackbar("Optimization failed: " + e.message);
            }
        }
        
        async function rotateApiKey() {
            const newKey = await showDialog({
                type: 'prompt',
                title: 'Rotate API Key',
                message: 'Enter new HUB_API_KEY. Warning: You must update your local .secrets manually if this fails!',
                placeholder: 'New API Key'
            });
            if (!newKey) return;
            try {
                const res = await apiCall("/rotate-api-key", {
                    method: 'POST',
                    body: JSON.stringify({ new_key: newKey })
                });
                const data = await res.json();
                if (data.success) {
                    odidoApiKey = newKey;
                    sessionStorage.setItem('odido_api_key', newKey);
                    showSnackbar("API Key rotated successfully!");
                } else { throw new Error(data.error); }
            } catch(e) { showSnackbar("Rotation failed: " + e.message); }
        }

        async function filterLogs() {
            const level = document.getElementById('log-filter-level').value;
            const category = document.getElementById('log-filter-cat').value;
            // Modern API call construction
            const query = new URLSearchParams();
            if (level && level !== 'ALL') query.append('level', level);
            if (category && category !== 'ALL') query.append('category', category);
            
            try {
                const res = await apiCall("/logs?" + query.toString());
                const data = await res.json();
                const el = document.getElementById('log-container');
                el.innerHTML = '';
                (data.logs || []).forEach(log => {
                    el.appendChild(parseLogLine(JSON.stringify(log)));
                });
            } catch(e) { showSnackbar("Failed to filter logs"); }
        }
        
        async function fetchContainerIds() {
            try {
                const res = await apiCall("/containers");
                if (!res.ok) throw new Error("API " + res.status);
                const data = await res.json();
                containerIds = data.containers || {};
                
                // Update all portainer links
                document.querySelectorAll('.portainer-link').forEach(el => {
                    const containerName = el.dataset.container;
                    const containerInfo = containerIds[containerName];
                    const cid = containerInfo ? containerInfo.id : null;
                    const originalHtml = el.getAttribute('data-original-html') || el.innerHTML;
                    if (!el.getAttribute('data-original-html')) el.setAttribute('data-original-html', originalHtml);

                    if (cid) {
                        el.style.opacity = '1';
                        el.style.cursor = 'pointer';
                        el.dataset.tooltip = "Manage " + containerName + " in Portainer";
                        el.innerHTML = originalHtml;
                        
                        // Use a fresh onclick handler
                        el.onclick = (e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            window.open(PORTAINER_URL + "/#!/1/docker/containers/" + cid, '_blank');
                        };
                    } else {
                        el.style.opacity = '0.6';
                        el.style.cursor = 'default';
                        el.onclick = (e) => { e.preventDefault(); e.stopPropagation(); };
                    }
                });
            } catch(e) { console.error('Container fetch error:', e); }
        }
        
        function navigate(el, e) {
            if (e && (e.target.closest('.portainer-link') || e.target.closest('.btn') || e.target.closest('.chip'))) return;
            const url = el.getAttribute('data-url');
            if (url && (url.startsWith('http://') || url.startsWith('https://'))) {
                window.open(url, '_blank');
            }
        }

        function generateRandomId() {
            const chars = 'abcdef0123456789';
            let id = '';
            for (let i = 0; i < 8; i++) id += chars.charAt(Math.floor(Math.random() * chars.length));
            return 'profile-' + id;
        }
        
        function updateProfileDisplay() {
            const vpnActive = document.getElementById('vpn-active');
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (vpnActive && realProfileName) {
                if (isPrivate) {
                    if (!maskedProfileId) maskedProfileId = generateRandomId();
                    vpnActive.textContent = maskedProfileId;
                    vpnActive.classList.add('sensitive-masked');
                } else {
                    vpnActive.textContent = realProfileName;
                    vpnActive.classList.remove('sensitive-masked');
                }
            }
            updateProfileListDisplay();
        }

        function getProfileLabel(name) {
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (!isPrivate) return name;
            if (!profileMaskMap[name]) profileMaskMap[name] = generateRandomId();
            return profileMaskMap[name];
        }

        function updateProfileListDisplay() {
            const items = document.querySelectorAll('#profile-list .list-item-text');
            items.forEach((item) => {
                const realName = item.dataset.realName;
                if (realName) item.textContent = getProfileLabel(realName);
            });
        }
        
        async function saveDesecConfig() {
            const domain = document.getElementById('desec-domain-input').value.trim();
            const token = document.getElementById('desec-token-input').value.trim();
            if (!domain && !token) {
                showSnackbar("Domain or token required");
                return;
            }
            try {
                const res = await apiCall("/config-desec", {
                    method: 'POST',
                    body: JSON.stringify({ domain, token })
                });
                const result = await res.json();
                if (result.success) {
                    showSnackbar("deSEC configuration saved! Certificates updating in background.");
                    document.getElementById('desec-domain-input').value = '';
                    document.getElementById('desec-token-input').value = '';
                } else {
                    throw new Error(result.error || "Unknown error");
                }
            } catch (e) {
                showSnackbar("Failed to save deSEC config: " + e.message);
            }
        }
        
        let lastStatusTime = Date.now();
        let lastByteCounts = { vpn_rx: 0, vpn_tx: 0, wge_rx: 0, wge_tx: 0 };

        let isFetchingStatus = false;
        /**
         * The heartbeat of the dashboard. Polls the backend for real-time status.
         * Why: 
         * 1. Updates VPN connection state, throughput, and service health indicators.
         * 2. Uses AbortController to prevent request pile-up on slow networks.
         * 3. Calculates real-time speed deltas for network graphs.
         * 4. Handles 'Connecting...' vs 'Down' states for better UX during restarts.
         */
        async function fetchStatus() {
            if (isFetchingStatus) return;
            isFetchingStatus = true;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 15000);
            const now = Date.now();
            const deltaSec = (now - lastStatusTime) / 1000;
            lastStatusTime = now;

            try {
                const res = await apiCall("/status", { signal: controller.signal });
                clearTimeout(timeoutId);
                
                if (res.status === 401) {
                    throw new Error("401 Unauthorized");
                }
                
                if (!res.ok) return;

                const data = await res.json();
                const setText = (id, value) => {
                    const el = document.getElementById(id);
                    if (el) el.textContent = value;
                    return el;
                };
                const g = data.gluetun || {};
                const vpnStatus = document.getElementById('vpn-status');
                const hintVpnStatus = document.getElementById('hint-vpn-status');
                const hintVpnIp = document.getElementById('hint-vpn-ip');
                const hintVpnUsage = document.getElementById('hint-vpn-usage');
                const hintVpnSpeed = document.getElementById('hint-vpn-speed');

                // Speed calculation
                const vpn_rx = parseInt(g.session_rx || 0);
                const vpn_tx = parseInt(g.session_tx || 0);
                if (hintVpnSpeed && deltaSec > 0) {
                    const rx_speed = (vpn_rx - lastByteCounts.vpn_rx) / deltaSec;
                    const tx_speed = (vpn_tx - lastByteCounts.vpn_tx) / deltaSec;
                    // Filter out negative values if session reset
                    const s_rx = rx_speed > 0 ? rx_speed : 0;
                    const s_tx = tx_speed > 0 ? tx_speed : 0;
                    hintVpnSpeed.innerHTML = `<span class="material-symbols-rounded">speed</span> ↓${formatBytes(s_rx)}/s ↑${formatBytes(s_tx)}/s`;
                }
                lastByteCounts.vpn_rx = vpn_rx;
                lastByteCounts.vpn_tx = vpn_tx;

                if (hintVpnStatus) {
                    const statusText = (g.status === "up" && g.healthy) ? "Connected" : (g.status === "up" ? "Issues" : "Down");
                    hintVpnStatus.innerHTML = `<span class="material-symbols-rounded">vpn_lock</span> VPN: ${statusText}`;
                    hintVpnStatus.style.color = (g.status === "up" && g.healthy) ? 'var(--md-sys-color-success)' : (g.status === "up" ? 'var(--md-sys-color-warning)' : 'var(--md-sys-color-error)');
                }
                if (hintVpnIp) hintVpnIp.innerHTML = `<span class="material-symbols-rounded">public</span> IP: ${g.public_ip || "--"}`;
                if (hintVpnUsage) {
                    const sess = formatBytes(vpn_rx + vpn_tx);
                    const total = formatBytes(parseInt(g.total_rx || 0) + parseInt(g.total_tx || 0));
                    hintVpnUsage.innerHTML = `<span class="material-symbols-rounded">data_usage</span> Session: ${sess} / Total: ${total}`;
                }

                if (vpnStatus) {
                    if (g.status === "up" && g.healthy) {
                        vpnStatus.textContent = "Connected (Healthy)";
                        vpnStatus.className = "stat-value text-success";
                        vpnStatus.title = "VPN tunnel is active and passing health checks";
                    } else if (g.status === "up") {
                        vpnStatus.textContent = "Connected";
                        vpnStatus.className = "stat-value text-success";
                        vpnStatus.title = "VPN tunnel is active";
                    } else {
                        vpnStatus.textContent = "Disconnected";
                        vpnStatus.className = "stat-value error";
                        vpnStatus.title = "VPN tunnel is not established";
                    }
                }
                realProfileName = g.active_profile || "Unknown";
                updateProfileDisplay();
                setText('vpn-endpoint', g.endpoint || "--");
                setText('vpn-public-ip', g.public_ip || "--");
                setText('vpn-connection', g.handshake_ago || "Never");
                setText('vpn-session-rx', formatBytes(g.session_rx || 0));
                setText('vpn-session-tx', formatBytes(g.session_tx || 0));
                setText('vpn-total-rx', formatBytes(g.total_rx || 0));
                setText('vpn-total-tx', formatBytes(g.total_tx || 0));
                const w = data.wgeasy || {};
                const wgeStat = document.getElementById('wge-status');
                const hintWgeClients = document.getElementById('hint-wge-clients');
                const hintWgeUsage = document.getElementById('hint-wge-usage');

                const wge_rx = parseInt(w.session_rx || 0);
                const wge_tx = parseInt(w.session_tx || 0);
                lastByteCounts.wge_rx = wge_rx;
                lastByteCounts.wge_tx = wge_tx;

                if (hintWgeClients) {
                    const connected = parseInt(w.connected) || 0;
                    const total = parseInt(w.clients) || 0;
                    hintWgeClients.innerHTML = `<span class="material-symbols-rounded">group</span> ${connected}/${total} Clients`;
                    hintWgeClients.style.color = connected > 0 ? 'var(--md-sys-color-success)' : 'inherit';
                }
                if (hintWgeUsage) {
                    const sess = formatBytes(wge_rx + wge_tx);
                    const total = formatBytes(parseInt(w.total_rx || 0) + parseInt(w.total_tx || 0));
                    hintWgeUsage.innerHTML = `<span class="material-symbols-rounded">move_up</span> Session: ${sess} / Total: ${total}`;
                }

                if (wgeStat) {
                    if (w.status === "up") {
                        wgeStat.textContent = "Running";
                        wgeStat.className = "stat-value text-success";
                        wgeStat.title = "WireGuard management service is operational";
                    } else {
                        wgeStat.textContent = "Stopped";
                        wgeStat.className = "stat-value error";
                        wgeStat.title = "WireGuard management service is not running";
                    }
                }
                setText('wge-host', w.host || "--");
                setText('wge-clients', w.clients || "0");
                const wgeConnected = document.getElementById('wge-connected');
                const connectedCount = parseInt(w.connected) || 0;
                if (wgeConnected) {
                    wgeConnected.textContent = connectedCount > 0 ? connectedCount + " active" : "None";
                    wgeConnected.className = connectedCount > 0 ? "stat-value text-success" : "stat-value";
                }
                setText('wge-session-rx', formatBytes(w.session_rx || 0));
                setText('wge-session-tx', formatBytes(w.session_tx || 0));
                setText('wge-total-rx', formatBytes(w.total_rx || 0));
                setText('wge-total-tx', formatBytes(w.total_tx || 0));

                // Update service statuses from server-side checks
                if (data.services) {
                    for (const [name, status] of Object.entries(data.services)) {
                        const cards = document.querySelectorAll(`[data-container="${name}"]`);
                        cards.forEach(card => {
                            const dot = card.querySelector('.status-dot');
                            const txt = card.querySelector('.status-text');
                            const indicator = card.querySelector('.status-indicator');
                            
                            if (dot && txt && indicator) {
                                if (status === 'unhealthy' && data.health_details && data.health_details[name]) {
                                    txt.textContent = 'Issue Detected';
                                    dot.className = 'status-dot down';
                                    indicator.title = data.health_details[name];
                                } else if (status === 'healthy' || status === 'up') {
                                    txt.textContent = 'Connected';
                                    dot.className = 'status-dot up';
                                    indicator.title = 'Service is connected and operational';
                                } else if (status === 'starting') {
                                    txt.textContent = 'Connecting...';
                                    dot.className = 'status-dot starting';
                                    indicator.title = 'Service is currently initializing';
                                } else {
                                    txt.textContent = 'Offline';
                                    dot.className = 'status-dot down';
                                    indicator.title = 'Service is unreachable';
                                }
                            }
                        });
                    }
                }
                
                const dot = document.getElementById('api-dot');
                const txt = document.getElementById('api-text');
                if (dot && txt) {
                    dot.className = 'status-dot up';
                    txt.textContent = 'Connected';
                }
            } catch(e) {
                if (e.name !== 'AbortError') {
                    console.error("Status fetch error:", e);
                    const dot = document.getElementById('api-dot');
                    const txt = document.getElementById('api-text');
                    if (dot && txt) {
                        dot.className = 'status-dot down';
                        txt.textContent = 'Offline';
                    }
                    // Force indicators out of "Connecting..." state on API failure
                    document.querySelectorAll('.status-indicator').forEach(indicator => {
                        const dot = indicator.querySelector('.status-dot');
                        const text = indicator.querySelector('.status-text');
                        if (dot && text && !dot.id.includes('api')) {
                            dot.className = 'status-dot down';
                            text.textContent = 'API Offline';
                            indicator.title = 'The Management Hub is unreachable. Real-time metrics, VPN switching, and service update controls are unavailable until connection is restored.';
                        }
                    });
                }
            } finally {
                isFetchingStatus = false;
            }
        }
        
        async function fetchOdidoStatus() {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 10000);
            try {
                const res = await apiCall("/status", { 
                    baseUrl: ODIDO_API,
                    signal: controller.signal 
                });
                clearTimeout(timeoutId);
                if (!res.ok) {
                    const data = await res.json().catch(() => ({}));
                    document.getElementById('odido-loading').style.display = 'none';
                    document.getElementById('odido-not-configured').style.display = 'none';
                    document.getElementById('odido-configured').style.display = 'block';
                    document.getElementById('odido-remaining').textContent = '--';
                    document.getElementById('odido-bundle-code').textContent = '--';
                    document.getElementById('odido-threshold').textContent = '--';
                    const apiStatus = document.getElementById('odido-api-status');
                    
                    if (res.status === 401) {
                        apiStatus.textContent = 'Dashboard API Key Invalid';
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    } else if (res.status === 400 || (data.detail && data.detail.includes('credentials'))) {
                        apiStatus.textContent = 'Odido Account Not Linked';
                        apiStatus.style.color = 'var(--md-sys-color-warning)';
                    } else {
                        apiStatus.textContent = "Service Error: " + res.status;
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    }
                    return;
                }
                const data = await res.json();
                document.getElementById('odido-loading').style.display = 'none';
                document.getElementById('odido-not-configured').style.display = 'none';
                document.getElementById('odido-configured').style.display = 'block';
                const state = data.state || {};
                const config = data.config || {};
                const remaining = state.remaining_mb || 0;
                const threshold = config.absolute_min_threshold_mb || 100;
                const rate = data.consumption_rate_mb_per_min || 0;
                const bundleCode = config.bundle_code || 'A0DAY01';
                const hasOdidoCreds = config.odido_user_id && config.odido_token;
                // Also consider as "connected" if we have real data from the API
                const hasRealData = remaining > 0 || state.last_updated_ts;
                const isConfigured = hasOdidoCreds || hasRealData;
                document.getElementById('odido-remaining').textContent = Math.round(remaining) + " MB";
                document.getElementById('odido-bundle-code').textContent = bundleCode;
                document.getElementById('odido-threshold').textContent = threshold + " MB";
                document.getElementById('odido-auto-renew').textContent = config.auto_renew_enabled ? 'Enabled' : 'Disabled';
                document.getElementById('odido-rate').textContent = rate.toFixed(3) + " MB/min";
                const apiStatus = document.getElementById('odido-api-status');
                apiStatus.textContent = isConfigured ? 'Connected' : 'Not configured';
                apiStatus.style.color = isConfigured ? 'var(--md-sys-color-success)' : 'var(--md-sys-color-warning)';
                
                updateOdidoGraph(rate, remaining);

                const maxData = config.bundle_size_mb || 1024;
                const percent = Math.min(100, (remaining / maxData) * 100);
                const bar = document.getElementById('odido-bar');
                if (bar) {
                    bar.style.width = percent + "%";
                    bar.className = 'progress-indicator';
                    if (remaining < threshold) bar.classList.add('critical');
                    else if (remaining < threshold * 2) bar.classList.add('low');
                }
            } catch(e) {
                // Network error or service unavailable - show not-configured with error info
                const loading = document.getElementById('odido-loading');
                if (loading) loading.style.display = 'none';
                const notConf = document.getElementById('odido-not-configured');
                if (notConf) notConf.style.display = 'flex';
                const conf = document.getElementById('odido-configured');
                if (conf) conf.style.display = 'none';
                console.error('Odido status error:', e);
            }
        }
        
        async function saveOdidoConfig() {
            const st = document.getElementById('odido-config-status');
            const data = {};
            const oauthToken = document.getElementById('odido-oauth-token').value.trim();
            const bundleCode = document.getElementById('odido-bundle-code-input').value.trim();
            const threshold = document.getElementById('odido-threshold-input').value.trim();
            const leadTime = document.getElementById('odido-lead-time-input').value.trim();
            
            // If OAuth token provided, fetch User ID automatically via hub-api API (uses curl)
            if (oauthToken) {
                if (st) {
                    st.textContent = 'Fetching User ID from Odido API...';
                    st.style.color = 'var(--p)';
                }
                try {
                    const res = await apiCall("/odido-userid", {
                        method: 'POST',
                        body: JSON.stringify({ oauth_token: oauthToken })
                    });
                    const result = await res.json();
                    if (result.error) throw new Error(result.error);
                    if (result.user_id) {
                        data.odido_user_id = result.user_id;
                        data.odido_token = oauthToken;
                        if (st) {
                            st.textContent = "User ID fetched: " + result.user_id;
                            st.style.color = 'var(--ok)';
                        }
                    } else {
                        throw new Error('Could not extract User ID from Odido API response');
                    }
                } catch(e) {
                    if (st) {
                        st.textContent = "Failed to fetch User ID: " + e.message;
                        st.style.color = 'var(--err)';
                    }
                    return;
                }
            }
            
            if (bundleCode) data.bundle_code = bundleCode;
            if (threshold) data.absolute_min_threshold_mb = parseInt(threshold);
            if (leadTime) data.lead_time_minutes = parseInt(leadTime);
            
            if (Object.keys(data).length === 0) {
                if (st) {
                    st.textContent = 'Fill at least one field';
                    st.style.color = 'var(--err)';
                }
                return;
            }
            if (st) {
                st.textContent = 'Saving configuration...';
                st.style.color = 'var(--p)';
            }
            try {
                const res = await apiCall("/config", {
                    baseUrl: ODIDO_API,
                    method: 'POST',
                    body: JSON.stringify(data)
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = 'Configuration saved!';
                    st.style.color = 'var(--ok)';
                }
                document.getElementById('odido-api-key').value = '';
                document.getElementById('odido-oauth-token').value = '';
                document.getElementById('odido-bundle-code-input').value = '';
                document.getElementById('odido-threshold-input').value = '';
                document.getElementById('odido-lead-time-input').value = '';
                fetchOdidoStatus();
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
        }
        
        async function buyOdidoBundle() {
            const st = document.getElementById('odido-buy-status');
            const btn = document.getElementById('odido-buy-btn');
            btn.disabled = true;
            if (st) {
                st.textContent = 'Purchasing bundle from Odido...';
                st.style.color = 'var(--p)';
            }
            try {
                const res = await apiCall("/odido/buy-bundle", {
                    baseUrl: ODIDO_API,
                    method: 'POST',
                    body: JSON.stringify({})
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = 'Bundle purchased successfully!';
                    st.style.color = 'var(--ok)';
                }
                setTimeout(fetchOdidoStatus, 2000);
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
            btn.disabled = false;
        }
        
        async function refreshOdidoRemaining() {
            const st = document.getElementById('odido-buy-status');
            if (st) {
                st.textContent = 'Fetching from Odido API...';
                st.style.color = 'var(--p)';
            }
            try {
                const res = await apiCall("/odido/remaining", { baseUrl: ODIDO_API });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = "Live data: " + Math.round(result.remaining_mb || 0) + " MB remaining";
                    st.style.color = 'var(--ok)';
                }
                setTimeout(fetchOdidoStatus, 1000);
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
        }
        
        async function fetchProfiles() {
            if (!isAdmin) return;
            try {
                const res = await apiCall("/profiles");
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                const el = document.getElementById('profile-list');
                el.innerHTML = '';
                el.style.flexDirection = 'column';
                el.style.alignItems = 'stretch';
                el.style.justifyContent = 'flex-start';
                el.style.gap = '4px';
                
                if (data.profiles.length === 0) {
                    el.innerHTML = '<div style="text-align:center; padding: 24px; opacity: 0.6;"><span class="material-symbols-rounded" style="font-size: 48px;">folder_open</span><p class="body-medium">No profiles found</p></div>';
                    return;
                }

                data.profiles.forEach(p => {
                    const row = document.createElement('div');
                    row.className = 'list-item';
                    row.style.margin = '0';
                    row.style.borderRadius = 'var(--md-sys-shape-corner-medium)';
                    row.style.background = 'var(--md-sys-color-surface-container-low)';
                    row.style.border = '1px solid var(--md-sys-color-outline-variant)';

                    const content = document.createElement('div');
                    content.style.display = 'flex';
                    content.style.alignItems = 'center';
                    content.style.gap = '12px';
                    content.style.flex = '1';
                    content.style.cursor = 'pointer';
                    content.onclick = function() { activateProfile(p); };

                    const icon = document.createElement('span');
                    icon.className = 'material-symbols-rounded';
                    icon.textContent = 'vpn_key';
                    icon.style.color = 'var(--md-sys-color-primary)';

                    const name = document.createElement('span');
                    name.className = 'list-item-text title-small';
                    name.style.flex = '1';
                    name.dataset.realName = p;
                    name.textContent = getProfileLabel(p);

                    content.appendChild(icon);
                    content.appendChild(name);

                    const delBtn = document.createElement('button');
                    delBtn.className = 'btn btn-icon';
                    delBtn.style.color = 'var(--md-sys-color-on-surface-variant)';
                    delBtn.title = 'Delete';
                    delBtn.innerHTML = '<span class="material-symbols-rounded">delete</span>';
                    delBtn.onclick = function(e) { e.stopPropagation(); deleteProfile(p); };

                    row.appendChild(content);
                    row.appendChild(delBtn);
                    el.appendChild(row);
                });
                updateProfileListDisplay();
            } catch(e) {
                console.error("Profile fetch error:", e);
            }
        }
        async function uploadProfile() {
            const nameInput = document.getElementById('prof-name').value;
            const config = document.getElementById('prof-conf').value;
            const st = document.getElementById('upload-status');
            if(!config) { 
                if(st) st.textContent="Error: Config content missing"; 
                else await showDialog({type:'alert', title:'Error', message: "Error: Config content missing"}); 
                return; 
            }
            if(st) st.textContent = "Uploading...";
            try {
                const upRes = await apiCall("/upload", { 
                    method:'POST', 
                    body:JSON.stringify({name: nameInput, config: config}) 
                });
                const upData = await upRes.json();
                if(upData.error) throw new Error(upData.error);
                const activeName = upData.name;
                if(st) st.textContent = "Activating " + activeName + "...";
                await apiCall("/activate", { 
                    method:'POST', 
                    body:JSON.stringify({name: activeName}) 
                });
                if(st) st.textContent = "Success! VPN restarting."; 
                else await showDialog({type:'alert', title:'Success', message: "Success! VPN restarting."});
                fetchProfiles(); document.getElementById('prof-name').value=""; document.getElementById('prof-conf').value="";
            } catch(e) { 
                if(st) st.textContent = e.message; 
                else await showDialog({type:'alert', title:'Error', message: e.message}); 
            }
        }
        
        async function activateProfile(name) {
            if(!await showDialog({
                title: 'Switch Profile?',
                message: "Switch to " + name + "?",
                confirmText: 'Switch'
            })) return;
            try { 
                await apiCall("/activate", { 
                    method:'POST', 
                    body:JSON.stringify({name: name}) 
                }); 
                await showDialog({
                    type: 'alert',
                    title: 'Profile Switched',
                    message: "Profile switched. VPN restarting."
                });
            } catch(e) { 
                await showDialog({type:'alert', title:'Error', message: "Error switching profile"}); 
            }
        }
        
        async function deleteProfile(name) {
            if(!await showDialog({
                title: 'Delete Profile?',
                message: "Delete " + name + "?",
                confirmText: 'Delete'
            })) return;
            try { 
                await apiCall("/delete", { 
                    method:'POST', 
                    body:JSON.stringify({name: name}) 
                }); 
                fetchProfiles(); 
            } catch(e) { 
                await showDialog({type:'alert', title:'Error', message: "Error deleting profile"}); 
            }
        }
        
        function startLogStream() {
            if (!isAdmin) return;
            const el = document.getElementById('log-container');
            const status = document.getElementById('log-status');
            const evtSource = new EventSource(API + "/events");
            
            evtSource.onmessage = function(e) {
                if (!e.data) return;
                const entry = parseLogLine(e.data);
                if (!entry) return;

                // Clear the loader if it's still there
                if (el.querySelector('.body-medium')) {
                    el.innerHTML = '';
                    el.style.alignItems = 'flex-start';
                    el.style.justifyContent = 'flex-start';
                }

                el.appendChild(entry);
                if (el.childNodes.length > 500) el.removeChild(el.firstChild);
                el.scrollTop = el.scrollHeight;
            };
            evtSource.onopen = function() { status.textContent = "Live"; status.style.color = "var(--md-sys-color-success)"; };
            evtSource.onerror = function() { status.textContent = "Reconnecting..."; status.style.color = "var(--md-sys-color-error)"; evtSource.close(); if (isAdmin) setTimeout(startLogStream, 3000); };
        }

        function parseLogLine(line) {
            let logData = null;
            try {
                logData = JSON.parse(line);
            } catch(e) {
                logData = { message: line, level: 'INFO', category: 'SYSTEM', timestamp: '' };
            }

            // Apply active filters
            const filterLevel = document.getElementById('log-filter-level').value;
            const filterCat = document.getElementById('log-filter-cat').value;
            if (filterLevel !== 'ALL' && logData.level !== filterLevel) return null;
            if (filterCat !== 'ALL' && logData.category !== filterCat) return null;

            // Filter out common noise
            const m = logData.message || "";
            if (m.includes('HTTP/1.1" 200') || m.includes('HTTP/1.1" 304')) {
                // Only filter if it doesn't match a known humanization pattern
                const knownPatterns = ['GET /status', 'GET /metrics', 'GET /containers', 'GET /updates', 'GET /logs', 'GET /certificate-status', 'GET /theme', 'POST /theme', 'GET /system-health', 'GET /profiles', 'POST /update-service', 'POST /batch-update', 'POST /restart-stack', 'POST /rotate-api-key', 'POST /activate', 'POST /upload', 'POST /delete', 'GET /check-updates', 'GET /changelog', 'GET /project-details', 'POST /purge-images'];
                if (!knownPatterns.some(p => m.includes(p))) return null;
            }

            const div = document.createElement('div');
            div.className = 'log-entry';

            let icon = 'info';
            let iconColor = 'var(--md-sys-color-primary)';
            let message = logData.message;
            let timestamp = logData.timestamp;

            // Humanization logic
            if (message.includes('GET /project-details')) message = 'Storage utilization breakdown fetched';
            if (message.includes('POST /purge-images')) message = 'Unused Docker assets purged';
            if (message.includes('GET /system-health')) message = 'System health telemetry synchronized';
            if (message.includes('POST /update-service')) message = 'Service update initiated';
            if (message.includes('POST /theme')) message = 'UI theme preferences updated';
            if (message.includes('GET /theme')) message = 'UI theme assets synchronized';
            if (message.includes('POST /verify-admin')) message = 'Administrative session authorized';
            if (message.includes('POST /toggle-session-cleanup')) message = 'Session security policy updated';
            if (message.includes('GET /profiles')) message = 'VPN profiles synchronized';
            if (message.includes('POST /activate')) message = 'VPN profile switch triggered';
            if (message.includes('POST /upload')) message = 'VPN profile upload completed';
            if (message.includes('POST /delete')) message = 'VPN profile deletion requested';
            if (message.includes('Watchtower Notification')) message = 'Container update availability checked';
            if (message.includes('GET /status')) message = 'Service health status refreshed';
            if (message.includes('GET /metrics')) message = 'Performance metrics updated';
                if (message.includes('POST /batch-update')) message = 'Batch update sequence started';
                if (message.includes('GET /updates')) message = 'Checking repository update status';
                if (message.includes('GET /services')) message = 'Service catalog synchronized';
                if (message.includes('GET /check-updates')) message = 'Update availability check requested';
                if (message.includes('GET /changelog')) message = 'Service changelog retrieved';
                if (message.includes('POST /config-desec')) message = 'deSEC dynamic DNS updated';
                if (message.includes('GET /certificate-status')) message = 'SSL certificate validity checked';
                if (message.includes('GET /containers')) message = 'Container orchestration state audited';
                if (message.includes('GET /logs')) message = 'System logs retrieved';
                if (message.includes('GET /events')) message = 'Live log stream connection established';
                if (message.includes('POST /restart-stack')) message = 'Full system stack restart triggered';
                if (message.includes('POST /rotate-api-key')) message = 'Dashboard API security key rotated';

                // Category based icons
                if (logData.category === 'NETWORK') icon = 'lan';
                if (logData.category === 'AUTH' || logData.category === 'SECURITY') icon = 'lock';
                if (logData.category === 'MAINTENANCE') icon = 'build';
                if (logData.category === 'ORCHESTRATION') icon = 'hub';

                // Level based colors
                if (logData.level === 'WARN') {
                    icon = 'warning';
                    iconColor = 'var(--md-sys-color-warning)';
                } else if (logData.level === 'ERROR') {
                    icon = 'error';
                    iconColor = 'var(--md-sys-color-error)';
                } else if (logData.level === 'ACCESS') {
                    icon = 'api';
                    // Simplify common access logs
                    if (message.includes('GET /status')) message = 'Health check processed';
                    if (message.includes('GET /events')) message = 'Log stream connection';
                }

                // Production Readiness: Use DOM methods to prevent XSS in logs
                const iconSpan = document.createElement('span');
                iconSpan.className = 'material-symbols-rounded log-icon';
                iconSpan.style.color = iconColor;
                iconSpan.textContent = icon;

                const contentDiv = document.createElement('div');
                contentDiv.className = 'log-content';
                contentDiv.textContent = message;

                const timeSpan = document.createElement('span');
                timeSpan.className = 'log-time';
                timeSpan.textContent = timestamp;

                div.appendChild(iconSpan);
                div.appendChild(contentDiv);
                div.appendChild(timeSpan);

                return div;
            }
                    
                            // Dialog Modal Implementation
        let dialogResolve = null;

        function closeDialog() {
            const modal = document.getElementById('dialog-modal');
            if (modal) modal.style.display = 'none';
            if (dialogResolve) dialogResolve(false);
            dialogResolve = null;
        }

        function showDialog(options) {
            return new Promise((resolve) => {
                const modal = document.getElementById('dialog-modal');
                const title = document.getElementById('dialog-title');
                const msg = document.getElementById('dialog-message');
                const inputContainer = document.getElementById('dialog-input-container');
                const input = document.getElementById('dialog-input');
                const confirmBtn = document.getElementById('dialog-confirm-btn');
                const cancelBtn = document.getElementById('dialog-cancel-btn');

                if (!modal) {
                    // Fallback
                    if (options.type === 'prompt') {
                        const val = prompt(options.message, options.value);
                        resolve(val);
                    } else if (options.type === 'alert') {
                        alert(options.message);
                        resolve(true);
                    } else {
                        resolve(confirm(options.message));
                    }
                    return;
                }

                title.textContent = options.title || 'Confirm';
                msg.textContent = options.message || '';
                
                if (options.type === 'prompt') {
                    inputContainer.style.display = 'block';
                    input.value = options.value || '';
                    input.placeholder = options.placeholder || '';
                    setTimeout(() => input.focus(), 100);
                } else {
                    inputContainer.style.display = 'none';
                }

                confirmBtn.textContent = options.confirmText || 'Confirm';
                confirmBtn.className = 'btn ' + (options.confirmClass || 'btn-filled');
                
                if (options.type === 'alert') {
                    cancelBtn.style.display = 'inline-flex';
                } else {
                    cancelBtn.style.display = 'inline-flex';
                    cancelBtn.textContent = options.cancelText || 'Cancel';
                }

                dialogResolve = resolve;

                confirmBtn.onclick = () => {
                    modal.style.display = 'none';
                    if (options.type === 'prompt') {
                        resolve(input.value);
                    } else {
                        resolve(true);
                    }
                    dialogResolve = null;
                };

                cancelBtn.onclick = () => {
                    modal.style.display = 'none';
                    resolve(false);
                    dialogResolve = null;
                };

                if (options.type === 'prompt') {
                    input.onkeydown = (e) => {
                        if (e.key === 'Enter') confirmBtn.click();
                        if (e.key === 'Escape') cancelBtn.click();
                    };
                }

                modal.style.display = 'flex';
            });
        }

        async function copyToClipboard(text, el) {
            const originalText = el.textContent;
            const originalBg = el.style.background;

            const performCopy = async () => {
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    await navigator.clipboard.writeText(text);
                    return true;
                }
                // Fallback
                const textArea = document.createElement("textarea");
                textArea.value = text;
                textArea.style.position = "fixed";
                textArea.style.left = "-9999px";
                textArea.style.top = "0";
                document.body.appendChild(textArea);
                textArea.focus();
                textArea.select();
                try {
                    document.execCommand('copy');
                    textArea.remove();
                    return true;
                } catch (err) {
                    textArea.remove();
                    return false;
                }
            };

            if (await performCopy()) {
                el.textContent = 'Copied!';
                el.style.background = 'var(--md-sys-color-primary-container)';
                el.style.color = 'var(--md-sys-color-on-primary-container)';
                
                setTimeout(() => {
                    el.textContent = originalText;
                    el.style.background = originalBg;
                    el.style.color = '';
                }, 1500);
            } else {
                showSnackbar("Failed to copy to clipboard");
            }
        }

        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return parseFloat((a/Math.pow(1024,d)).toFixed(c)) + " " + ["B","KiB","MiB","GiB","TiB"][d]}
        
        // Snackbar implementation
        const snackbarContainer = document.createElement('div');
        snackbarContainer.className = 'snackbar-container';
        document.body.appendChild(snackbarContainer);

        function showSnackbar(message, actionText = '', actionCallback = null) {
            const snackbar = document.createElement('div');
            snackbar.className = 'snackbar';
            
            let html = `<div class="snackbar-content">${message}</div>`;
            if (actionText) {
                html += `<button class="snackbar-action">${actionText}</button>`;
            }
            snackbar.innerHTML = html;
            
            if (actionCallback) {
                snackbar.querySelector('.snackbar-action').onclick = () => {
                    actionCallback();
                    snackbar.classList.remove('visible');
                    setTimeout(() => snackbar.remove(), 500);
                };
            }

            snackbarContainer.appendChild(snackbar);
            // Trigger reflow
            snackbar.offsetHeight;
            snackbar.classList.add('visible');

            setTimeout(() => {
                snackbar.classList.remove('visible');
                setTimeout(() => snackbar.remove(), 500);
            }, 1500);
        }

        // Theme customization logic
        async function applySeedColor(hex) {
            const hexEl = document.getElementById('theme-seed-hex');
            if (hexEl) hexEl.textContent = hex.toUpperCase();
            const colors = generateM3Palette(hex);
            applyThemeColors(colors);
            await syncSettings();
        }

        function renderThemePreset(seedHex) {
            const colors = generateM3Palette(seedHex);
            const container = document.createElement('div');
            container.style.width = '48px';
            container.style.height = '48px';
            container.style.borderRadius = '24px';
            container.style.backgroundColor = colors.surfaceContainer; // Background of the "folder"
            container.style.cursor = 'pointer';
            container.style.border = '1px solid var(--md-sys-color-outline-variant)';
            container.style.transition = 'transform 0.2s, border-color 0.2s';
            container.title = "Apply " + seedHex;
            container.style.display = 'grid';
            container.style.gridTemplateColumns = '1fr 1fr';
            container.style.gridTemplateRows = '1fr 1fr';
            container.style.overflow = 'hidden';
            container.style.padding = '4px';
            container.style.gap = '2px';

            const c1 = document.createElement('div'); c1.style.background = colors.primary; c1.style.borderRadius = '50%';
            const c2 = document.createElement('div'); c2.style.background = colors.secondary; c2.style.borderRadius = '50%';
            const c3 = document.createElement('div'); c3.style.background = colors.tertiary; c3.style.borderRadius = '50%';
            const c4 = document.createElement('div'); c4.style.background = colors.primaryContainer; c4.style.borderRadius = '50%';

            container.appendChild(c1); container.appendChild(c2); container.appendChild(c3); container.appendChild(c4);

            container.onmouseover = () => { container.style.transform = 'scale(1.1)'; container.style.borderColor = 'var(--md-sys-color-primary)'; };
            container.onmouseout = () => { container.style.transform = 'scale(1)'; container.style.borderColor = 'var(--md-sys-color-outline-variant)'; };
            container.onclick = () => { applySeedColor(seedHex); };
            
            return container;
        }

        function initStaticPresets() {
            const presets = ['#D0BCFF', '#93000A', '#FFA500', '#006e1c', '#0061a4', '#555555'];
            const container = document.getElementById('static-presets');
            if(container) {
                container.innerHTML = '';
                presets.forEach(hex => container.appendChild(renderThemePreset(hex)));
            }
        }

        async function extractColorsFromImage(event) {
            const file = event.target.files[0];
            if (!file) return;
            
            const reader = new FileReader();
            reader.onload = async function(e) {
                const img = new Image();
                img.src = e.target.result;
                await new Promise(r => img.onload = r);

                // Downscale for performance (max 128x128 is usually enough for color extraction)
                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d');
                const scale = Math.min(1, 128 / Math.max(img.width, img.height));
                canvas.width = img.width * scale;
                canvas.height = img.height * scale;
                ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                
                const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
                const pixels = imageData.data;
                const argbPixels = [];
                
                for (let i = 0; i < pixels.length; i += 4) {
                    const r = pixels[i];
                    const g = pixels[i + 1];
                    const b = pixels[i + 2];
                    const a = pixels[i + 3];
                    if (a < 255) continue; // Skip transparent
                    // ARGB int format
                    const argb = (a << 24) | (r << 16) | (g << 8) | b;
                    argbPixels.push(argb);
                }

                if (typeof MaterialColorUtilities !== 'undefined' && MaterialColorUtilities.QuantizerCelebi) {
                    // Use official extraction
                    const result = MaterialColorUtilities.QuantizerCelebi.quantize(argbPixels, 128);
                    const ranked = MaterialColorUtilities.Score.score(result);
                    
                    // Clear previous
                    const container = document.getElementById('extracted-palette');
                    container.innerHTML = '';
                    
                    // Take top 4 or all if fewer
                    const topColors = ranked.slice(0, 4);
                    if (topColors.length === 0) {
                        // Fallback to naive average if algo fails
                        fallbackExtraction(pixels);
                        return;
                    }

                    topColors.forEach(argb => {
                        const hex = hexFromArgb(argb);
                        container.appendChild(renderThemePreset(hex));
                    });
                    
                    // Auto-select first
                    applySeedColor(hexFromArgb(topColors[0]));
                } else {
                    // Library missing? Fallback
                    fallbackExtraction(pixels);
                }
            };
            reader.readAsDataURL(file);
        }

        function fallbackExtraction(data) {
            let r = 0, g = 0, b = 0;
            const step = Math.max(1, Math.floor(data.length / 4000));
            let count = 0;
            for (let i = 0; i < data.length; i += step * 4) { 
                r += data[i]; g += data[i+1]; b += data[i+2];
                count++;
            }
            const avgHex = rgbToHex(Math.round(r/count), Math.round(g/count), Math.round(b/count));
            const container = document.getElementById('extracted-palette');
            container.innerHTML = '';
            container.appendChild(renderThemePreset(avgHex));
            applySeedColor(avgHex);
        }

        function addManualColor() {
            const input = document.getElementById('manual-color-input');
            let val = input.value.trim();
            if (!val.startsWith('#')) val = '#' + val;
            if (/^#[0-9A-F]{6}$/i.test(val)) {
                // Clear placeholder text if it exists
                const container = document.getElementById('extracted-palette');
                if (container.querySelector('span')) container.innerHTML = '';
                
                container.appendChild(renderThemePreset(val));
                applySeedColor(val);
                input.value = '';
            } else {
                showDialog({type:'alert', title:'Invalid Color', message: "Invalid Hex Code. Format: #RRGGBB"});
            }
        }



        function rgbToHex(r, g, b) {
            return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
        }

        function hexFromArgb(argb) {
            const r = (argb >> 16) & 255;
            const g = (argb >> 8) & 255;
            const b = argb & 255;
            return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
        }

        function getLuminance(hex) {
            const rgb = hexToRgb(hex);
            const rs = rgb.r / 255;
            const gs = rgb.g / 255;
            const bs = rgb.b / 255;
            const r = rs <= 0.03928 ? rs / 12.92 : Math.pow((rs + 0.055) / 1.055, 2.4);
            const g = gs <= 0.03928 ? gs / 12.92 : Math.pow((gs + 0.055) / 1.055, 2.4);
            const b = bs <= 0.03928 ? bs / 12.92 : Math.pow((bs + 0.055) / 1.055, 2.4);
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        function generateM3Palette(seedHex) {
            if (typeof MaterialColorUtilities === 'undefined') {
                // Fallback if library fails to load
                const rgb = hexToRgb(seedHex);
                const hsl = rgbToHsl(rgb.r, rgb.g, rgb.b);
                const isDark = !document.documentElement.classList.contains('light-mode');
                
                if (isDark) {
                    return {
                        primary: seedHex,
                        onPrimary: '#381E72',
                        primaryContainer: hslToHex(hsl.h, hsl.s, 0.3),
                        onPrimaryContainer: hslToHex(hsl.h, hsl.s, 0.9),
                        secondary: hslToHex((hsl.h + 0.1) % 1, hsl.s * 0.5, 0.7),
                        onSecondary: '#332D41',
                        surface: '#141218',
                        onSurface: '#E6E1E5',
                        surfaceVariant: '#49454F',
                        onSurfaceVariant: '#CAC4D0',
                        outline: '#938F99',
                        surfaceContainerLow: '#1D1B20',
                        surfaceContainer: '#211F26',
                        surfaceContainerHigh: '#2B2930'
                    };
                } else {
                    return {
                        primary: seedHex,
                        onPrimary: '#FFFFFF',
                        primaryContainer: hslToHex(hsl.h, hsl.s, 0.9),
                        onPrimaryContainer: hslToHex(hsl.h, hsl.s, 0.1),
                        secondary: hslToHex((hsl.h + 0.1) % 1, hsl.s * 0.5, 0.4),
                        onSecondary: '#FFFFFF',
                        surface: '#FEF7FF',
                        onSurface: '#1D1B20',
                        surfaceVariant: '#E7E0EC',
                        onSurfaceVariant: '#49454F',
                        outline: '#79747E',
                        surfaceContainerLow: '#F7F2FA',
                        surfaceContainer: '#F3EDF7',
                        surfaceContainerHigh: '#ECE6F0'
                    };
                }
            }

            const argb = MaterialColorUtilities.argbFromHex(seedHex);
            const isDark = !document.documentElement.classList.contains('light-mode');
            const theme = MaterialColorUtilities.themeFromSourceColor(argb);
            const scheme = isDark ? theme.schemes.dark : theme.schemes.light;

            const tokens = {
                primary: hexFromArgb(scheme.primary),
                onPrimary: hexFromArgb(scheme.onPrimary),
                primaryContainer: hexFromArgb(scheme.primaryContainer),
                onPrimaryContainer: hexFromArgb(scheme.onPrimaryContainer),
                secondary: hexFromArgb(scheme.secondary),
                onSecondary: hexFromArgb(scheme.onSecondary),
                secondaryContainer: hexFromArgb(scheme.secondaryContainer),
                onSecondaryContainer: hexFromArgb(scheme.onSecondaryContainer),
                tertiary: hexFromArgb(scheme.tertiary),
                onTertiary: hexFromArgb(scheme.onTertiary),
                tertiaryContainer: hexFromArgb(scheme.tertiaryContainer),
                onTertiaryContainer: hexFromArgb(scheme.onTertiaryContainer),
                error: hexFromArgb(scheme.error),
                onError: hexFromArgb(scheme.onError),
                errorContainer: hexFromArgb(scheme.errorContainer),
                onErrorContainer: hexFromArgb(scheme.onErrorContainer),
                outline: hexFromArgb(scheme.outline),
                outlineVariant: hexFromArgb(scheme.outlineVariant),
                surface: hexFromArgb(scheme.surface),
                onSurface: hexFromArgb(scheme.onSurface),
                surfaceVariant: hexFromArgb(scheme.surfaceVariant),
                onSurfaceVariant: hexFromArgb(scheme.onSurfaceVariant),
                inverseSurface: hexFromArgb(scheme.inverseSurface),
                inverseOnSurface: hexFromArgb(scheme.inverseOnSurface),
                inversePrimary: hexFromArgb(scheme.inversePrimary)
            };

            // Add surface container tokens if the library supports them or calculate them
            // M3 dynamic color usually provides these via the HCT/DynamicColor API, 
            // but the simplified 'scheme' object might miss them.
            // We calculate them based on the surface color and standard M3 tonal offsets if missing.
            const palette = theme.palettes.neutral;
            if (isDark) {
                tokens.surfaceDim = hexFromArgb(palette.tone(6));
                tokens.surfaceBright = hexFromArgb(palette.tone(24));
                tokens.surfaceContainerLowest = hexFromArgb(palette.tone(4));
                tokens.surfaceContainerLow = hexFromArgb(palette.tone(10));
                tokens.surfaceContainer = hexFromArgb(palette.tone(12));
                tokens.surfaceContainerHigh = hexFromArgb(palette.tone(17));
                tokens.surfaceContainerHighest = hexFromArgb(palette.tone(22));
            } else {
                tokens.surfaceDim = hexFromArgb(palette.tone(87));
                tokens.surfaceBright = hexFromArgb(palette.tone(98));
                tokens.surfaceContainerLowest = hexFromArgb(palette.tone(100));
                tokens.surfaceContainerLow = hexFromArgb(palette.tone(96));
                tokens.surfaceContainer = hexFromArgb(palette.tone(94));
                tokens.surfaceContainerHigh = hexFromArgb(palette.tone(92));
                tokens.surfaceContainerHighest = hexFromArgb(palette.tone(90));
            }

            return tokens;
        }

        function applyThemeColors(colors) {
            const root = document.documentElement;
            for (const [key, value] of Object.entries(colors)) {
                root.style.setProperty('--md-sys-color-' + key.replace(/[A-Z]/g, m => "-" + m.toLowerCase()), value);
            }
        }

        function updateStrategyChange() {
            const select = document.getElementById('update-strategy-select');
            const desc = document.getElementById('strategy-desc');
            if (select.value === 'stable') {
                desc.textContent = "Stable: Use latest git tags (Recommended).";
            } else {
                desc.textContent = "Latest: Use latest branch commits (Bleeding edge).";
            }
            syncSettings();
        }

        async function toggleOdidoVpn() {
            const toggle = document.getElementById('odido-vpn-switch');
            const newState = !toggle.classList.contains('active');
            toggle.classList.toggle('active', newState);
            
            try {
                await apiCall("/theme", {
                    method: 'POST',
                    body: JSON.stringify({ odido_use_vpn: newState })
                });
                
                if (newState) {
                    showSnackbar("Odido API will now route through VPN. A stack restart is required for this change to take effect.", "Restart Now", restartStack);
                } else {
                    showSnackbar("Odido API will now use your home IP. A stack restart is required for this change to take effect.", "Restart Now", restartStack);
                }
            } catch (e) {
                toggle.classList.toggle('active', !newState); // Revert on failure
                showSnackbar("Failed to save VPN setting: " + e.message);
            }
        }

        async function syncSettings() {
            if (!isAdmin) return;
            const seed = document.getElementById('theme-seed-color').value;
            const isLight = document.documentElement.classList.contains('light-mode');
            const isPrivacy = document.body.classList.contains('privacy-mode');
            const activeFilter = localStorage.getItem('dashboard_filter') || 'all';
            const sessionTimeout = document.getElementById('session-timeout-input') ? document.getElementById('session-timeout-input').value : 30;
            const updateStrategy = document.getElementById('update-strategy-select') ? document.getElementById('update-strategy-select').value : 'stable';
            const odidoVpnSwitch = document.getElementById('odido-vpn-switch');
            const odidoUseVpn = odidoVpnSwitch ? odidoVpnSwitch.classList.contains('active') : true;
            
            const settings = {
                seed,
                theme: isLight ? 'light' : 'dark',
                privacy_mode: isPrivacy,
                dashboard_filter: activeFilter,
                is_admin: isAdmin,
                session_timeout: parseInt(sessionTimeout),
                update_strategy: updateStrategy,
                odido_use_vpn: odidoUseVpn,
                timestamp: Date.now()
            };

            try {
                await apiCall("/theme", {
                    method: 'POST',
                    body: JSON.stringify(settings)
                });
            } catch (e) { console.error("Settings sync failed", e); }
        }



        async function saveThemeSettings() {
            await syncSettings();
            showSnackbar("Settings synchronized to server");
        }

        async function openProjectSizeModal() {
            const modal = document.getElementById('project-size-modal');
            const content = document.getElementById('project-size-content');
            const loading = document.getElementById('project-size-loading');
            const list = document.getElementById('project-size-list');
            
            modal.style.display = 'flex';
            content.style.display = 'none';
            loading.style.display = 'block';
            
            try {
                const res = await apiCall("/project-details");
                const data = await res.json();
                
                list.innerHTML = '';
                if (data.breakdown) {
                    data.breakdown.forEach(item => {
                        const row = document.createElement('div');
                        row.className = 'list-item';
                        row.style.margin = '0';
                        row.style.borderBottom = '1px solid var(--md-sys-color-outline-variant)';
                        row.style.borderRadius = '0';

                        row.innerHTML = `
                            <div class="flex-row align-center gap-16 flex-1" style="min-width: 0;">
                                <span class="material-symbols-rounded" style="color: var(--md-sys-color-primary); font-size: 24px;">${item.icon}</span>
                                <span class="body-medium" style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${item.category}</span>
                            </div>
                            <span class="label-large" style="white-space: nowrap; margin-left: 12px;">${formatBytes(item.size * 1024 * 1024)}</span>
                        `;
                        list.appendChild(row);
                    });
                }
                
                if (data.reclaimable > 0) {
                    const row = document.createElement('div');
                    row.className = 'list-item';
                    row.style.margin = '0';
                    row.style.borderRadius = '0';
                    row.innerHTML = `
                        <div class="flex-row align-center gap-16 flex-1" style="min-width: 0;">
                            <span class="material-symbols-rounded" style="color: var(--md-sys-color-error); font-size: 24px;">delete_sweep</span>
                            <span class="body-medium" style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Reclaimable assets</span>
                        </div>
                        <span class="label-large" style="white-space: nowrap; margin-left: 12px; color: var(--md-sys-color-error);">${formatBytes(data.reclaimable * 1024 * 1024)}</span>
                    `;
                    list.appendChild(row);
                }
                
                loading.style.display = 'none';
                content.style.display = 'block';
            } catch (e) {
                showSnackbar("Failed to load storage details: " + e.message);
                closeProjectSizeModal();
            }
        }

        function closeProjectSizeModal() {
            document.getElementById('project-size-modal').style.display = 'none';
        }

        async function purgeUnusedImages(e) {
            if (!await showDialog({
                title: 'Clean Storage?',
                message: "This will permanently delete all dangling Docker images and unused build cache. Images currently in use by containers will NOT be affected. Proceed?",
                confirmText: 'Start Cleanup',
                confirmClass: 'btn btn-filled'
            })) return;
            
            const btn = e ? e.target.closest('button') : document.querySelector('#project-size-content button');
            const originalHtml = btn ? btn.innerHTML : 'Purge Unused Assets';
            if (btn) {
                btn.disabled = true;
                // Use a simpler loading state to avoid double icons
                btn.innerHTML = 'Cleaning Assets...';
            }

            try {
                const res = await apiCall("/purge-images", { 
                    method: 'POST' 
                });
                const result = await res.json();
                if (result.success) {
                    showSnackbar(result.message || "Storage optimized successfully", "OK");
                    closeProjectSizeModal();
                    fetchSystemHealth(); // Refresh main dashboard size
                } else {
                    throw new Error(result.error);
                }
            } catch (e) {
                showSnackbar("Optimization failed: " + e.message);
            } finally {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = originalHtml;
                }
            }
        }

        async function uninstallStack() {
            if (!await showDialog({
                title: 'Uninstall System?',
                message: "⚠️ DANGER: This will permanently remove all containers, volumes, and data. This cannot be undone. Are you absolutely sure?",
                confirmText: 'Proceed',
                confirmClass: 'btn btn-filled'
            })) return;

            if (!await showDialog({
                title: 'Final Confirmation',
                message: "LAST WARNING: Final confirmation required to proceed with uninstallation.",
                confirmText: 'Uninstall Forever',
                confirmClass: 'btn btn-filled'
            })) return;
            
            showSnackbar("Uninstallation sequence initiated...");
            try {
                const res = await apiCall("/uninstall", { 
                    method: 'POST' 
                });
                const result = await res.json();
                if (result.success) {
                    showSnackbar("System removed. Redirecting...");
                    setTimeout(() => window.location.href = "about:blank", 3000);
                } else {
                    throw new Error(result.error || "Uninstall failed");
                }
            } catch (e) {
                showSnackbar("Error during uninstall: " + e.message);
            }
        }

        async function loadAllSettings() {
            try {
                const res = await apiCall("/theme?_=" + Date.now());
                if (!res.ok) {
                    if (res.status >= 500) return; // Silent skip if backend not ready
                    throw new Error("Server responded with " + res.status);
                }
                const data = await res.json();
                
                // 1. Seed & Colors
                if (data.seed) {
                    const picker = document.getElementById('theme-seed-color');
                    if (picker) picker.value = data.seed;
                    applyThemeColors(data.colors || generateM3Palette(data.seed));
                }
                
                // 2. Theme (Light/Dark)
                if (data.theme) {
                    const isLight = data.theme === 'light';
                    document.documentElement.classList.toggle('light-mode', isLight);
                    localStorage.setItem('theme', data.theme);
                    updateThemeIcon();
                }
                
                // 3. Privacy Mode
                if (data.hasOwnProperty('privacy_mode')) {
                    const toggle = document.getElementById('privacy-switch');
                    if (toggle) toggle.classList.toggle('active', data.privacy_mode);
                    document.body.classList.toggle('privacy-mode', data.privacy_mode);
                    localStorage.setItem('privacy_mode', data.privacy_mode ? 'true' : 'false');
                    updateProfileDisplay();
                }
                
                // 4. Dashboard Filter - Default to all categories active (excluding 'all' chip)
                const filter = data.dashboard_filter || localStorage.getItem('dashboard_filter') || 'apps,system,dns,tools';
                localStorage.setItem('dashboard_filter', filter);
                const cats = filter.split(',');
                document.querySelectorAll('.filter-chip').forEach(c => {
                    if (cats.includes(c.dataset.target)) c.classList.add('active');
                    else if (cats.length === 1 && cats[0] === 'all' && c.dataset.target === 'all') c.classList.add('active');
                    else c.classList.remove('active');
                });
                updateGridVisibility();

                // 5. Admin Mode
                if (data.hasOwnProperty('is_admin')) {
                    isAdmin = data.is_admin;
                    sessionStorage.setItem('is_admin', isAdmin ? 'true' : 'false');
                    updateAdminUI();
                }

                // 6. Session Timeout
                if (data.session_timeout) {
                    const timeoutInput = document.getElementById('session-timeout-input');
                    if (timeoutInput) timeoutInput.value = data.session_timeout;
                }
                
                // 7. Odido VPN Mode (defaults to true/enabled)
                if (data.hasOwnProperty('odido_use_vpn')) {
                    const toggle = document.getElementById('odido-vpn-switch');
                    if (toggle) toggle.classList.toggle('active', data.odido_use_vpn);
                } else {
                    // Default to enabled if not set
                    const toggle = document.getElementById('odido-vpn-switch');
                    if (toggle) toggle.classList.add('active');
                }
            } catch(e) { 
                console.warn("Failed to load settings from server", e);
                // Fallback to local defaults if server fails
                if (!localStorage.getItem('dashboard_filter')) {
                    localStorage.setItem('dashboard_filter', 'apps,system,dns,tools');
                }
                const filter = localStorage.getItem('dashboard_filter');
                const cats = filter.split(',');
                document.querySelectorAll('.filter-chip').forEach(c => {
                    if (cats.includes(c.dataset.target)) c.classList.add('active');
                    else c.classList.remove('active');
                });
                updateGridVisibility();
                
                // Default odido VPN toggle to enabled on failure
                const toggle = document.getElementById('odido-vpn-switch');
                if (toggle) toggle.classList.add('active');
            }
        }

        function hexToRgb(hex) {
            const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
            return result ? {
                r: parseInt(result[1], 16),
                g: parseInt(result[2], 16),
                b: parseInt(result[3], 16)
            } : { r:0, g:0, b:0 };
        }

        function rgbToHsl(r, g, b) {
            r /= 255, g /= 255, b /= 255;
            const max = Math.max(r, g, b), min = Math.min(r, g, b);
            let h, s, l = (max + min) / 2;
            if (max == min) h = s = 0;
            else {
                const d = max - min;
                s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
                switch (max) {
                    case r: h = (g - b) / d + (g < b ? 6 : 0); break;
                    case g: h = (b - r) / d + 2; break;
                    case b: h = (r - g) / d + 4; break;
                }
                h /= 6;
            }
            return { h, s, l };
        }

        function hslToHex(h, s, l) {
            let r, g, b;
            if (s == 0) r = g = b = l;
            else {
                const hue2rgb = (p, q, t) => {
                    if (t < 0) t += 1;
                    if (t > 1) t -= 1;
                    if (t < 1/6) return p + (q - p) * 6 * t;
                    if (t < 1/2) return q;
                    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                    return p;
                };
                const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
                const p = 2 * l - q;
                r = hue2rgb(p, q, h + 1/3);
                g = hue2rgb(p, q, h);
                b = hue2rgb(p, q, h - 1/3);
            }
            return rgbToHex(Math.round(r * 255), Math.round(g * 255), Math.round(b * 255));
        }

        // Theme management
        function toggleTheme() {
            const isLight = document.documentElement.classList.toggle('light-mode');
            const newTheme = isLight ? 'light' : 'dark';
            localStorage.setItem('theme', newTheme);
            updateThemeIcon();
            
            // Apply immediate color updates if a seed exists
            const picker = document.getElementById('theme-seed-color');
            if (picker && picker.value) {
                applyThemeColors(generateM3Palette(picker.value));
            }
            
            syncSettings();
            showSnackbar(`Switched to ${isLight ? 'Light' : 'Dark'} mode`);
        }

        function updateThemeIcon() {
            const icon = document.getElementById('theme-icon');
            const isLight = document.documentElement.classList.contains('light-mode');
            if (icon) icon.textContent = isLight ? 'dark_mode' : 'light_mode';
        }

        function initTheme() {
            const savedTheme = localStorage.getItem('theme');
            const savedSeed = localStorage.getItem('theme_seed') || '#D0BCFF';
            const systemPrefersLight = window.matchMedia('(prefers-color-scheme: light)').matches;
            
            const isLight = savedTheme === 'light' || (!savedTheme && systemPrefersLight);
            if (isLight) {
                document.documentElement.classList.add('light-mode');
            } else {
                document.documentElement.classList.remove('light-mode');
            }
            
            // Apply saved seed or default
            const picker = document.getElementById('theme-seed-color');
            if (picker) picker.value = savedSeed;
            const hexEl = document.getElementById('theme-seed-hex');
            if (hexEl) hexEl.textContent = savedSeed.toUpperCase();
            
            if (typeof generateM3Palette === 'function') {
                applyThemeColors(generateM3Palette(savedSeed));
            }
            
            updateThemeIcon();
        }

        // Privacy toggle functionality
        function togglePrivacy() {
            const toggle = document.getElementById('privacy-switch');
            const body = document.body;
            const isPrivate = toggle.classList.toggle('active');
            if (isPrivate) {
                body.classList.add('privacy-mode');
                localStorage.setItem('privacy_mode', 'true');
            } else {
                body.classList.remove('privacy-mode');
                localStorage.setItem('privacy_mode', 'false');
            }
            updateProfileDisplay();
            syncSettings();
        }
        
        function initPrivacyMode() {
            const savedMode = localStorage.getItem('privacy_mode');
            if (savedMode === 'true') {
                const toggle = document.getElementById('privacy-switch');
                if (toggle) toggle.classList.add('active');
                document.body.classList.add('privacy-mode');
            }
            updateProfileDisplay();
        }

        // Link Mode (IP vs Domain) functionality
        function toggleLinkMode() {
            const toggle = document.getElementById('link-mode-switch');
            const label = document.getElementById('link-mode-label');
            const useDomain = toggle.classList.toggle('active');
            
            if (useDomain) {
                localStorage.setItem('link_mode_domain', 'true');
                if(label) label.textContent = 'Domain links';
            } else {
                localStorage.setItem('link_mode_domain', 'false');
                if(label) label.textContent = 'IP links';
            }
            renderDynamicGrid();
        }

        function initLinkMode() {
            const useDomain = localStorage.getItem('link_mode_domain') === 'true';
            const toggle = document.getElementById('link-mode-switch');
            const label = document.getElementById('link-mode-label');
            
            if (useDomain) {
                if(toggle) toggle.classList.add('active');
                if(label) label.textContent = 'Domain links';
            } else {
                if(toggle) toggle.classList.remove('active');
                if(label) label.textContent = 'IP links';
            }
        }



        function updateDnsSetupDisplay(isTrusted, hasDesec) {
            const trusted = document.getElementById('dns-setup-trusted');
            const untrusted = document.getElementById('dns-setup-untrusted');
            const local = document.getElementById('dns-setup-local');
            
            if (!trusted || !untrusted || !local) return;

            // Hide all first
            trusted.style.display = 'none';
            untrusted.style.display = 'none';
            local.style.display = 'none';

            if (isTrusted) {
                trusted.style.display = 'flex';
            } else if (hasDesec) {
                untrusted.style.display = 'flex';
            } else {
                local.style.display = 'flex';
            }
        }

        async function fetchCertStatus() {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 10000);
                const res = await apiCall("/certificate-status", { signal: controller.signal });
                clearTimeout(timeoutId);
                
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                
                const loadingBox = document.getElementById('cert-loading');
                if (loadingBox) loadingBox.style.display = 'none';

                document.getElementById('cert-type').textContent = data.type || "--";
                document.getElementById('cert-subject').textContent = data.subject || "--";
                document.getElementById('cert-issuer').textContent = data.issuer || "--";
                
                // Make the year slightly bolder
                const expiresEl = document.getElementById('cert-to');
                if (data.expires && data.expires !== "--") {
                    const parts = data.expires.split(' ');
                    if (parts.length > 0) {
                        const lastPart = parts[parts.length - 1];
                        const rest = data.expires.substring(0, data.expires.lastIndexOf(lastPart));
                        expiresEl.innerHTML = rest + '<span style="font-weight: 600;">' + lastPart + '</span>';
                    } else {
                        expiresEl.textContent = data.expires;
                    }
                } else {
                    expiresEl.textContent = "--";
                }
                
                const badge = document.getElementById('cert-status-badge');
                const isTrusted = data.status && data.status.includes("Trusted");
                const isSelfSigned = data.status && data.status.includes("Self-Signed");
                const hasDesec = "$DESEC_DOMAIN" !== "";

                if (isTrusted) {
                    badge.className = "chip vpn"; // Use primary-container color
                    badge.innerHTML = '<span class="material-symbols-rounded" style="font-size:16px;">verified</span> Trusted';
                    badge.dataset.tooltip = "✓ Globally Trusted: Valid certificate from Let's Encrypt.";
                } else if (isSelfSigned) {
                    badge.className = "chip admin"; // Use secondary-container color
                    badge.innerHTML = '<span class="material-symbols-rounded" style="font-size:16px;">warning</span> Self-Signed';
                    badge.dataset.tooltip = "⚠ Self-Signed (Local): Devices will show security warnings. deSEC configuration recommended.";
                } else if (data.status === "Rate Limited") {
                    badge.className = "chip tertiary";
                    badge.innerHTML = '<span class="material-symbols-rounded" style="font-size:16px;">timer</span> Rate Limited';
                    badge.dataset.tooltip = data.error || "Let's Encrypt rate limit reached. Re-attempting automatically.";
                } else {
                    badge.className = "chip tertiary";
                    badge.textContent = data.status || "Unknown";
                    badge.dataset.tooltip = data.error || "Status unknown or certificate missing.";
                }
                
                const failInfo = document.getElementById('ssl-failure-info');
                const retryBtn = document.getElementById('ssl-retry-btn');

                if (data.error) {
                    failInfo.style.display = 'block';
                    document.getElementById('ssl-failure-reason').textContent = data.error;
                    if (retryBtn) retryBtn.style.display = 'inline-flex';
                } else {
                    failInfo.style.display = 'none';
                    if (retryBtn) {
                        retryBtn.style.display = isTrusted ? 'none' : 'inline-flex';
                    }
                }

                updateDnsSetupDisplay(isTrusted, hasDesec);

            } catch(e) { 
                console.error('Cert status fetch error:', e);
            } finally {
                const loadingBox = document.getElementById('cert-loading');
                if (loadingBox) loadingBox.style.display = 'none';
            }
        }

        async function requestSslCheck() {
            const btn = document.getElementById('ssl-retry-btn');
            btn.disabled = true;
            btn.style.opacity = '0.5';
            try {
                const res = await apiCall("/request-ssl-check");
                const data = await res.json();
                if (data.success) {
                    await showDialog({type:'alert', title:'Success', message: "SSL Check triggered in background. This may take 2-3 minutes. Refresh the dashboard later."});
                } else {
                    await showDialog({type:'alert', title:'Error', message: "Failed to trigger SSL check: " + (data.error || "Unknown error")});
                }
            } catch (e) {
                await showDialog({type:'alert', title:'Error', message: "Network error while triggering SSL check."});
            }
            setTimeout(() => { btn.disabled = false; btn.style.opacity = '1'; }, 10000);
        }

        async function checkUpdates() {
            showSnackbar("Update check initiated... checking images and sources.");
            try {
                const res = await apiCall("/check-updates");
                const data = await res.json();
                if (data.success) {
                    showSnackbar("Update check running... Please wait.", "OK");
                    // Poll for updates a few times
                    let checks = 0;
                    const interval = setInterval(async () => {
                        await fetchUpdates();
                        checks++;
                        if (checks >= 6) clearInterval(interval); // Stop after 30s
                    }, 5000);
                } else {
                    throw new Error(data.error);
                }
            } catch(e) {
                showSnackbar("Failed to initiate update check: " + e.message);
            }
        }

        async function restartStack() {
            if (!await showDialog({
                title: 'Restart Stack?',
                message: "Are you sure you want to restart the entire stack? The dashboard and all services will be unreachable for approximately 30 seconds.",
                confirmText: 'Restart',
                confirmClass: 'btn btn-filled'
            })) return;
            
            try {
                const res = await apiCall("/restart-stack", {
                    method: 'POST'
                });
                
                const data = await res.json();
                if (data.success) {
                    // Show a persistent overlay or alert
                    document.body.innerHTML = `
                        <div style="display:flex; flex-direction:column; align-items:center; justify-content:center; height:100vh; background:var(--md-sys-color-surface); color:var(--md-sys-color-on-surface); font-family:sans-serif; text-align:center; padding:24px;">
                            <span class="material-symbols-rounded" style="font-size:64px; color:var(--md-sys-color-primary); margin-bottom:24px;">restart_alt</span>
                            <h1>Restarting Stack...</h1>
                            <p style="margin-top:16px; opacity:0.8;">The management interface is rebooting. This page will automatically refresh when the services are back online.</p>
                            <div style="margin-top:32px; width:48px; height:48px; border:4px solid var(--md-sys-color-surface-container-highest); border-top:4px solid var(--md-sys-color-primary); border-radius:50%; animation: spin 1s linear infinite;"></div>
                            <style>
                                @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
                            </style>
                        </div>
                    `;
                    
                    // Poll for availability
                    let attempts = 0;
                    const checkAvailability = setInterval(async () => {
                        attempts++;
                        try {
                            const ping = await fetch(window.location.href, { mode: 'no-cors' });
                            clearInterval(checkAvailability);
                            window.location.reload();
                        } catch (e) {
                            if (attempts > 60) {
                                clearInterval(checkAvailability);
                                await showDialog({type:'alert', title:'Timeout', message: "Restart is taking longer than expected. Please refresh the page manually."});
                            }
                        }
                    }, 2000);
                } else {
                    throw new Error(data.error || "Unknown error");
                }
            } catch (e) {
                await showDialog({type:'alert', title:'Error', message: "Failed to initiate restart: " + e.message});
            }
        }
        
        async function fetchSystemHealth() {
            try {
                const res = await apiCall("/system-health");
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                
                const cpu = Math.round(data.cpu_percent || 0);
                const ramUsed = Math.round(data.ram_used || 0);
                const ramTotal = Math.round(data.ram_total || 0);
                const ramPct = Math.round((ramUsed / ramTotal) * 100);

                const sysCpu = document.getElementById('sys-cpu');
                if(sysCpu) sysCpu.textContent = cpu + "%";
                const sysCpuFill = document.getElementById('sys-cpu-fill');
                if(sysCpuFill) sysCpuFill.style.width = cpu + "%";
                
                const sysRam = document.getElementById('sys-ram');
                if(sysRam) sysRam.textContent = ramUsed + " MB / " + ramTotal + " MB";
                const sysRamFill = document.getElementById('sys-ram-fill');
                if(sysRamFill) sysRamFill.style.width = ramPct + "%";
                
                const sysProj = document.getElementById('sys-project-size');
                if(sysProj) sysProj.textContent = (data.project_size || 0).toFixed(1) + " MB";
                
                const uptime = data.uptime || 0;
                const d = Math.floor(uptime / 86400);
                const h = Math.floor((uptime % 86400) / 3600);
                const m = Math.floor((uptime % 3600) / 60);
                const sysUp = document.getElementById('sys-uptime');
                if(sysUp) sysUp.textContent = d + "d " + h + "h " + m + "m";

                const driveStatus = document.getElementById('sys-drive-status');
                const drivePct = document.getElementById('sys-drive-pct');
                const driveContainer = document.getElementById('drive-health-container');
                const diskPercent = document.getElementById('sys-disk-percent');
                
                if(driveStatus) driveStatus.textContent = data.drive_status || "Unknown";
                if(drivePct) drivePct.textContent = (data.drive_health_pct || 0) + "% Health";
                if(diskPercent) diskPercent.textContent = (data.disk_percent || 0).toFixed(1) + "% used";

                if (driveStatus) {
                    if (data.drive_status === "Action Required") {
                        driveStatus.style.color = "var(--md-sys-color-error)";
                    } else if (data.drive_status && data.drive_status.includes("Warning")) {
                        driveStatus.style.color = "var(--md-sys-color-warning)";
                    } else {
                        driveStatus.style.color = "var(--md-sys-color-success)";
                    }
                }

                if (driveContainer) {
                    if (data.smart_alerts && data.smart_alerts.length > 0) {
                        driveContainer.dataset.tooltip = "SMART Alerts:\n" + data.smart_alerts.join("\n");
                    } else {
                        driveContainer.dataset.tooltip = "Drive is reporting healthy SMART status.";
                    }
                }

            } catch(e) { console.error("Health fetch error:", e); }
        }

        document.addEventListener('DOMContentLoaded', () => {
            // Load deSEC config if available
            apiCall("/status").then(r => r.json()).then(data => {
                if (data.gluetun && data.gluetun.desec_domain) {
                    document.getElementById('desec-domain-input').placeholder = data.gluetun.desec_domain;
                }
            }).catch(() => {});

            // Tooltip Initialization
            const tooltipBox = document.createElement('div');
            tooltipBox.className = 'tooltip-box';
            document.body.appendChild(tooltipBox);
            
            let tooltipTimeout = null;

            const hideTooltip = () => {
                if (tooltipTimeout) clearTimeout(tooltipTimeout);
                tooltipBox.classList.remove('visible');
                setTimeout(() => {
                    if (!tooltipBox.classList.contains('visible')) {
                        tooltipBox.style.display = 'none';
                    }
                }, 150);
            };

            document.addEventListener('mouseover', (e) => {
                const target = e.target.closest('[data-tooltip]');
                if (!target) return;

                if (tooltipTimeout) clearTimeout(tooltipTimeout);
                
                tooltipTimeout = setTimeout(() => {
                    tooltipBox.textContent = target.dataset.tooltip;
                    tooltipBox.style.display = 'block';
                    tooltipBox.offsetHeight;
                    tooltipBox.classList.add('visible');

                    const rect = target.getBoundingClientRect();
                    const boxRect = tooltipBox.getBoundingClientRect();
                    
                    let top = rect.top - boxRect.height - 12;
                    let left = rect.left + (rect.width / 2) - (boxRect.width / 2);

                    if (top < 12) top = rect.bottom + 12;
                    if (left < 12) left = 12;
                    if (left + boxRect.width > window.innerWidth - 12) {
                        left = window.innerWidth - boxRect.width - 12;
                    }
                    if (top + boxRect.height > window.innerHeight - 12) {
                        top = window.innerHeight - boxRect.height - 12;
                    }

                    tooltipBox.style.top = top + 'px';
                    tooltipBox.style.left = left + 'px';
                }, 150); 
            });

            document.addEventListener('mouseout', (e) => {
                if (e.target.closest('[data-tooltip]')) {
                    hideTooltip();
                }
            });

            // Hide tooltip on scroll to prevent persistence
            window.addEventListener('scroll', hideTooltip, true);

            const savedFilter = localStorage.getItem('dashboard_filter') || 'all';
            filterCategory(savedFilter);
            if (window.location.protocol === 'https:') {
                const badge = document.getElementById('https-badge');
                if (badge) badge.style.display = 'inline-flex';
            }



            initPrivacyMode();
            initTheme();
            initStaticPresets();
            fetchContainerIds();
            updateAdminUI();
            
            // Guest-accessible background data
            setTimeout(() => {
                fetchStatus(); 
                fetchCertStatus(); 
                fetchMetrics(); 
                fetchSystemHealth();
                loadAllSettings(); 
            }, 2000);
            
            // Admin-only background data
            if (isAdmin) {
                setTimeout(() => {
                    fetchProfiles(); 
                    fetchWgClients(); 
                    fetchOdidoStatus(); 
                    startLogStream(); 
                    fetchUpdates();
                }, 2000);
            }

            setInterval(fetchStatus, 15000);
            setInterval(fetchSystemHealth, 15000);
            setInterval(fetchMetrics, 30000);
            setInterval(fetchCertStatus, 300000); // Check cert status every 5 mins
            
            if (isAdmin) {
                setInterval(fetchUpdates, 300000); // Check for source updates every 5 mins
                setInterval(fetchOdidoStatus, 60000);  // Reduced polling frequency to respect Odido API
            }
            setInterval(fetchContainerIds, 60000);
        });

        // WireGuard Client Management
        async function fetchWgClients() {
            if (!isAdmin) return;
            try {
                const res = await apiCall("/wg/clients");
                if (!res.ok) return;
                const clients = await res.json();
                renderClientList(clients);
            } catch (e) {
                console.error("Failed to fetch WG clients:", e);
            }
        }

        function renderClientList(clients) {
            const list = document.getElementById('wg-client-list');
            if (!list) return;
            list.innerHTML = '';
            
            if (!clients || clients.length === 0) {
                list.innerHTML = '<div style="padding: 24px; text-align: center; opacity: 0.6;"><span class="material-symbols-rounded" style="font-size: 48px;">devices</span><p class="body-medium">No clients configured</p></div>';
                return;
            }

            clients.forEach(client => {
                const row = document.createElement('div');
                row.className = 'list-item';
                row.style.margin = '0';
                row.style.borderRadius = 'var(--md-sys-shape-corner-medium)';
                row.style.background = 'var(--md-sys-color-surface-container-low)';
                row.style.border = '1px solid var(--md-sys-color-outline-variant)';
                
                const statusColor = client.handshakeAt && (Date.now() - new Date(client.handshakeAt).getTime() < 180000) ? 'var(--md-sys-color-success)' : 'var(--md-sys-color-outline)';
                const transfer = formatBytes(client.transferRx + client.transferTx);

                row.innerHTML = `
                    <div style="display:flex; align-items:center; justify-content:space-between; width:100%; gap:12px;">
                        <div style="display:flex; align-items:center; gap:12px; flex-grow:1;">
                            <span class="material-symbols-rounded" style="color: ${statusColor};" title="${client.enabled ? 'Enabled' : 'Disabled'}">smartphone</span>
                            <div style="display:flex; flex-direction:column;">
                                <span class="title-small" style="font-weight:500;">${client.name || 'Unnamed Client'}</span>
                                <span class="label-small monospace" style="opacity:0.7;">${client.address}</span>
                            </div>
                        </div>
                        <div style="display:flex; align-items:center; gap:8px;">
                            <span class="chip tertiary" style="height:24px; font-size:11px;">${transfer}</span>
                            <button onclick="showClientQr('${client.id}', '${client.name}')" class="btn btn-icon" title="Show QR Code">
                                <span class="material-symbols-rounded">qr_code</span>
                            </button>
                            <button onclick="deleteClient('${client.id}', '${client.name}')" class="btn btn-icon" style="color:var(--md-sys-color-error);" title="Delete">
                                <span class="material-symbols-rounded">delete</span>
                            </button>
                        </div>
                    </div>
                `;
                list.appendChild(row);
            });
        }

        function openAddClientModal() {
            document.getElementById('add-client-modal').style.display = 'flex';
            document.getElementById('new-client-name').value = '';
            document.getElementById('new-client-name').focus();
        }

        async function createClient() {
            const name = document.getElementById('new-client-name').value.trim();
            if (!name) return;
            
            try {
                const res = await apiCall("/wg/clients", {
                    method: 'POST',
                    body: JSON.stringify({ name: name })
                });
                
                if (res.ok) {
                    showSnackbar("Client created successfully!");
                    document.getElementById('add-client-modal').style.display = 'none';
                    fetchWgClients();
                } else {
                    const err = await res.json();
                    showSnackbar("Failed to create client: " + (err.error || "Unknown error"));
                }
            } catch (e) {
                showSnackbar("Error creating client: " + e.message);
            }
        }

        async function deleteClient(id, name) {
            if (!await showDialog({
                title: 'Delete Client?',
                message: `Delete client "${name}"? This cannot be undone.`,
                confirmText: 'Delete',
                confirmClass: 'btn btn-filled'
            })) return;
            try {
                const res = await apiCall("/wg/clients/" + id, { method: 'DELETE' });
                if (res.ok) {
                    showSnackbar("Client deleted.");
                    fetchWgClients();
                } else {
                    showSnackbar("Failed to delete client.");
                }
            } catch (e) {
                showSnackbar("Error deleting client: " + e.message);
            }
        }

        async function showClientQr(id, name) {
            const modal = document.getElementById('client-qr-modal');
            const container = document.getElementById('qrcode-container');
            const title = document.getElementById('qr-client-name');
            const link = document.getElementById('client-download-link');
            
            container.innerHTML = ''; // Clear previous
            title.textContent = name;
            modal.style.display = 'flex';
            
            try {
                // Fetch config content
                const res = await apiCall("/wg/clients/" + id + "/configuration"); // We need to add this to API proxy too? 
                // Wait, /wg/clients response usually includes config or we proxy download.
                // wg-easy API: GET /api/wireguard/client/:id/configuration -> returns file
                // Let's use a simpler approach: construct the download link via our API proxy or assume we fetch text.
                // Actually, let's add a config fetch endpoint to server.py or handle it here if we assume `GET /wg/clients` returned it?
                // wg-easy `GET /api/wireguard/client` returns list without config content usually.
                
                // Let's assume we implement `GET /wg/clients/:id/configuration` in proxy.
                // For now, let's fetch it as text.
                
                const confRes = await apiCall("/wg/clients/" + id + "/configuration"); 
                // Wait, we didn't add this route to server.py yet. We added /wg/clients/DELETE.
                // We need to add /wg/clients/ID/configuration to server.py!
                
                // Assuming we fix server.py:
                if (confRes.ok) {
                    const configText = await confRes.text(); // It comes as text/plain usually
                    
                    // Generate QR
                    new QRCode(container, {
                        text: configText,
                        width: 256,
                        height: 256
                    });
                    
                    // Setup download
                    const blob = new Blob([configText], { type: "text/plain;charset=utf-8" });
                    link.href = URL.createObjectURL(blob);
                    link.download = (name.replace(/\s/g, '_')) + ".conf";
                } else {
                    container.innerHTML = '<p class="error">Failed to load config</p>';
                }
            } catch (e) {
                console.error(e);
                container.innerHTML = '<p class="error">Error loading config</p>';
            }
        }
