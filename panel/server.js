const fs = require('fs');
const path = require('path');
const express = require('express');
const bodyParser = require('body-parser');
const yaml = require('js-yaml');
const basicAuth = require('basic-auth');
const { exec } = require('child_process');

function safeError(res, e, msg='Internal error') { console.error('[panel]', e); return res.status(500).json({ error: msg }); }
const crypto = require('crypto');

const SBX_BIND = process.env.SBX_BIND || '127.0.0.1';
const SBX_PORT = parseInt(process.env.SBX_PORT || '7789', 10);
const ADMIN_PASS_FILE = '/etc/sbx/panel.env';
const SBX_YAML = '/etc/sbx/sbx.yml';
const SBX_JSON = '/etc/sing-box/config.json';

function getAdminPass() {
  try {
    const data = fs.readFileSync(ADMIN_PASS_FILE, 'utf8');
    const line = data.split('\n').find(l => l.startsWith('ADMIN_PASS='));
    return line ? line.replace('ADMIN_PASS=', '').trim() : null;
  } catch { return null; }
}

const ADMIN_PASS = getAdminPass();

const app = express();
app.use(bodyParser.json({limit: '2mb'}));
app.use(express.static(path.join(__dirname, 'public')));

// Basic auth middleware
function auth(req, res, next) {
  const creds = basicAuth(req);
  if (!ADMIN_PASS) return res.status(500).send('Admin password not set');
  if (!creds || creds.name !== 'admin' || creds.pass !== ADMIN_PASS) {
    res.set('WWW-Authenticate', 'Basic realm="sbx-lite"');
    return res.status(401).send('Authentication required.');
  }
  next();
}

