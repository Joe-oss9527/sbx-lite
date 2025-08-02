const fs = require('fs');
const yaml = require('js-yaml');
const { execSync } = require('child_process');

const SBX_YAML = '/etc/sbx/sbx.yml';

function load() { return yaml.load(fs.readFileSync(SBX_YAML, 'utf8')); }
function save(doc){ fs.writeFileSync(SBX_YAML, yaml.dump(doc), 'utf8'); }

function genUUID(){ return execSync('sing-box generate uuid').toString().trim(); }
function rand(n){ return require('crypto').randomBytes(n).toString('base64url'); }

function enable(doc, key, on) {
  doc.inbounds = doc.inbounds || {};
  const map = { reality:'reality', ws:'vless_ws_tls', hy2:'hysteria2' };
  const k = map[key];
  if (!k) throw new Error('unknown inbound key');
  doc.inbounds[k] = doc.inbounds[k] || {};
  doc.inbounds[k].enabled = !!on;
  return doc;
}

function cfmode(doc, mode) {
  if (!['proxied','direct'].includes(mode)) throw new Error('mode must be proxied|direct');
  doc.cloudflare_mode = mode;
  // also adjust default cert paths for ws tls
  doc.inbounds = doc.inbounds || {};
  doc.inbounds.vless_ws_tls = doc.inbounds.vless_ws_tls || {};
  if (mode === 'proxied') {
    doc.inbounds.vless_ws_tls.cert_path = '/etc/ssl/cf/origin.pem';
    doc.inbounds.vless_ws_tls.key_path = '/etc/ssl/cf/origin.key';
  } else {
    doc.inbounds.vless_ws_tls.cert_path = '/etc/ssl/fullchain.pem';
    doc.inbounds.vless_ws_tls.key_path = '/etc/ssl/privkey.pem';
  }
  return doc;
}

function sethost(doc, host) {
  doc.export = doc.export || {};
  doc.export.host = host;
  return doc;
}

function setdomain(doc, domain) {
  doc.inbounds = doc.inbounds || {};
  doc.inbounds.vless_ws_tls = doc.inbounds.vless_ws_tls || {};
  doc.inbounds.vless_ws_tls.domain = domain;
  return doc;
}

function adduser(doc, name) {
  doc.users = doc.users || [];
  const u = {
    name,
    enabled: true,
    token: rand(18),
    vless_uuid: genUUID(),
    hy2_pass: rand(14)
  };
  doc.users.push(u);
  return { doc, u };
}

function rmuser(doc, name) {
  doc.users = (doc.users || []).filter(u => u.name !== name);
  return doc;
}

function main() {
  const [,, cmd, arg1, arg2] = process.argv;
  if (!cmd) throw new Error('usage: node cmd.js <enable|disable|cf|sethost|setdomain|adduser|rmuser> ...');
  let doc = load();
  switch(cmd){
    case 'user-rotate': {
      const doc = load();
      const name = (arg1 || 'user').toString();
      if (!/^[a-zA-Z0-9._-]{1,32}$/.test(name)) throw new Error('bad user name');
      const users = doc.users || [];
      const idx = users.findIndex(u => u && u.name === name);
      if (idx < 0) throw new Error('user not found');
      users[idx].token = rand(18);
      save(doc);
      console.log(JSON.stringify({name, token: users[idx].token}, null, 2));
      break;
    }
    case 'user-enable': {
      const doc = load();
      const name = (arg1 || 'user').toString();
      const en = String(arg2||'true') !== 'false';
      if (!/^[a-zA-Z0-9._-]{1,32}$/.test(name)) throw new Error('bad user name');
      const users = doc.users || [];
      const idx = users.findIndex(u => u && u.name === name);
      if (idx < 0) throw new Error('user not found');
      users[idx].enabled = en;
      save(doc);
      console.log(JSON.stringify({name, enabled: en}, null, 2));
      break;
    }
    case 'enable': doc = enable(doc, arg1, true); break;
    case 'disable': doc = enable(doc, arg1, false); break;
    case 'cf': doc = cfmode(doc, arg1); break;
    case 'sethost': doc = sethost(doc, arg1); break;
    case 'setdomain': doc = setdomain(doc, arg1); break;
    case 'adduser': {
      const r = adduser(doc, arg1 || 'user');
      doc = r.doc; console.log(JSON.stringify(r.u, null, 2));
      break;
    }
    case 'rmuser': doc = rmuser(doc, arg1); break;
    default: throw new Error('unknown command');
  }
  save(doc);
}

main();
