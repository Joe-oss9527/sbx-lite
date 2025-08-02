import fs from 'fs';
import yaml from 'js-yaml';

const SBX_YML = '/etc/sbx/sbx.yml';

function load(){ return yaml.load(fs.readFileSync(SBX_YML,'utf8')); }

function echoKV(k,v){ console.log(`${k}=${v}`); }

function main(){
  const cfg = load();

  // export
  echoKV('HOST', cfg?.export?.host||'');

  // users
  const users = (cfg?.users||[]).filter(u=>u.enabled);
  echoKV('ENABLED_USERS', users.length);

  // reality
  const re = cfg?.inbounds?.reality||{};
  echoKV('REALITY_ENABLED', !!re.enabled);
  echoKV('REALITY_SNI', re.server_name||'');
  echoKV('REALITY_PRIVKEY', re.private_key? 'SET':'MISSING');
  echoKV('REALITY_SHORTID', re.short_id? 'SET':'MISSING');
  echoKV('REALITY_PUBKEY', re.public_key? 'SET':'MISSING');

  // ws
  const ws = cfg?.inbounds?.vless_ws_tls||{};
  echoKV('WS_ENABLED', !!ws.enabled);
  echoKV('WS_DOMAIN', ws.domain||'');
  const wsAcme = ws?.acme?.enabled ? 'ACME' : ((ws.cert_path && ws.key_path)?'FILES':'MISSING');
  echoKV('WS_TLS', wsAcme);

  // hy2
  const hy = cfg?.inbounds?.hysteria2||{};
  echoKV('HY2_ENABLED', !!hy.enabled);
  const tls = hy?.tls||{};
  const hyAcme = tls?.acme?.enabled ? 'ACME' : ((tls.certificate_path && tls.key_path)?'FILES':'MISSING');
  echoKV('HY2_TLS', hyAcme);
  echoKV('HY2_UP', (hy.up_mbps??'') );
  echoKV('HY2_DOWN', (hy.down_mbps??'') );

  // quick JSON summary
  console.log('SBX_SUMMARY_JSON=' + JSON.stringify({ users: users.length, reality: re, ws, hy2: hy }));
}

main();