// Public route: subscription
app.get('/sub/:token', (req, res) => {
  try {
    const format = (req.query.format || 'shadowrocket').toString().toLowerCase();
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const user = (doc.users || []).find(u => u && u.enabled && u.token === req.params.token);
    if (!user) return res.status(404).send('user not found');

    const host = (doc.export && doc.export.host) || req.query.host;
    if (!host) return res.status(400).send('export.host not set; provide ?host=example.com');

    const lines = [];
    const namePrefix = (doc.export && doc.export.name_prefix) || 'sbx';

    // REALITY link
    if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
      const r = doc.inbounds.reality;
      const port = r.listen_port || 443;
      const sni = r.server_name;
      const pbk = r.public_key || '';
      const sid = r.short_id;
      // vless URI for REALITY
      // flow param is not widely standardized in URI; some clients support it as 'flow'
      const uri = `vless://${user.vless_uuid}@${host}:${port}`
        + `?type=tcp&security=reality&encryption=none&alpn=h2%2Chttp%2F1.1&fp=chrome`
        + `&sni=${encodeURIComponent(sni)}&pbk=${encodeURIComponent(pbk)}&sid=${encodeURIComponent(sid)}`
        + `#${encodeURIComponent(namePrefix + '-REALITY-' + user.name)}`;
      lines.push(uri);
    }

    // WS-TLS link
    if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
      const w = doc.inbounds.vless_ws_tls;
      const port = w.listen_port || 443;
      const domain = w.domain;
      const pathWs = w.path || '/ws';
      const uri = `vless://${user.vless_uuid}@${domain}:${port}`
        + `?type=ws&path=${encodeURIComponent(pathWs)}&security=tls&encryption=none&sni=${encodeURIComponent(domain)}&host=${encodeURIComponent(domain)}`
        + `#${encodeURIComponent(namePrefix + '-WS-' + user.name)}`;
      lines.push(uri);
    }

    // Hysteria2 link (URI conventions vary by client; we use hy2://PASSWORD@host:port?insecure=0&sni=...)
    if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
      const h = doc.inbounds.hysteria2;
      const port = h.listen_port || 8443;
      const pass = user.hy2_pass || h.global_password;
      if (!pass) return res.status(400).send('hy2 password missing');
      const sni = host; // you may set a specific hy2 sni in doc.export later
      const uri = `hy2://${encodeURIComponent(pass)}@${host}:${port}?sni=${encodeURIComponent(sni)}&insecure=0`
        + `#${encodeURIComponent(namePrefix + '-HY2-' + user.name)}`;
      lines.push(uri);
    }

    if (format === 'shadowrocket' || format === 'uri') {
      res.type('text/plain').send(lines.join('\n'));
      return;
    }

    if (format === 'clash_full') {
      const tpl = (req.query.tpl || 'balanced').toString();
      // Full Mihomo/Clash Meta config: proxies + proxy-groups + rule-providers + rules
      const proxies = [];
      const names = [];
      // REALITY
      if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
        const r = doc.inbounds.reality;
        const name = `${namePrefix}-REALITY-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: host,
          port: r.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          flow: 'xtls-rprx-vision',
          network: 'tcp',
          'client-fingerprint': 'chrome',
          'reality-opts': {
            'public-key': r.public_key || '',
            'short-id': r.short_id
          },
          servername: r.server_name
        });
        names.push(name);
      }
      // WS-TLS
      if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
        const w = doc.inbounds.vless_ws_tls;
        const name = `${namePrefix}-WS-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: w.domain,
          port: w.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          servername: w.domain,
          network: 'ws',
          'ws-opts': {
            path: w.path || '/ws',
            headers: { Host: w.domain }
          }
        });
        names.push(name);
      }
      // Hysteria2
      if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
        const h = doc.inbounds.hysteria2;
        const pass = user.hy2_pass || h.global_password;
        const name = `${namePrefix}-HY2-${user.name}`;
        proxies.push({
          name,
          type: 'hysteria2',
          server: host,
          port: h.listen_port || 8443,
          password: pass,
          sni: host,
          'skip-cert-verify': false,
          alpn: ['h3'],
          udp: true
        });
        names.push(name);
      }

      // Groups
      const groups = [];
      if (names.length > 0) {
        groups.push({
        name: '🟢 Auto',
        type: 'url-test',
        proxies: names,
        url: computeTestUrl(req),
          interval: 300,
          tolerance: 50,
          lazy: true
        });
        groups.push({
          name: '🔀 Select',
          type: 'select',
          proxies: ['🟢 Auto', ...names, 'DIRECT']
        });
      }

      // Rule providers (popular open-source lists; users may replace with private mirrors)
      const providers = {
        reject: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt',
          path: './providers/reject.txt', interval: 86400
        },
        direct: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt',
          path: './providers/direct.txt', interval: 86400
        },
        proxy: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt',
          path: './providers/proxy.txt', interval: 86400
        },
        private: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt',
          path: './providers/private.txt', interval: 86400
        },
        'tld-not-cn': {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt',
          path: './providers/tld-not-cn.txt', interval: 86400
        },
        applications: {
          type: 'http', behavior: 'classical',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt',
          path: './providers/applications.yaml', interval: 86400
        }
      };

      // Rules (order matters) - selectable templates
      let rules;
      if (tpl === 'global') {
        // Global proxy: most traffic goes to proxy, CN stays DIRECT
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else if (tpl === 'cn') {
        // Mainland-first: prefer DIRECT for China; proxy for tld-not-cn & proxy sets
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else {
        // balanced (default): same as cn
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      }

      const cfg = {
        port: 7890,
        'socks-port': 7891,
        'allow-lan': false,
        mode: 'Rule',
        'log-level': 'info',
        dns: {
          enable: true,
          listen: '0.0.0.0:1053',
          ipv6: false,
          'enhanced-mode': 'fake-ip',
          'fake-ip-range': '198.18.0.1/16',
          'fake-ip-filter': [
            '*.lan', 'localhost', '+.local', 'time.*.com', 'time.*.gov',
            'ntp.*.com', 'ntp.*.cn', 'pool.ntp.org', 'connect.rom.miui.com'
          ],
          'default-nameserver': ['119.29.29.29', '223.5.5.5'],
          nameserver: ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
          fallback: ['tls://1.1.1.1:853', 'tls://8.8.8.8:853'],
          'proxy-server-nameserver': ['https://cloudflare-dns.com/dns-query'],
          'nameserver-policy': {
            'geosite:cn': ['119.29.29.29', '223.5.5.5'],
            'geosite:geolocation-!cn': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query']
          },
          'fallback-filter': {
            'geoip': true,
            'geoip-code': 'CN',
            'domain': ['+.google.com', '+.facebook.com', '+.github.com', '+.githubusercontent.com']
          }
        },
        proxies,
        'proxy-groups': groups,
        'rule-providers': providers,
        rules
      };
      const y = yaml.dump(cfg);
      res.type('text/yaml').send(y);
      return;
    }
        
    if (format === 'singbox' || format === 'json') {
      // Build proper sing-box outbounds
      const outbounds = [];
      // REALITY
      if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
        const r = doc.inbounds.reality;
        outbounds.push({
          type: 'vless',
          tag: `${namePrefix}-REALITY-${user.name}`,
          server: host,
          server_port: r.listen_port || 443,
          uuid: user.vless_uuid,
          flow: 'xtls-rprx-vision',
          tls: {
            enabled: true,
            server_name: r.server_name,
            reality: {
              enabled: true,
              public_key: r.public_key || '',
              short_id: r.short_id
            },
            alpn: ['h2','http/1.1']
          }
        });
      }
      // WS-TLS
      if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
        const w = doc.inbounds.vless_ws_tls;
        outbounds.push({
          type: 'vless',
          tag: `${namePrefix}-WS-${user.name}`,
          server: w.domain,
          server_port: w.listen_port || 443,
          uuid: user.vless_uuid,
          tls: { enabled: true, server_name: w.domain },
          transport: { type: 'ws', path: w.path || '/ws', headers: { Host: w.domain } }
        });
      }
      // Hysteria2
      if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
        const h = doc.inbounds.hysteria2;
        const pass = user.hy2_pass || h.global_password;
        outbounds.push({
          type: 'hysteria2',
          tag: `${namePrefix}-HY2-${user.name}`,
          server: host,
          server_port: h.listen_port || 8443,
          password: pass,
          tls: { enabled: true, server_name: host, insecure: false }
        });
      }
      res.json({ version: 1, outbounds });
      return;
    }

    if (format === 'clash_full') {
      const tpl = (req.query.tpl || 'balanced').toString();
      // Full Mihomo/Clash Meta config: proxies + proxy-groups + rule-providers + rules
      const proxies = [];
      const names = [];
      // REALITY
      if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
        const r = doc.inbounds.reality;
        const name = `${namePrefix}-REALITY-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: host,
          port: r.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          flow: 'xtls-rprx-vision',
          network: 'tcp',
          'client-fingerprint': 'chrome',
          'reality-opts': {
            'public-key': r.public_key || '',
            'short-id': r.short_id
          },
          servername: r.server_name
        });
        names.push(name);
      }
      // WS-TLS
      if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
        const w = doc.inbounds.vless_ws_tls;
        const name = `${namePrefix}-WS-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: w.domain,
          port: w.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          servername: w.domain,
          network: 'ws',
          'ws-opts': {
            path: w.path || '/ws',
            headers: { Host: w.domain }
          }
        });
        names.push(name);
      }
      // Hysteria2
      if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
        const h = doc.inbounds.hysteria2;
        const pass = user.hy2_pass || h.global_password;
        const name = `${namePrefix}-HY2-${user.name}`;
        proxies.push({
          name,
          type: 'hysteria2',
          server: host,
          port: h.listen_port || 8443,
          password: pass,
          sni: host,
          'skip-cert-verify': false,
          alpn: ['h3'],
          udp: true
        });
        names.push(name);
      }

      // Groups
      const groups = [];
      if (names.length > 0) {
        groups.push({
          name: '🟢 Auto',
          type: 'url-test',
          proxies: names,
          url: 'https://www.gstatic.com/generate_204',
          interval: 300,
          tolerance: 50,
          lazy: true
        });
        groups.push({
          name: '🔀 Select',
          type: 'select',
          proxies: ['🟢 Auto', ...names, 'DIRECT']
        });
      }

      // Rule providers (popular open-source lists; users may replace with private mirrors)
      const providers = {
        reject: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt',
          path: './providers/reject.txt', interval: 86400
        },
        direct: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt',
          path: './providers/direct.txt', interval: 86400
        },
        proxy: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt',
          path: './providers/proxy.txt', interval: 86400
        },
        private: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt',
          path: './providers/private.txt', interval: 86400
        },
        'tld-not-cn': {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt',
          path: './providers/tld-not-cn.txt', interval: 86400
        },
        applications: {
          type: 'http', behavior: 'classical',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt',
          path: './providers/applications.yaml', interval: 86400
        }
      };

      // Rules (order matters) - selectable templates
      let rules;
      if (tpl === 'global') {
        // Global proxy: most traffic goes to proxy, CN stays DIRECT
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else if (tpl === 'cn') {
        // Mainland-first: prefer DIRECT for China; proxy for tld-not-cn & proxy sets
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else {
        // balanced (default): same as cn
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      }

      const cfg = {
        port: 7890,
        'socks-port': 7891,
        'allow-lan': false,
        mode: 'Rule',
        'log-level': 'info',
        dns: {
          enable: true,
          listen: '0.0.0.0:1053',
          ipv6: false,
          'enhanced-mode': 'fake-ip',
          'fake-ip-range': '198.18.0.1/16',
          'fake-ip-filter': [
            '*.lan', 'localhost', '+.local', 'time.*.com', 'time.*.gov',
            'ntp.*.com', 'ntp.*.cn', 'pool.ntp.org', 'connect.rom.miui.com'
          ],
          'default-nameserver': ['119.29.29.29', '223.5.5.5'],
          nameserver: ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
          fallback: ['tls://1.1.1.1:853', 'tls://8.8.8.8:853'],
          'proxy-server-nameserver': ['https://cloudflare-dns.com/dns-query'],
          'nameserver-policy': {
            'geosite:cn': ['119.29.29.29', '223.5.5.5'],
            'geosite:geolocation-!cn': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query']
          },
          'fallback-filter': {
            'geoip': true,
            'geoip-code': 'CN',
            'domain': ['+.google.com', '+.facebook.com', '+.github.com', '+.githubusercontent.com']
          }
        },
        proxies,
        'proxy-groups': groups,
        'rule-providers': providers,
        rules
      };
      const y = yaml.dump(cfg);
      res.type('text/yaml').send(y);
      return;
    }
        
    if (format === 'clash' || format === 'yaml') {
      // Build Clash Meta-compatible proxies and proxy-groups
      const proxies = [];
      const names = [];
      // REALITY
      if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
        const r = doc.inbounds.reality;
        const name = `${namePrefix}-REALITY-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: host,
          port: r.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          flow: 'xtls-rprx-vision',
          network: 'tcp',
          'client-fingerprint': 'chrome',
          'reality-opts': {
            'public-key': r.public_key || '',
            'short-id': r.short_id
          },
          servername: r.server_name
        });
        names.push(name);
      }
      // WS-TLS
      if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
        const w = doc.inbounds.vless_ws_tls;
        const name = `${namePrefix}-WS-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: w.domain,
          port: w.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          servername: w.domain,
          network: 'ws',
          'ws-opts': {
            path: w.path || '/ws',
            headers: { Host: w.domain }
          }
        });
        names.push(name);
      }
      // Hysteria2
      if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
        const h = doc.inbounds.hysteria2;
        const pass = user.hy2_pass || h.global_password;
        const name = `${namePrefix}-HY2-${user.name}`;
        proxies.push({
          name,
          type: 'hysteria2',
          server: host,
          port: h.listen_port || 8443,
          password: pass,
          sni: host,
          'skip-cert-verify': false,
          alpn: ['h3'],
          udp: true
        });
        names.push(name);
      }
      // Proxy groups (Mihomo/Clash Meta)
      const groups = [];
      if (names.length > 0) {
        groups.push({
          name: '🟢 Auto',
          type: 'url-test',
          proxies: names,
          url: computeTestUrl(req),
          interval: 300,
          tolerance: 50,
          lazy: true
        });
        groups.push({
          name: '🔀 Select',
          type: 'select',
          proxies: ['🟢 Auto', ...names, 'DIRECT']
        });
      }
      const y = yaml.dump({ proxies, 'proxy-groups': groups });
      res.type('text/yaml').send(y);
      return;
    }

    if (format === 'clash_full') {
      const tpl = (req.query.tpl || 'balanced').toString();
      // Full Mihomo/Clash Meta config: proxies + proxy-groups + rule-providers + rules
      const proxies = [];
      const names = [];
      // REALITY
      if (doc.inbounds && doc.inbounds.reality && doc.inbounds.reality.enabled) {
        const r = doc.inbounds.reality;
        const name = `${namePrefix}-REALITY-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: host,
          port: r.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          flow: 'xtls-rprx-vision',
          network: 'tcp',
          'client-fingerprint': 'chrome',
          'reality-opts': {
            'public-key': r.public_key || '',
            'short-id': r.short_id
          },
          servername: r.server_name
        });
        names.push(name);
      }
      // WS-TLS
      if (doc.inbounds && doc.inbounds.vless_ws_tls && doc.inbounds.vless_ws_tls.enabled) {
        const w = doc.inbounds.vless_ws_tls;
        const name = `${namePrefix}-WS-${user.name}`;
        proxies.push({
          name,
          type: 'vless',
          server: w.domain,
          port: w.listen_port || 443,
          uuid: user.vless_uuid,
          udp: true,
          tls: true,
          servername: w.domain,
          network: 'ws',
          'ws-opts': {
            path: w.path || '/ws',
            headers: { Host: w.domain }
          }
        });
        names.push(name);
      }
      // Hysteria2
      if (doc.inbounds && doc.inbounds.hysteria2 && doc.inbounds.hysteria2.enabled) {
        const h = doc.inbounds.hysteria2;
        const pass = user.hy2_pass || h.global_password;
        const name = `${namePrefix}-HY2-${user.name}`;
        proxies.push({
          name,
          type: 'hysteria2',
          server: host,
          port: h.listen_port || 8443,
          password: pass,
          sni: host,
          'skip-cert-verify': false,
          alpn: ['h3'],
          udp: true
        });
        names.push(name);
      }

      // Groups
      const groups = [];
      if (names.length > 0) {
        groups.push({
          name: '🟢 Auto',
          type: 'url-test',
          proxies: names,
          url: 'https://www.gstatic.com/generate_204',
          interval: 300,
          tolerance: 50,
          lazy: true
        });
        groups.push({
          name: '🔀 Select',
          type: 'select',
          proxies: ['🟢 Auto', ...names, 'DIRECT']
        });
      }

      // Rule providers (popular open-source lists; users may replace with private mirrors)
      const providers = {
        reject: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt',
          path: './providers/reject.txt', interval: 86400
        },
        direct: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt',
          path: './providers/direct.txt', interval: 86400
        },
        proxy: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt',
          path: './providers/proxy.txt', interval: 86400
        },
        private: {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt',
          path: './providers/private.txt', interval: 86400
        },
        'tld-not-cn': {
          type: 'http', behavior: 'domain', format: 'text',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt',
          path: './providers/tld-not-cn.txt', interval: 86400
        },
        applications: {
          type: 'http', behavior: 'classical',
          url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt',
          path: './providers/applications.yaml', interval: 86400
        }
      };

      // Rules (order matters) - selectable templates
      let rules;
      if (tpl === 'global') {
        // Global proxy: most traffic goes to proxy, CN stays DIRECT
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else if (tpl === 'cn') {
        // Mainland-first: prefer DIRECT for China; proxy for tld-not-cn & proxy sets
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      } else {
        // balanced (default): same as cn
        rules = [
          'RULE-SET,applications,DIRECT',
          'RULE-SET,private,DIRECT',
          'RULE-SET,reject,REJECT',
          'RULE-SET,direct,DIRECT',
          'RULE-SET,proxy,🔀 Select',
          'RULE-SET,tld-not-cn,🔀 Select',
          'GEOIP,CN,DIRECT',
          'MATCH,🔀 Select'
        ];
      }

      const cfg = {
        port: 7890,
        'socks-port': 7891,
        'allow-lan': false,
        mode: 'Rule',
        'log-level': 'info',
        dns: {
          enable: true,
          listen: '0.0.0.0:1053',
          ipv6: false,
          'enhanced-mode': 'fake-ip',
          'fake-ip-range': '198.18.0.1/16',
          'fake-ip-filter': [
            '*.lan', 'localhost', '+.local', 'time.*.com', 'time.*.gov',
            'ntp.*.com', 'ntp.*.cn', 'pool.ntp.org', 'connect.rom.miui.com'
          ],
          'default-nameserver': ['119.29.29.29', '223.5.5.5'],
          nameserver: ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
          fallback: ['tls://1.1.1.1:853', 'tls://8.8.8.8:853'],
          'proxy-server-nameserver': ['https://cloudflare-dns.com/dns-query'],
          'nameserver-policy': {
            'geosite:cn': ['119.29.29.29', '223.5.5.5'],
            'geosite:geolocation-!cn': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query']
          },
          'fallback-filter': {
            'geoip': true,
            'geoip-code': 'CN',
            'domain': ['+.google.com', '+.facebook.com', '+.github.com', '+.githubusercontent.com']
          }
        },
        proxies,
        'proxy-groups': groups,
        'rule-providers': providers,
        rules
      };
      const y = yaml.dump(cfg);
      res.type('text/yaml').send(y);
      return;
    }
        
    res.status(400).send('unsupported format');
  } catch (e) {
    safeError(res, e);
  }
});

// Everything below requires admin basic auth
app.use(auth);

// API: diag (summary of required items) - admin auth
app.get('/api/diag', (req, res) => {
  try {
    const y = fs.readFileSync(SBX_YAML, 'utf8');
    const doc = yaml.load(y) || {};
    const ib = doc.inbounds || {};
    const users = (doc.users || []).filter(u => u && u.enabled);
    const d = {
      exportHost: (doc.export && doc.export.host) || '',
      cloudflareMode: doc.cloudflare_mode || 'proxied',
      users: users.map(u => ({
        name: u.name || '', token: !!u.token, uuid: !!u.vless_uuid, hy2: !!u.hy2_pass
      })),
      inbounds: {
        reality: {
          enabled: !!(ib.reality && ib.reality.enabled),
          server_name: ib.reality && ib.reality.server_name || '',
          priv: !!(ib.reality && ib.reality.private_key),
          sid: !!(ib.reality && ib.reality.short_id),
          port: ib.reality && ib.reality.listen_port || 443
        },
        ws: {
          enabled: !!(ib.vless_ws_tls && ib.vless_ws_tls.enabled),
          domain: ib.vless_ws_tls && ib.vless_ws_tls.domain || '',
          path: ib.vless_ws_tls && ib.vless_ws_tls.path || '/ws',
          port: ib.vless_ws_tls && ib.vless_ws_tls.listen_port || 443,
          cert: ib.vless_ws_tls && ib.vless_ws_tls.cert_path || '',
          key: ib.vless_ws_tls && ib.vless_ws_tls.key_path || ''
        },
        hy2: {
          enabled: !!(ib.hysteria2 && ib.hysteria2.enabled),
          port: ib.hysteria2 && ib.hysteria2.listen_port || 8443,
        }
      }
    };
    res.json(d);
  } catch (e) { return safeError(res, e); }
});


// API: list users (admin)
app.get('/api/users', (req, res) => {
  try {
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const users = (doc.users || []).map(u => ({
      name: u.name || '',
      enabled: !!u.enabled,
      token: u.token || '',
      vless_uuid: u.vless_uuid || '',
      has_hy2: !!u.hy2_pass
    }));
    res.json({ users });
  } catch (e) { return safeError(res, e); }
});

// API: rotate token (admin)
app.post('/api/user/rotate', (req, res) => {
  try {
    const name = (req.body && req.body.name || '').toString();
    if (!name || !/^[a-zA-Z0-9._-]{1,32}$/.test(name)) return res.status(400).json({error:'bad user name'});
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const users = doc.users || [];
    const crypto = require('crypto');
    const idx = users.findIndex(u => u && u.name === name);
    if (idx < 0) return res.status(404).json({error:'not found'});
    users[idx].token = crypto.randomBytes(18).toString('base64url');
    doc.users = users;
    fs.writeFileSync(SBX_YAML, yaml.dump(doc), 'utf8');
    res.json({ ok:true, user: { name, token: users[idx].token } });
  } catch (e) { return safeError(res, e); }
});

// API: enable/disable user (admin)
app.post('/api/user/enable', (req, res) => {
  try {
    const name = (req.body && req.body.name || '').toString();
    const en = !!(req.body && req.body.enable);
    if (!name || !/^[a-zA-Z0-9._-]{1,32}$/.test(name)) return res.status(400).json({error:'bad user name'});
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const users = doc.users || [];
    const idx = users.findIndex(u => u && u.name === name);
    if (idx < 0) return res.status(404).json({error:'not found'});
    users[idx].enabled = en;
    doc.users = users;
    fs.writeFileSync(SBX_YAML, yaml.dump(doc), 'utf8');
    res.json({ ok:true, user: { name, enabled: en } });
  } catch (e) { return safeError(res, e); }
});

// API: get config
app.get('/api/config', (req, res) => {
  try {
    const y = fs.readFileSync(SBX_YAML, 'utf8');
    res.type('text/yaml').send(y);
  } catch (e) {
    safeError(res, e);
  }
});

// API: save config
app.post('/api/config', (req, res) => {
  try {
    const content = req.body && req.body.content;
    if (typeof content !== 'string') return res.status(400).json({error: 'content required'});
    // Validate YAML minimally
    yaml.load(content);
    fs.writeFileSync(SBX_YAML, content, 'utf8');
    res.json({ok: true});
  } catch (e) {
    safeError(res, e);
  }
});


// API: fix actions (admin) - limited, safe wrapper around cmd.js
app.post('/api/fix', async (req, res) => {
  try {
    const body = req.body || {};
    const action = (body.action || '').toString();
    let arg = (body.arg || '').toString();
    const allowed = ['enable','disable','cf','sethost','setdomain','adduser','rmuser'];
    if (!allowed.includes(action)) return res.status(400).json({error:'unsupported action'});
    // basic validation
    if (['enable','disable'].includes(action) && !['reality','ws','hy2'].includes(arg)) {
      return res.status(400).json({error:'bad inbound key'});
    }
    if (action === 'cf' && !['proxied','direct'].includes(arg)) {
      return res.status(400).json({error:'bad cf mode'});
    }
    if (['adduser','rmuser'].includes(action) && !/^[a-zA-Z0-9._-]{1,32}$/.test(arg)) {
      return res.status(400).json({error:'bad user name'});
    }
    const hostRe = /^(?:[a-zA-Z0-9-]{1,63}\.)+[a-zA-Z]{2,63}$|^(?:\d{1,3}\.){3}\d{1,3}$/;
    if (['sethost','setdomain'].includes(action)) {
      if (!arg) {
        try {
          const out = require('child_process').execSync("bash -lc 'curl -4 -fsS ifconfig.co || curl -4 -fsS api.ipify.org'").toString().trim();
          if (out) arg = out;
        } catch(e) {}
      } else if (!hostRe.test(arg)) {
        return res.status(400).json({error:'bad host/domain'});
      }
    }
    const { spawn } = require('child_process');
    const p = spawn('node', ['/opt/sbx/panel/cmd.js', action, arg], {stdio:['ignore','pipe','pipe']});
    let out='', err='';
    p.stdout.on('data', d=> out+=d);
    p.stderr.on('data', d=> err+=d);
    p.on('close', code => {
      if (code !== 0) return res.status(500).json({error: err || 'apply failed'});
      return res.json({ok:true, output: out});
    });
  } catch (e) { return safeError(res, e); }
});


// API: Hy2 TLS check
app.get('/api/hy2/tls-check', (req, res) => {
  try {
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const h = (doc.inbounds && doc.inbounds.hysteria2) || {};
    const cert = (h.tls && h.tls.certificate_path) || '';
    const key = (h.tls && h.tls.key_path) || '';
    const fsExists = (p) => p && fs.existsSync(p);
    const result = { enabled: !!h.enabled, cert_path: cert, key_path: key,
      cert_exists: fsExists(cert), key_exists: fsExists(key) };
    res.json(result);
  } catch(e){ return safeError(res, e); }
});

// API: Hy2 TLS set paths
app.post('/api/hy2/tls-set', (req, res) => {
  try {
    const cert = (req.body && req.body.cert_path || '').toString();
    const key = (req.body && req.body.key_path || '').toString();
    if (!cert || !key) return res.status(400).json({error:'cert_path/key_path required'});
    if (!fs.existsSync(cert) || !fs.existsSync(key)) return res.status(400).json({error:'cert/key not found'});
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    doc.inbounds = doc.inbounds || {};
    doc.inbounds.hysteria2 = doc.inbounds.hysteria2 || {};
    doc.inbounds.hysteria2.tls = doc.inbounds.hysteria2.tls || {};
    doc.inbounds.hysteria2.tls.certificate_path = cert;
    doc.inbounds.hysteria2.tls.key_path = key;
    fs.writeFileSync(SBX_YAML, yaml.dump(doc), 'utf8');
    res.json({ok:true});
  } catch(e){ return safeError(res, e); }
});

// API: health summary (subset of diagnose)
app.get('/api/health', (req, res) => {
  try {
    const { execSync } = require('child_process');
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));
    const ib = doc.inbounds || {};
    const sum = JSON.parse(execSync('node /opt/sbx/panel/diag.js', {encoding:'utf8'}));
    // sing-box check
    let sbCheck = { ok: false, output: '' };
    try {
      const out = execSync('sing-box check -c /etc/sing-box/config.json', {encoding:'utf8'});
      sbCheck = { ok: true, output: out.slice(0, 4000) };
    } catch(e) {
      sbCheck = { ok: false, output: (e.stdout||'') + (e.stderr||'') };
    }
    // service status
    let svc = 'unknown';
    try { svc = execSync('systemctl is-active sing-box', {encoding:'utf8'}).trim(); } catch(e){}
    // ports
    function listen(port) {
      try {
        const out = execSync(`ss -lntup | grep ":${port} " || true`, {encoding:'utf8'});
        return out.trim().length > 0;
      } catch(e) { return null; }
    }
    const ports = {};
    if (ib.reality && ib.reality.enabled) ports.reality = listen(ib.reality.listen_port || 443);
    if (ib.vless_ws_tls && ib.vless_ws_tls.enabled) ports.ws = listen(ib.vless_ws_tls.listen_port || 443);
    if (ib.hysteria2 && ib.hysteria2.enabled) ports.hy2 = listen(ib.hysteria2.listen_port || 8443);
    res.json({ summary: sum, singbox: sbCheck, service: svc, ports });
  } catch(e){ return safeError(res, e); }
});

// API: apply -> generate config.json + restart sing-box
app.post('/api/apply', (req, res) => {
  exec('node /opt/sbx/panel/gen-config.js && sing-box check -c /etc/sing-box/config.json && systemctl restart sing-box', (err, stdout, stderr) => {
    if (err) return res.status(500).json({error: stderr || err.message});
    return res.json({ok: true, output: stdout});
  });
});

// API: create a new user quickly
app.post('/api/user/new', (req, res) => {
  try {
    const body = req.body || {};
    const name = (body.name || '').toString().trim() || 'user';
    const doc = yaml.load(fs.readFileSync(SBX_YAML, 'utf8'));

    const token = crypto.randomBytes(18).toString('base64url');
    const vless_uuid = (require('child_process').execSync('sing-box generate uuid').toString().trim());
    const hy2_pass = crypto.randomBytes(14).toString('base64url');

    const users = doc.users || [];
    users.push({ name, enabled: true, token, vless_uuid, hy2_pass });
    doc.users = users;
    fs.writeFileSync(SBX_YAML, yaml.dump(doc), 'utf8');
    res.json({ ok: true, user: { name, token, vless_uuid, hy2_pass } });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.listen(SBX_PORT, SBX_BIND, () => {
  console.log(`sbx-lite panel listening on http://${SBX_BIND}:${SBX_PORT}`);
});
