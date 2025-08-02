import fs from 'fs';
import path from 'path';
import express from 'express';
import basicAuth from 'basic-auth';
import bodyParser from 'body-parser';
import yaml from 'js-yaml';

const app = express();
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({extended:true}));

const STATE = {
  adminUser: 'admin',
  adminPass: process.env.SBX_ADMIN_PASS || (Math.random().toString(36).slice(2,10) + Math.random().toString(36).slice(2,10))
};

const SBX_YML = '/etc/sbx/sbx.yml';
const PANEL_ROOT = '/opt/sbx/panel';

fs.mkdirSync('/etc/sbx', {recursive:true});
if (!fs.existsSync(SBX_YML)){
  fs.writeFileSync(SBX_YML, yaml.dump({
    panel:{bind:'127.0.0.1',port:7789},
    export:{host:'YOUR_PUBLIC_HOST', name_prefix:'sbx'},
    cloudflare_mode:'proxied',
    users:[{name:'phone',enabled:true,token:'',vless_uuid:'',hy2_pass:''}],
    inbounds:{
      reality:{enabled:true,listen_port:443,server_name:'www.cloudflare.com',private_key:'',public_key:'',short_id:''},
      vless_ws_tls:{enabled:false,listen_port:443,domain:'example.com',path:'/ws',cert_path:'/etc/ssl/cf/origin.pem',key_path:'/etc/ssl/cf/origin.key',
        acme:{enabled:false,provider:'letsencrypt',email:'[email protected]',domain:['example.com'],data_directory:'/var/lib/sbx/acme',disable_http_challenge:true,disable_tls_alpn_challenge:true,
        alternative_http_port:18080,alternative_tls_port:15443,dns01_challenge:{provider:'cloudflare',api_token:''}}},
      hysteria2:{enabled:false,listen_port:8443,up_mbps:null,down_mbps:null,global_password:'',tls:{certificate_path:'/etc/ssl/fullchain.pem',key_path:'/etc/ssl/privkey.pem',
        acme:{enabled:false,provider:'letsencrypt',email:'[email protected]',domain:['hy2.example.com'],data_directory:'/var/lib/sbx/acme',disable_http_challenge:true,disable_tls_alpn_challenge:true,
        dns01_challenge:{provider:'cloudflare',api_token:''}}}}
    }
  }));
}

// Basic auth
app.use((req,res,next)=>{
  const creds = basicAuth(req);
  if (!creds || creds.name !== STATE.adminUser || creds.pass !== STATE.adminPass){
    res.set('WWW-Authenticate','Basic realm="sbx-lite"');
    return res.status(401).send('Auth required');
  }
  next();
});

function load(){ return yaml.load(fs.readFileSync(SBX_YML,'utf8')); }
function save(cfg){ fs.writeFileSync(SBX_YML, yaml.dump(cfg, {lineWidth:120})); }

// Subscription rendering helpers
function buildProxies(cfg){
  const host = cfg?.export?.host || 'YOUR_PUBLIC_HOST';
  const namePrefix = (cfg?.export?.name_prefix || 'sbx') + '-';

  const proxies = [];
  const re = cfg?.inbounds?.reality;
  if (re?.enabled){
    (cfg.users||[]).filter(u=>u.enabled).forEach(u=>{
      proxies.push({
        type:'vless', name:`${namePrefix}re-${u.name}`, server:host, port:(re.listen_port||443),
        uuid:u.vless_uuid, flow:'xtls-rprx-vision', network:'tcp', tls:true, "client-fingerprint":'chrome',
        "reality-opts":{ "public-key":re.public_key, "short-id":re.short_id, "server-name":re.server_name, "spider-x":"/" }
      });
    });
  }
  const ws = cfg?.inbounds?.vless_ws_tls;
  if (ws?.enabled){
    (cfg.users||[]).filter(u=>u.enabled).forEach(u=>{
      proxies.push({
        type:'vless', name:`${namePrefix}ws-${u.name}`, server:host, port:(ws.listen_port||443),
        uuid:u.vless_uuid, network:'ws', tls:true, sni:ws.domain, servername:ws.domain,
        "ws-opts":{ path: ws.path||'/ws', headers:{ Host: ws.domain } }
      });
    });
  }
  const hy = cfg?.inbounds?.hysteria2;
  if (hy?.enabled){
    const sni = (hy?.tls?.acme?.enabled && hy.tls.acme.domain && hy.tls.acme.domain[0]) ? hy.tls.acme.domain[0] : (cfg?.export?.host||host);
    (cfg.users||[]).filter(u=>u.enabled).forEach(u=>{
      proxies.push({ type:'hysteria2', name:`${namePrefix}hy2-${u.name}`, server:host, port:(hy.listen_port||8443),
        password: (u.hy2_pass || hy.global_password), sni, "skip-cert-verify":false, alpn:['h3'] });
    });
  }
  return proxies;
}

