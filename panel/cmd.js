import fs from 'fs';
import yaml from 'js-yaml';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import child_process from 'child_process';

const SBX_YML = '/etc/sbx/sbx.yml';

function load(){ return yaml.load(fs.readFileSync(SBX_YML,'utf8')); }
function save(obj){ fs.writeFileSync(SBX_YML, yaml.dump(obj, {lineWidth:120})); }

function exec(cmd){
  return child_process.execSync(cmd, {encoding:'utf8'}).trim();
}

function realityGen(){
  const priv = exec('sing-box generate reality-keypair | grep PrivateKey | awk \'{print $2}\'');
  const pub  = exec('sing-box generate reality-keypair | grep PublicKey | awk \'{print $2}\'');
  // call twice is wasteful; better to run once and parse both; keeping simple here
  return { private_key: priv, public_key: pub };
}

const actions = {
  enable(proto){
    const cfg = load();
    cfg.inbounds[proto].enabled = true;
    save(cfg);
    console.log(`enabled ${proto}`);
  },
  disable(proto){
    const cfg = load();
    cfg.inbounds[proto].enabled = false;
    save(cfg);
    console.log(`disabled ${proto}`);
  },
  sethost(host){
    const cfg = load();
    cfg.export = cfg.export || {};
    cfg.export.host = host;
    save(cfg);
    console.log(`host set to ${host}`);
  },
  autodetect_host(){
    // best-effort
    try {
      const ip = exec("curl -fsS https://api.ipify.org");
      actions.sethost(ip);
    } catch(e){
      console.error("detect host failed:", e.message);
      process.exit(1);
    }
  },
  cf(mode){
    const cfg = load();
    cfg.cloudflare_mode = mode;
    // adjust default cert paths for ws
    if (!cfg.inbounds.vless_ws_tls) cfg.inbounds.vless_ws_tls = {};
    if (mode === 'proxied'){
      cfg.inbounds.vless_ws_tls.cert_path = "/etc/ssl/cf/origin.pem";
      cfg.inbounds.vless_ws_tls.key_path  = "/etc/ssl/cf/origin.key";
    } else {
      cfg.inbounds.vless_ws_tls.cert_path = "/etc/ssl/fullchain.pem";
      cfg.inbounds.vless_ws_tls.key_path  = "/etc/ssl/privkey.pem";
    }
    save(cfg);
    console.log(`cloudflare_mode=${mode}`);
  },
  setdomain(domain){
    const cfg = load();
    cfg.inbounds.vless_ws_tls = cfg.inbounds.vless_ws_tls || {};
    cfg.inbounds.vless_ws_tls.domain = domain;
    save(cfg);
    console.log(`ws.domain=${domain}`);
  },
  user_add(name){
    const cfg = load();
    cfg.users = cfg.users || [];
    const token = crypto.randomBytes(12).toString('base64url');
    const vless_uuid = uuidv4();
    const hy2_pass = crypto.randomBytes(16).toString('base64url');
    cfg.users.push({ name, enabled: true, token, vless_uuid, hy2_pass });
    save(cfg);
    console.log(JSON.stringify({name, token, vless_uuid, hy2_pass}, null, 2));
  },
  user_rm(name){
    const cfg = load();
    cfg.users = (cfg.users || []).filter(u => u.name !== name);
    save(cfg);
    console.log(`removed ${name}`);
  },
  user_enable(name, on=true){
    const cfg = load();
    const u = (cfg.users||[]).find(u=>u.name===name);
    if (!u) { console.error('no such user'); process.exit(1); }
    u.enabled = !!on;
    save(cfg);
    console.log(`${on?'enabled':'disabled'} ${name}`);
  },
  user_rotate(name){
    const cfg = load();
    const u = (cfg.users||[]).find(u=>u.name===name);
    if (!u) { console.error('no such user'); process.exit(1); }
    u.token = crypto.randomBytes(12).toString('base64url');
    save(cfg);
    console.log(JSON.stringify({name, token: u.token}, null, 2));
  },
  reality_keys(){
    const cfg = load();
    if (!cfg.inbounds.reality) cfg.inbounds.reality = {};
    if (!cfg.inbounds.reality.private_key || !cfg.inbounds.reality.public_key){
      const kp = realityGen();
      cfg.inbounds.reality.private_key = kp.private_key;
      cfg.inbounds.reality.public_key  = kp.public_key;
      save(cfg);
    }
    console.log('reality keys ensured');
  }
};

// CLI
const [,, cmd, arg1, arg2] = process.argv;
if (!cmd) {
  console.log(`Usage:
  node cmd.js enable <reality|vless_ws_tls|hysteria2>
  node cmd.js disable <reality|vless_ws_tls|hysteria2>
  node cmd.js sethost <host> | autodetect_host
  node cmd.js cf <proxied|direct>
  node cmd.js setdomain <domain>
  node cmd.js user-add <name> | user-rm <name> | user-enable <name> | user-disable <name> | user-rotate <name>
  node cmd.js reality-keys
`);
  process.exit(0);
}

try{
  if (cmd==='enable' || cmd==='disable'){
    actions[cmd](arg1);
  } else if (cmd==='sethost'){
    actions.sethost(arg1);
  } else if (cmd==='autodetect_host'){
    actions.autodetect_host();
  } else if (cmd==='cf'){
    actions.cf(arg1);
  } else if (cmd==='setdomain'){
    actions.setdomain(arg1);
  } else if (cmd==='user-add'){
    actions.user_add(arg1);
  } else if (cmd==='user-rm'){
    actions.user_rm(arg1);
  } else if (cmd==='user-enable'){
    actions.user_enable(arg1, true);
  } else if (cmd==='user-disable'){
    actions.user_enable(arg1, false);
  } else if (cmd==='user-rotate'){
    actions.user_rotate(arg1);
  } else if (cmd==='reality-keys'){
    actions.reality_keys();
  } else {
    throw new Error('unknown command');
  }
} catch (e){
  console.error('[cmd] ERROR:', e.message);
  process.exit(1);
}
