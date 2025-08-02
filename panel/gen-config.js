import fs from 'fs';
import yaml from 'js-yaml';

const SBX_YML = '/etc/sbx/sbx.yml';
const OUT_JSON = '/etc/sing-box/config.json';

function ensure(cond, msg){ if(!cond) throw new Error(msg); }

function guardPorts(cfg){
  const re = cfg?.inbounds?.reality;
  const ws = cfg?.inbounds?.vless_ws_tls;
  if (re?.enabled && ws?.enabled){
    const p1 = re.listen_port || 443;
    const p2 = ws.listen_port || 443;
    if (p1 === p2){
      throw new Error(`Port conflict: reality(${p1}) vs vless_ws_tls(${p2}).`);
    }
  }
}

function tlsFrom(wsOrHy, fallbackSNI){
  const ac = wsOrHy?.acme;
  if (ac?.enabled){
    const acme = {
      provider: ac.provider || 'letsencrypt',
      email: ac.email || undefined,
      directory_url: ac.directory_url || undefined,
      domains: ac.domain || undefined,
      data_directory: ac.data_directory || '/var/lib/sbx/acme',
      disable_http_challenge: !!ac.disable_http_challenge,
      disable_tls_alpn_challenge: !!ac.disable_tls_alpn_challenge,
      alternative_http_port: ac.alternative_http_port || undefined,
      alternative_tls_port: ac.alternative_tls_port || undefined,
      dns01_challenge: ac.dns01_challenge || undefined
    };
    return { enabled: true, acme };
  }
  // file certs
  const cert = wsOrHy.certificate_path || wsOrHy.cert_path;
  const key  = wsOrHy.key_path;
  ensure(cert && key, 'tls certificate_path/key_path (or acme.enabled) required');
  return { enabled: true, certificate_path: cert, key_path: key };
}

function buildReality(cfg, users){
  const r = cfg.inbounds.reality;
  if (!r?.enabled) return null;
  ensure(r.server_name, 'reality.server_name required');
  ensure(r.private_key && r.short_id, 'reality.private_key/short_id required');
  const vusers = users.filter(u=>u.enabled && u.vless_uuid).map(u=>({ uuid: u.vless_uuid, flow: 'xtls-rprx-vision' }));
  ensure(vusers.length>0, 'no enabled users with vless_uuid');
  return {
    type: "vless",
    tag: "in-reality",
    listen: "::",
    listen_port: r.listen_port || 443,
    users: vusers,
    tls: {
      enabled: true,
      server_name: r.server_name,
      reality: { enabled: true, private_key: r.private_key, short_id: [r.short_id], handshake: { server: r.server_name, server_port: 443 } },
      alpn: ["h2","http/1.1"]
    }
  };
}

function buildWs(cfg, users){
  const wsi = cfg.inbounds.vless_ws_tls;
  if (!wsi?.enabled) return null;
  ensure(wsi.domain, 'vless_ws_tls.domain required');
  const tls = tlsFrom({ ...wsi, certificate_path: wsi.cert_path, key_path: wsi.key_path }, wsi.domain);
  const vusers = users.filter(u=>u.enabled && u.vless_uuid).map(u=>({ uuid: u.vless_uuid }));
  ensure(vusers.length>0, 'no enabled users with vless_uuid');
  return {
    type: "vless",
    tag: "in-ws",
    listen: "::",
    listen_port: wsi.listen_port || 443,
    users: vusers,
    tls,
    transport: { type: "ws", path: wsi.path || "/ws", headers: { Host: wsi.domain } }
  };
}

function buildHy2(cfg, users){
  const hy = cfg.inbounds.hysteria2;
  if (!hy?.enabled) return null;

  const pwds = users.filter(u=>u.enabled && u.hy2_pass).map(u=>({ password: u.hy2_pass }));
  if (pwds.length === 0 && hy.global_password) pwds.push({ password: hy.global_password });
  ensure(pwds.length>0, 'hysteria2 enabled but no password');

  let tls = null;
  if (hy.tls?.acme?.enabled){
    tls = tlsFrom({ acme: hy.tls.acme }, (hy.tls.acme.domain && hy.tls.acme.domain[0]) || undefined);
  } else {
    ensure(hy.tls?.certificate_path && hy.tls?.key_path, 'hysteria2.tls certs or acme required');
    tls = { enabled: true, certificate_path: hy.tls.certificate_path, key_path: hy.tls.key_path };
  }

  const inb = { type: "hysteria2", tag: "in-hy2", listen: "::", listen_port: hy.listen_port || 8443, users: pwds, tls };
  if (!isNaN(Number(hy.up_mbps))) inb.up_mbps = Number(hy.up_mbps);
  if (!isNaN(Number(hy.down_mbps))) inb.down_mbps = Number(hy.down_mbps);
  return inb;
}

function main(){
  const cfg = yaml.load(fs.readFileSync(SBX_YML, 'utf8'));
  guardPorts(cfg);
  const users = cfg.users || [];
  const inbounds = [];
  const r = buildReality(cfg, users); if (r) inbounds.push(r);
  const ws = buildWs(cfg, users); if (ws) inbounds.push(ws);
  const hy = buildHy2(cfg, users); if (hy) inbounds.push(hy);
  if (inbounds.length === 0) throw new Error('no inbound enabled');

  const outbounds = [{ type: "direct", tag: "direct" }, { type: "block", tag: "block" }];
  const conf = { log: { level: "info" }, inbounds, outbounds };

  fs.mkdirSync('/etc/sing-box', { recursive: true });
  fs.writeFileSync(OUT_JSON, JSON.stringify(conf, null, 2));
  console.log(`Wrote ${OUT_JSON}`);
}

try { main(); } catch (e) { console.error('[gen-config] ERROR:', e.message); process.exit(1); }