app.get('/sub/:token', (req,res)=>{
  const { token } = req.params;
  const format = (req.query.format || 'shadowrocket').toLowerCase();
  const cfg = load();
  const user = (cfg.users||[]).find(u=>u.token===token && u.enabled);
  if (!user) return res.status(404).send('invalid token');
  const host = req.query.host || cfg?.export?.host || 'YOUR_PUBLIC_HOST';
  const proxies = buildProxies({...cfg, export:{...cfg.export, host}});

  if (format==='singbox'){
    return res.json({ proxies });
  }

  if (format==='clash' || format==='clash_full'){
    const { proxies: ps, groups, ruleset } = buildClash(proxies, { full: format==='clash_full', tpl: (req.query.tpl||'cn'), test:(req.query.test||'auto'), region:(req.query.region||'cloudflare') });
    const doc = (format==='clash_full') ? renderClashFullYaml(ps, groups, ruleset) : renderClashYaml(ps, groups);
    return res.type('yaml').send(doc);
  }

  // shadowrocket URIs
  const lines = [];
  proxies.forEach(p=>{
    if (p.type==='vless' && p.network==='tcp'){ // REALITY
      const q = new URLSearchParams({ security:'reality', pbk: p["reality-opts"]["public-key"]||'', sid: p["reality-opts"]["short-id"]||'', sni: p["reality-opts"]["server-name"]||'', flow:'xtls-rprx-vision', fp:'chrome' }).toString();
      lines.push(`vless://${user.vless_uuid}@${host}:${p.port}?${q}#${encodeURIComponent(p.name)}`);
    } else if (p.type==='vless' && p.network==='ws'){
      const q = new URLSearchParams({ type:'ws', path: p["ws-opts"].path, security:'tls', sni:p.sni, host:p.servername, encryption:'none' }).toString();
      lines.push(`vless://${user.vless_uuid}@${host}:${p.port}?${q}#${encodeURIComponent(p.name)}`);
    } else if (p.type==='hysteria2'){
      const q = new URLSearchParams({ sni: p.sni, insecure:'0' }).toString();
      lines.push(`hy2://${encodeURIComponent(p.password)}@${host}:${p.port}?${q}#${encodeURIComponent(p.name)}`);
    }
  });
  res.type('text/plain').send(lines.join('\n'));
});

function toClashProxies(internal){
  return internal.map(p=>{
    if (p.type==='vless' && p.network==='tcp'){ // Reality
      return {
        name:p.name, type:'vless', server:p.server, port:p.port, uuid:p.uuid, tls:true,
        flow:'xtls-rprx-vision', 'client-fingerprint':'chrome',
        'reality-opts': { 'public-key': p["reality-opts"]["public-key"], 'short-id': p["reality-opts"]["short-id"], 'spider-x':'/', 'server-name': p["reality-opts"]["server-name"] }
      };
    }
    if (p.type==='vless' && p.network==='ws'){
      return {
        name:p.name, type:'vless', server:p.server, port:p.port, uuid:p.uuid, tls:true, network:'ws',
        sni:p.sni, servername:p.servername, 'ws-opts': { path:p["ws-opts"].path, headers: { Host: p["ws-opts"].headers.Host } }
      };
    }
    if (p.type==='hysteria2'){
      return { name:p.name, type:'hysteria2', server:p.server, port:p.port, password:p.password, sni:p.sni, 'skip-cert-verify':false, alpn:['h3'] };
    }
    return p;
  });
}

