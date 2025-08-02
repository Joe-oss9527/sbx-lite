import fs from 'fs';
import yaml from 'js-yaml';

const cfg = yaml.load(fs.readFileSync('/etc/sbx/sbx.yml','utf8'));

function echo(k,v){ console.log(`${k}=${v}`); }

const users = (cfg.users||[]).filter(u=>u.enabled);
echo('HOST', cfg?.export?.host||'');
echo('ENABLED_USERS', users.length);

const re = cfg?.inbounds?.reality||{};
echo('REALITY_ENABLED', !!re.enabled);
echo('REALITY_SNI', re.server_name||'');
echo('REALITY_PRIVKEY', re.private_key? 'SET':'MISSING');
echo('REALITY_SHORTID', re.short_id? 'SET':'MISSING');
echo('REALITY_PUBKEY', re.public_key? 'SET':'MISSING');

const ws = cfg?.inbounds?.vless_ws_tls||{};
echo('WS_ENABLED', !!ws.enabled);
const wsTls = ws?.acme?.enabled ? 'ACME' : ((ws.cert_path && ws.key_path)?'FILES':'MISSING');
echo('WS_TLS', wsTls);

const hy = cfg?.inbounds?.hysteria2||{};
echo('HY2_ENABLED', !!hy.enabled);
const hyTls = hy?.tls?.acme?.enabled ? 'ACME' : ((hy?.tls?.certificate_path && hy?.tls?.key_path)?'FILES':'MISSING');
echo('HY2_TLS', hyTls);
echo('HY2_UP', (hy.up_mbps??''));
echo('HY2_DOWN', (hy.down_mbps??''));

console.log('SBX_SUMMARY_JSON=' + JSON.stringify({ users: users.length, reality: re, ws, hy2: hy }));
