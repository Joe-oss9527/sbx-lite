import fs from 'fs';
import yaml from 'js-yaml';

const SBX_YML = '/etc/sbx/sbx.yml';
const OUT_JSON = '/etc/sing-box/config.json';

function ensure(cond, msg){ if(!cond) { throw new Error(msg); } }

function truthy(v){ return v !== undefined && v !== null && v !== '' && !(typeof v==='boolean' && v===false); }

function portConflictGuard(cfg){
  const re = cfg?.inbounds?.reality;
  const ws = cfg?.inbounds?.vless_ws_tls;
  if (re?.enabled && ws?.enabled){
    const p1 = re.listen_port || 443;
    const p2 = ws.listen_port || 443;
    if (p1 === p2){
      throw new Error(`Port conflict: reality(${p1}) vs vless_ws_tls(${p2}). Disable one or change port.`);
    }
  }
}

function buildRealityInbound(cfg, users){
  const re = cfg.inbounds.reality;
  if(!re?.enabled) return null;

  ensure(re.server_name, 'reality.server_name required');
  ensure(re.private_key && re.short_id, 'reality.private_key/short_id required');
  const listen = re.listen_port || 443;

  // users (VLESS with XTLS-Vision flow)
  const vusers = users.filter(u=>u.enabled).map(u => ({
    uuid: u.vless_uuid, flow: 'xtls-rprx-vision'
  }));
  ensure(vusers.length>0, 'no enabled user');

  return {
    type: "vless",
    tag: "in-reality",
    listen: "::",
    listen_port: listen,
    users: vusers,
    tls: {
      enabled: true,
      server_name: re.server_name,
      reality: {
        enabled: true,
        private_key: re.private_key,
        short_id: [ re.short_id ],
        handshake: {
          server: re.server_name,
          server_port: 443
        }
      },
      alpn: ["h2","http/1.1"]
    }
  };
}

function tlsFromFilesOrAcme(tlsNode, fallbackServerName){
  // tlsNode may contain cert_path/key_path and/or acme (enabled flag)
  const hasAcme = tlsNode?.acme?.enabled;
  if (hasAcme){
    const ac = tlsNode.acme;
    const tls = {
      enabled: true,
      server_name: (ac.domain && ac.domain[0]) || fallbackServerName || undefined,
      acme: {
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
      }
    };
    return tls;
  }
  // else fall back to certificate files
  const cert = tlsNode?.certificate_path || tlsNode?.cert_path;
  const key  = tlsNode?.key_path || tlsNode?.key;
  ensure(cert && key, 'tls certificate_path/key_path (or acme.enabled=true) required');
  return {
    enabled: true,
    server_name: fallbackServerName,
    certificate_path: cert,
    key_path: key
  };
}

function buildWsInbound(cfg, users){
  const ws = cfg.inbounds.vless_ws_tls;
  if(!ws?.enabled) return null;
  ensure(ws.domain, 'vless_ws_tls.domain required');

  const vusers = users.filter(u=>u.enabled).map(u => ({ uuid: u.vless_uuid }));
  ensure(vusers.length>0, 'no enabled user');

  const tls = tlsFromFilesOrAcme(ws, ws.domain);
  const listen = ws.listen_port || 443;

  return {
    type: "vless",
    tag: "in-ws",
    listen: "::",
    listen_port: listen,
    users: vusers,
    tls,
    transport: {
      type: "ws",
      path: ws.path || "/ws",
      headers: { Host: ws.domain }
    }
  };
}

function buildHy2Inbound(cfg, users){
  const hy = cfg.inbounds.hysteria2;
  if(!hy?.enabled) return null;

  // passwords: prefer per-user hy2_pass, else global
  const pwds = users.filter(u=>u.enabled && u.hy2_pass).map(u=>({password: u.hy2_pass}));
  if (pwds.length === 0 && hy.global_password){
    pwds.push({password: hy.global_password});
  }
  ensure(pwds.length>0, 'hysteria2 enabled but no user.hy2_pass or global_password');

  // TLS
  const tlsNode = hy.tls || {};
  let tls;
  if (tlsNode.acme?.enabled){
    tls = tlsFromFilesOrAcme({acme: tlsNode.acme}, (tlsNode.acme.domain && tlsNode.acme.domain[0]) || undefined);
  } else {
    ensure(tlsNode.certificate_path && tlsNode.key_path, 'hysteria2.tls certificate_path/key_path or acme required');
    tls = {
      enabled: true,
      certificate_path: tlsNode.certificate_path,
      key_path: tlsNode.key_path
    };
  }

  const inb = {
    type: "hysteria2",
    tag: "in-hy2",
    listen: "::",
    listen_port: hy.listen_port || 8443,
    users: pwds,
    tls
  };
  

  if (Number.isFinite(hy.up_mbps)) inb.up_mbps = hy.up_mbps;
  if (Number.isFinite(hy.down_mbps)) inb.down_mbps = hy.down_mbps;

  return inb;
}

function main(){
  const cfg = yaml.load(fs.readFileSync(SBX_YML, 'utf8'));
  ensure(cfg?.users && Array.isArray(cfg.users) && cfg.users.length>0, 'no users defined');
  portConflictGuard(cfg);

  const inbounds = [];
  const re = buildRealityInbound(cfg, cfg.users); if (re) inbounds.push(re);
  const ws = buildWsInbound(cfg, cfg.users); if (ws) inbounds.push(ws);
  const hy = buildHy2Inbound(cfg, cfg.users); if (hy) inbounds.push(hy);
  ensure(inbounds.length>0, 'no inbound enabled');

  const outbounds = [
    { type: "direct", tag: "direct" },
    { type: "block", tag: "block" }
  ];

  const conf = {
    log: { level: "info" },
    inbounds,
    outbounds
  };

  fs.mkdirSync('/etc/sing-box', { recursive: true });
  fs.writeFileSync(OUT_JSON, JSON.stringify(conf, null, 2));
  console.log(`Wrote ${OUT_JSON}`);
}

try { main(); }
catch (e) {
  console.error('[gen-config] ERROR:', e.message);
  process.exit(1);
}
