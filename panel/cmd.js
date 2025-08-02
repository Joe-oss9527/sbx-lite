import fs from 'fs';
import yaml from 'js-yaml';
import { v4 as uuidv4 } from 'uuid';
import child_process from 'child_process';
import crypto from 'crypto';

const SBX_YML = '/etc/sbx/sbx.yml';

function load(){ return yaml.load(fs.readFileSync(SBX_YML,'utf8')); }
function save(obj){ fs.writeFileSync(SBX_YML, yaml.dump(obj, {lineWidth:120})); }

function sh(cmd){
  return child_process.execSync(cmd, {encoding:'utf8'}).trim();
}

function realityGenOnce(){
  const out = sh('sing-box generate reality-keypair');
  const priv = (out.match(/PrivateKey\\s*:\\s*(\\S+)/)||[])[1] || '';
  const pub  = (out.match(/PublicKey\\s*:\\s*(\\S+)/)||[])[1] || '';
  return { private_key: priv, public_key: pub };
}

const actions = {
  enable(proto){
    const cfg = load();
    if (proto==='vless_ws_tls' && cfg?.inbounds?.reality?.enabled && (cfg.inbounds.reality.listen_port||443) === (cfg.inbounds.vless_ws_tls.listen_port||443)){
      throw new Error('Port conflict: reality and ws share same port. Change one or disable.');
    }
    cfg.inbounds[proto].enabled = true;
    save(cfg); console.log(`enabled ${proto}`);
  },
  disable(proto){ const cfg = load(); cfg.inbounds[proto].enabled = false; save(cfg); console.log(`disabled ${proto}`); },
  sethost(host){ const cfg = load(); cfg.export = cfg.export||{}; cfg.export.host = host; save(cfg); console.log(`host=${host}`); },
  autodetect_host(){
    try { const ip = sh("curl -fsS https://api.ipify.org"); actions.sethost(ip); }
    catch(e){ console.error("detect host failed:", e.message); process.exit(1); }
  },
  cf(mode){
    const cfg = load(); cfg.cloudflare_mode = mode;
    cfg.inbounds.vless_ws_tls = cfg.inbounds.vless_ws_tls || {};
    if (mode==='proxied'){ cfg.inbounds.vless_ws_tls.cert_path="/etc/ssl/cf/origin.pem"; cfg.inbounds.vless_ws_tls.key_path="/etc/ssl/cf/origin.key"; }
    else { cfg.inbounds.vless_ws_tls.cert_path="/etc/ssl/fullchain.pem"; cfg.inbounds.vless_ws_tls.key_path="/etc/ssl/privkey.pem"; }
    save(cfg); console.log(`cloudflare_mode=${mode}`);
  },
  setdomain(domain){ const cfg = load(); cfg.inbounds.vless_ws_tls = cfg.inbounds.vless_ws_tls||{}; cfg.inbounds.vless_ws_tls.domain=domain; save(cfg); console.log(`ws.domain=${domain}`); },
  user_add(name){
    const cfg = load(); cfg.users = cfg.users||[];
    const token = crypto.randomBytes(12).toString('base64url');
    const vless_uuid = uuidv4(); const hy2_pass = crypto.randomBytes(16).toString('base64url');
    cfg.users.push({ name, enabled:true, token, vless_uuid, hy2_pass });
    save(cfg); console.log(JSON.stringify({name, token, vless_uuid, hy2_pass},null,2));
  },
  user_rm(name){ const cfg = load(); cfg.users = (cfg.users||[]).filter(u=>u.name!==name); save(cfg); console.log(`removed ${name}`); },
  user_enable(name,on=true){ const cfg = load(); const u=(cfg.users||[]).find(u=>u.name===name); if(!u) throw new Error('no such user'); u.enabled=!!on; save(cfg); console.log(`${on?'enabled':'disabled'} ${name}`); },
  user_rotate(name){ const cfg = load(); const u=(cfg.users||[]).find(u=>u.name===name); if(!u) throw new Error('no such user'); u.token=crypto.randomBytes(12).toString('base64url'); save(cfg); console.log(JSON.stringify({name, token:u.token},null,2)); },
  reality_keys(){
    const cfg = load(); cfg.inbounds.reality = cfg.inbounds.reality||{};
    if(!cfg.inbounds.reality.private_key || !cfg.inbounds.reality.public_key){
      const kp = realityGenOnce(); cfg.inbounds.reality.private_key=kp.private_key; cfg.inbounds.reality.public_key=kp.public_key; save(cfg);
    }
    console.log('reality keys ensured');
  }
};

const [,, cmd, arg1] = process.argv;
try{
  if (cmd==='enable') actions.enable(arg1);
  else if (cmd==='disable') actions.disable(arg1);
  else if (cmd==='sethost') actions.sethost(arg1);
  else if (cmd==='autodetect_host') actions.autodetect_host();
  else if (cmd==='cf') actions.cf(arg1);
  else if (cmd==='setdomain') actions.setdomain(arg1);
  else if (cmd==='user-add') actions.user_add(arg1);
  else if (cmd==='user-rm') actions.user_rm(arg1);
  else if (cmd==='user-enable') actions.user_enable(arg1,true);
  else if (cmd==='user-disable') actions.user_enable(arg1,false);
  else if (cmd==='user-rotate') actions.user_rotate(arg1);
  else if (cmd==='reality-keys') actions.reality_keys();
  else {
    console.log(`Usage:
  node cmd.js enable <reality|vless_ws_tls|hysteria2>
  node cmd.js disable <reality|vless_ws_tls|hysteria2>
  node cmd.js sethost <host> | autodetect_host
  node cmd.js cf <proxied|direct>
  node cmd.js setdomain <domain>
  node cmd.js user-add <name> | user-rm <name> | user-enable <name> | user-disable <name> | user-rotate <name>
  node cmd.js reality-keys
`);
  }
} catch (e){ console.error('[cmd] ERROR:', e.message); process.exit(1); }
