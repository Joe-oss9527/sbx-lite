const fs = require('fs');
const yaml = require('js-yaml');

const SBX_YAML = '/etc/sbx/sbx.yml';
const SBX_JSON = '/etc/sing-box/config.json';

function loadDoc() {
  const raw = fs.readFileSync(SBX_YAML, 'utf8');
  return yaml.load(raw);
}

function ensure(cond, msg){ if (!cond) throw new Error(msg); }

function buildUsers(arr, withHy2=false){
  const users = (arr || []).filter(u => u && u.enabled);
  ensure(users.length > 0, 'No enabled users in sbx.yml');
  const uuids = users.map(u => ({ uuid: String(u.vless_uuid || '').trim() }));
  uuids.forEach(u => ensure(u.uuid && u.uuid.length > 10, 'Missing vless_uuid for a user'));
  const hy2Users = users.map(u => ({ password: String(u.hy2_pass || '').trim() })).filter(u => !!u.password);
  return { vless: uuids, hy2: hy2Users };
}

function buildConfig(doc){
  const users = buildUsers(doc.users);
  const ib = doc.inbounds || {};
  const outbounds = [{ type: 'direct', tag: 'direct' }, { type: 'block', tag: 'block' }];
  const inbounds = [];

  // REALITY (VLESS TCP + TLS.reality)
  if (ib.reality && ib.reality.enabled) {
    const r = ib.reality;
    ensure(r.server_name, 'reality.server_name is required');
    ensure(r.private_key && r.short_id, 'reality.private_key/short_id is required');
    inbounds.push({
      type: 'vless',
      tag: 'in-reality',
      listen: '0.0.0.0',
      listen_port: r.listen_port || 443,
      users: users.vless.map(u => ({ uuid: u.uuid, flow: 'xtls-rprx-vision' })),
      tls: {
        enabled: true,
        server_name: r.server_name,
        reality: {
          enabled: true,
          private_key: r.private_key,
          short_id: r.short_id,
          handshake: { server: r.server_name, server_port: 443 }
        },
        alpn: ['h2','http/1.1']
      }
    });
  }

  // VLESS-WS-TLS
  if (ib.vless_ws_tls && ib.vless_ws_tls.enabled) {
    const w = ib.vless_ws_tls;
    ensure(w.domain, 'vless_ws_tls.domain is required');
    ensure(w.cert_path && w.key_path, 'vless_ws_tls.cert_path/key_path is required');
    inbounds.push({
      type: 'vless',
      tag: 'in-ws',
      listen: '0.0.0.0',
      listen_port: w.listen_port || 443,
      users: users.vless,
      tls: {
        enabled: true,
        server_name: w.domain,
        certificate_path: w.cert_path,
        key_path: w.key_path
      },
      transport: { type: 'ws', path: w.path || '/ws' }
    });
  }

  // Hysteria2 (TLS required)
  if (ib.hysteria2 && ib.hysteria2.enabled) {
    const h = ib.hysteria2;
    // Prefer per-user passwords; fallback to global_password
    const { hy2 } = buildUsers(doc.users, true);
    const usersHy = hy2.length > 0 ? hy2 : (h.global_password ? [{ password: String(h.global_password) }] : []);
    ensure(usersHy.length > 0, 'hysteria2 enabled but no user.hy2_pass or global_password');
    ensure(h.tls && ((h.tls.certificate_path && h.tls.key_path) || h.tls.acme), 'hysteria2.tls certificate_path/key_path or acme is required');
    const tls = { enabled: true };
    if (h.tls.acme) {
      tls.acme = h.tls.acme; // user provided acme block (even if we generally avoid)
    } else {
      tls.certificate_path = h.tls.certificate_path;
      tls.key_path = h.tls.key_path;
    }
    inbounds.push({
      type: 'hysteria2',
      tag: 'in-hy2',
      listen: '0.0.0.0',
      listen_port: h.listen_port || 8443,
      users: usersHy,
      up_mbps: h.up_mbps || 100,
      down_mbps: h.down_mbps || 100,
      tls
    });
  }

  ensure(inbounds.length > 0, 'No inbound enabled. Enable at least one of reality/ws/hysteria2.');
  return {
    log: { level: 'info' },
    inbounds,
    outbounds
  };
}

function main(){
  const doc = loadDoc();
  const conf = buildConfig(doc);
  fs.writeFileSync(SBX_JSON, JSON.stringify(conf, null, 2));
  console.log('Wrote ' + SBX_JSON);
}

main();
