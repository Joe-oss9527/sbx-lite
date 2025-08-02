const fs = require('fs');
const yaml = require('js-yaml');

const SBX_YAML = '/etc/sbx/sbx.yml';

function loadDoc() {
  const raw = fs.readFileSync(SBX_YAML, 'utf8');
  return yaml.load(raw);
}

function summary(doc) {
  const usersAll = Array.isArray(doc.users) ? doc.users : [];
  const users = usersAll.filter(u => u && u.enabled);
  const ib = doc.inbounds || {};
  const r = ib.reality || {};
  const w = ib.vless_ws_tls || {};
  const h = ib.hysteria2 || {};

  const usersBrief = users.map(u => ({
    name: u.name || '',
    enabled: !!u.enabled,
    hasToken: !!u.token,
    hasUUID: !!u.vless_uuid,
    hasHy2Pass: !!u.hy2_pass
  }));

  const anyHy2Pass = users.some(u => !!u.hy2_pass);
  const needHy2Pass = !!h.enabled;
  const globalHy2 = !!(h.global_password && String(h.global_password).length > 0);

  return {
    exportHost: (doc.export && doc.export.host) || "",
    cloudflareMode: doc.cloudflare_mode || "",
    usersCount: users.length,
    users: usersBrief,
    inbounds: {
      realityEnabled: !!r.enabled,
      realityPort: r.listen_port || 443,
      realityServerName: r.server_name || "",
      realityPrivateKeyPresent: !!r.private_key,
      realityShortIdPresent: !!r.short_id,

      wsEnabled: !!w.enabled,
      wsDomain: w.domain || "",
      wsPath: w.path || "/ws",
      wsPort: w.listen_port || 443,
      wsCertPath: w.cert_path || "",
      wsKeyPath: w.key_path || "",

      hy2Enabled: !!h.enabled,
      hy2Port: h.listen_port || 8443,
      hy2GlobalPassword: h.global_password || ""
    },
    hy2: {
      needHy2Pass: needHy2Pass,
      anyUserHy2Pass: anyHy2Pass,
      hasGlobalPassword: globalHy2
    }
  };
}

const mode = process.argv.includes('--sh') ? 'sh' : 'json';
const doc = loadDoc();
const data = summary(doc);

if (mode === 'json') {
  process.stdout.write(JSON.stringify(data, null, 2));
} else {
  const e = (k, v) => console.log(`${k}=${String(v).replace(/[\n\r]/g,'')}`);
  e('EXPORT_HOST', data.exportHost);
  e('CLOUDFLARE_MODE', data.cloudflareMode);
  e('USERS_COUNT', data.usersCount);
  // Print first user brief (legacy)
  const u = data.users[0] || {};
  e('U_NAME', u.name || '');
  e('U_TOKEN', u.hasToken ? '1' : '');
  e('U_UUID', u.hasUUID ? '1' : '');
  e('U_HY2', u.hasHy2Pass ? '1' : '');

  e('REALITY_ENABLED', data.inbounds.realityEnabled ? 1 : 0);
  e('REALITY_PORT', data.inbounds.realityPort);
  e('REALITY_SNI', data.inbounds.realityServerName);
  e('REALITY_PVT', data.inbounds.realityPrivateKeyPresent ? 1 : 0);
  e('REALITY_SID', data.inbounds.realityShortIdPresent ? 1 : 0);

  e('WS_ENABLED', data.inbounds.wsEnabled ? 1 : 0);
  e('WS_DOMAIN', data.inbounds.wsDomain);
  e('WS_PATH', data.inbounds.wsPath);
  e('WS_PORT', data.inbounds.wsPort);
  e('WS_CERTPATH', data.inbounds.wsCertPath);
  e('WS_KEYPATH', data.inbounds.wsKeyPath);

  e('HY2_ENABLED', data.inbounds.hy2Enabled ? 1 : 0);
  e('HY2_PORT', data.inbounds.hy2Port);
  e('HY2_ANY_USER_PASS', data.hy2.anyUserHy2Pass ? 1 : 0);
  e('HY2_GLOBAL_PASS', data.hy2.hasGlobalPassword ? 1 : 0);
}