function buildClash(proxies, {full, tpl, test, region}){
  const cproxies = toClashProxies(proxies);
  const groups = [
    { name:'🔀 Select', type:'select', proxies: cproxies.map(x=>x.name) },
    { name:'🟢 Auto', type:'url-test', interval:180, tolerance:50, url: autoTestURL(test, region), proxies: cproxies.map(x=>x.name) }
  ];
  const ruleset = full ? defaultRuleProvidersAndRules(tpl) : null;
  return { proxies:cproxies, groups, ruleset };
}

function autoTestURL(test, region){
  if (test && test!=='auto') return test;
  const map = { cn:'http://connect.rom.miui.com/generate_204', cloudflare:'https://cp.cloudflare.com/generate_204', global:'https://www.gstatic.com/generate_204' };
  return map[region] || map.cloudflare;
}

function renderClashYaml(proxies, groups){
  return yaml.dump({ proxies, 'proxy-groups': groups }, { lineWidth: 140 });
}

function defaultRuleProvidersAndRules(tpl){
  const providers = {
    'geosite-cn': { type:'http', behavior:'domain', url:'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/geosite/cn.txt', path:'./providers/geosite-cn.txt', interval:86400 },
    'geosite-!cn': { type:'http', behavior:'domain', url:'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/geosite/geolocation-!cn.txt', path:'./providers/geosite-!cn.txt', interval:86400 },
    'geoip-cn': { type:'http', behavior:'ipcidr', url:'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/geoip/cn.txt', path:'./providers/geoip-cn.txt', interval:86400 },
    'ads': { type:'http', behavior:'domain', url:'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt', path:'./providers/ads.txt', interval:86400 }
  };
  const rules = ['RULE-SET,ads,REJECT','RULE-SET,geosite-cn,DIRECT','RULE-SET,geosite-!cn,🔀 Select','GEOIP,CN,DIRECT','MATCH,🔀 Select'];
  return { providers, rules };
}

function renderClashFullYaml(proxies, groups, ruleset){
  const obj = {
    port: 7890, 'socks-port': 7891, 'allow-lan': false, mode: 'Rule', 'log-level':'info',
    dns: { enable:true, listen:'127.0.0.1:1053', 'enhanced-mode':'fake-ip', nameserver:['223.5.5.5','119.29.29.29'], fallback:['https://1.1.1.1/dns-query','https://dns.google/dns-query'] },
    proxies, 'proxy-groups': groups, 'rule-providers': ruleset.providers, rules: ruleset.rules
  };
  return yaml.dump(obj, { lineWidth: 140 });
}

// Apply
app.post('/api/apply', (req,res)=>{
  try{
    const gen = path.join(PANEL_ROOT,'gen-config.js');
    require('child_process').execSync('node '+gen, {stdio:'inherit'});
    require('child_process').execSync('sing-box check -c /etc/sing-box/config.json', {stdio:'inherit'});
    require('child_process').execSync('systemctl restart sing-box', {stdio:'inherit'});
    res.json({ok:true});
  }catch(e){ res.status(500).json({ok:false, error:e.message}); }
});

app.get('/', (req,res)=> res.type('text/plain').send(`sbx-lite panel\nuser: ${STATE.adminUser}\npass: ${STATE.adminPass}\n`));

const cfg = yaml.load(fs.readFileSync(SBX_YML,'utf8'));
const bind = cfg?.panel?.bind || '127.0.0.1';
const port = cfg?.panel?.port || 7789;
app.listen(port, bind, ()=> console.log(`panel on http://${bind}:${port}`));
