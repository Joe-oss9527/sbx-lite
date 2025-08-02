async function loadConfig() {
  const r = await fetch('/api/config');
  const t = await r.text();
  document.getElementById('editor').value = t;
  document.getElementById('msg').textContent = 'Loaded.';
}
async function saveConfig() {
  const content = document.getElementById('editor').value;
  const r = await fetch('/api/config', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({content})
  });
  const d = await r.json();
  document.getElementById('msg').textContent = d.ok ? 'Saved.' : ('Error: ' + d.error);
}
async function applyConfig() {
  const r = await fetch('/api/apply', {method: 'POST'});
  const d = await r.json();
  document.getElementById('msg').textContent = d.ok ? ('Applied.\n' + (d.output||'')) : ('Error: ' + d.error);
}
loadConfig().catch(()=>{});

async function refreshDiag() {
  const r = await fetch('/api/diag');
  const d = await r.json();
  const msgs = [];
  const fixes = [];

  const btn = (label, action, arg) => `<button onclick="fix('${action}','${arg||''}')" style="margin-left:8px;">${label}</button>`;

  // export.host
  if (!d.exportHost || d.exportHost === 'YOUR_PUBLIC_HOST') {
    msgs.push(`export.host 未设置` + btn('设为当前主机IP','sethost',''));
  }

  // users
  if (!d.users || d.users.length === 0) {
    msgs.push(`没有启用的用户` + btn('新增用户 phone','adduser','phone'));
  }

  // REALITY
  if (d.inbounds.reality.enabled) {
    if (!d.inbounds.reality.server_name) msgs.push('REALITY: server_name 为空');
    if (!d.inbounds.reality.priv || !d.inbounds.reality.sid) msgs.push('REALITY: 私钥/short_id 缺失（请重新生成并写入）');
  } else {
    msgs.push('REALITY 未启用（推荐开启）' + btn('启用','enable','reality'));
  }

  // WS
  if (d.inbounds.ws.enabled) {
    if (!d.inbounds.ws.domain) msgs.push('WS-TLS: domain 为空');
    if (!d.inbounds.ws.cert || !d.inbounds.ws.key) {
      msgs.push(`WS-TLS: 证书缺失（${d.cloudflareMode==='proxied'?'需要 Origin Cert':'需要公认证书'}）`);
    }
  }

  // HY2
  if (d.inbounds.hy2.enabled) {
    const hasAnyHy2 = (d.users||[]).some(u=>u.hy2);
    // We don't have hy2 global info here; rely on diagnose.sh for deeper check
    if (!hasAnyHy2) msgs.push('Hy2 启用但没有用户密码（hy2_pass）');
  }

  if (msgs.length === 0) {
    document.getElementById('ck-body').innerHTML = `<div style="color:green">No obvious issues. You can Apply when ready.</div>`;
  } else {
    document.getElementById('ck-body').innerHTML = msgs.map(m=>`<div>• ${m}</div>`).join('');
  }
}
async function fix(action, arg) {
  // If sethost with empty arg, try to use server's first IP (best-effort on backend not implemented here)
  const payload = { action, arg: arg||'' };
  const r = await fetch('/api/fix', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload)});
  const d = await r.json();
  if (!d.ok) {
    alert('Failed: ' + (d.error||'unknown'));
    return;
  }
  await refreshDiag();
}

async function quickApply() {
  const r = await fetch('/api/apply', {method:'POST'});
  const d = await r.json();
  if (d.ok) document.getElementById('msg').textContent = 'Applied.';
  else document.getElementById('msg').textContent = 'Apply failed: ' + (d.error||'unknown');
}
refreshDiag().catch(()=>{});

async function loadUsers() {
  const r = await fetch('/api/users');
  const d = await r.json();
  const rows = (d.users||[]).map(u => {
    const btns = [];
    btns.push(`<button onclick="rotateUser('${u.name}')">Rotate token</button>`);
    if (u.enabled) btns.push(`<button onclick="disableUser('${u.name}')">Disable</button>`);
    else btns.push(`<button onclick="enableUser('${u.name}')">Enable</button>`);
    btns.push(`<button onclick="removeUser('${u.name}')">Delete</button>`);
    const token = u.token ? `<code>${u.token}</code>` : '<i>missing</i>';
    return `<tr><td>${u.name}</td><td>${u.enabled?'✅':'⛔️'}</td><td>${token}</td><td>${u.vless_uuid?'✅':'❌'}</td><td>${u.has_hy2?'✅':'❌'}</td><td>${btns.join(' ')} <button onclick="copySubFor('${u.token}')">Copy subs</button> <button onclick="openQR(\'${u.token}\')">QR</button></td></tr>`;
  }).join('');
  document.getElementById('users-body').innerHTML = `<table><thead><tr><th>Name</th><th>Enabled</th><th>Token</th><th>UUID</th><th>Hy2</th><th>Actions</th></tr></thead><tbody>${rows}</tbody></table>`;
}
async function rotateUser(name) {
  const r = await fetch('/api/user/rotate', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({name})});
  const d = await r.json();
  if (!d.ok) { alert('Rotate failed: '+(d.error||'unknown')); return; }
  await loadUsers();
}
async function enableUser(name) {
  const r = await fetch('/api/user/enable', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({name, enable:true})});
  const d = await r.json();
  if (!d.ok) { alert('Enable failed: '+(d.error||'unknown')); return; }
  await loadUsers();
}
async function disableUser(name) {
  const r = await fetch('/api/user/enable', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({name, enable:false})});
  const d = await r.json();
  if (!d.ok) { alert('Disable failed: '+(d.error||'unknown')); return; }
  await loadUsers();
}
async function removeUser(name) {
  if (!confirm('Delete user '+name+' ?')) return;
  const r = await fetch('/api/fix', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action:'rmuser', arg:name})});
  const d = await r.json();
  if (!d.ok) { alert('Delete failed: '+(d.error||'unknown')); return; }
  await loadUsers();
}
async function addUser() {
  const name = document.getElementById('newUserName').value.trim();
  if (!name) return;
  const r = await fetch('/api/fix', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({action:'adduser', arg:name})});
  const d = await r.json();
  if (!d.ok) { alert('Add failed: '+(d.error||'unknown')); return; }
  document.getElementById('newUserName').value='';
  await loadUsers();
}
// auto-load
loadUsers().catch(()=>{});

function baseURL() {
  // Use current origin by default; user may expose panel via tunnel/reverse-proxy
  return window.location.origin;
}
function buildSub(token, format) {
  return `${baseURL()}/sub/${token}?format=${format}`;
}
async function copyText(t) {
  try {
    await navigator.clipboard.writeText(t);
    alert('Copied.');
  } catch { prompt('Copy manually:', t); }
}
function copySubFor(token) {
  const lines = [
    buildSub(token, 'shadowrocket'),
    buildSub(token, 'singbox'),
    buildSub(token, 'clash'),
    buildSub(token, 'clash_full')
  ];
  copyText(lines.join('\n'));
}
async function shareAll() {
  const r = await fetch('/api/users');
  const d = await r.json();
  const lines = [];
  (d.users||[]).forEach(u => {
    if (!u.token) return;
    lines.push(`# ${u.name}`);
    lines.push(buildSub(u.token, 'shadowrocket'));
    lines.push(buildSub(u.token, 'singbox'));
    lines.push(buildSub(u.token, 'clash'));
    lines.push(buildSub(u.token, 'clash_full'));
    lines.push('');
  });
  if (lines.length === 0) { alert('No users with token'); return; }
  copyText(lines.join('\n'));
}


/*! qrcode.js (minimal) */
function QR8(){function r(r){this.mode=r,this.data=[]}function t(r){this.typeNumber=r,this.modules=null,this.moduleCount=0,this.dataList=[]}function e(r,t){this.x=r,this.y=t}function n(r,t){this.totalCount=r,this.dataCount=t}var o={L:1,M:0,Q:3,H:2};return {qrcode:function(e,n){var o=new t(4);return o.addData(e),o.make(),function(r){for(var t=0,e='<table cellspacing=0 cellpadding=0><tbody>',n=0;n<r.length;n++){e+="<tr>";for(var o=0;o<r[n].length;o++)e+='<td style="width:4px;height:4px;background-color:'+(r[n][o]?"#000":"#fff")+'"></td>';e+="</tr>"}return e+="</tbody></table>"}(function(r){for(var t=[],e=0;e<r.moduleCount;e++){t[e]=[];for(var n=0;n<r.moduleCount;n++)t[e][n]=r.isDark(e,n)}return t}(o))}}}();
function renderQR(el, text){ el.innerHTML = QR8.qrcode(text); }

function openQR(token){
  const base = window.location.origin;
  const ss = `${base}/sub/${token}?format=shadowrocket`;
  const sb = `${base}/sub/${token}?format=singbox`;
  const el1 = document.getElementById('qr-ss');
  const el2 = document.getElementById('qr-sb');
  el1.innerHTML = ''; el2.innerHTML = '';
  renderQR(el1, ss); renderQR(el2, sb);
  document.getElementById('qr-modal').style.display='block';
}
function closeQR(){ document.getElementById('qr-modal').style.display='none'; }

function copyClashFull() {
  (async () => {
    const r = await fetch('/api/users');
    const d = await r.json();
    if (!d.users || d.users.length === 0) { alert('No users'); return; }
    // choose first enabled user by default
    const u = d.users.find(x=>x.enabled && x.token) || d.users[0];
    if (!u || !u.token) { alert('No user token'); return; }
    const tpl = document.getElementById('tplSel').value || 'cn';
    const url = `${baseURL()}/sub/${u.token}?format=clash_full&tpl=${encodeURIComponent(tpl)}`;
    copyText(url);
  })().catch(e=>alert(e.message||e));
}

function tableToPng(elTableContainer, scale=6, pad=8){
  const tbl = elTableContainer.querySelector('table');
  if (!tbl) throw new Error('QR table not found');
  const rows = Array.from(tbl.querySelectorAll('tr'));
  const cells = rows.map(tr => Array.from(tr.querySelectorAll('td')));
  const n = rows.length;
  const m = cells[0].length;
  const size = Math.max(n, m);
  const cell = scale;
  const W = size*cell + pad*2;
  const H = size*cell + pad*2;
  const cvs = document.createElement('canvas');
  cvs.width = W; cvs.height = H;
  const ctx = cvs.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0,0,W,H);
  for (let y=0; y<n; y++) {
    for (let x=0; x<m; x++) {
      const black = cells[y][x].style.backgroundColor === 'rgb(0, 0, 0)' || cells[y][x].style.backgroundColor === 'black' || cells[y][x].style['background-color'] === '#000';
      if (black) {
        ctx.fillStyle = '#000';
        ctx.fillRect(pad + x*cell, pad + y*cell, cell, cell);
      }
    }
  }
  return cvs.toDataURL('image/png');
}
function dlQR(which){
  const id = which === 'ss' ? 'qr-ss' : 'qr-sb';
  const el = document.getElementById(id);
  try {
    const url = tableToPng(el, 8, 12);
    const a = document.createElement('a');
    a.href = url;
    a.download = which === 'ss' ? 'sub-shadowrocket.png' : 'sub-singbox.png';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  } catch(e){
    alert('Download failed: '+(e.message||e));
  }
}

async function runHealth(){
  const r = await fetch('/api/health');
  const d = await r.json();
  const lines = [];
  lines.push(`Service: ${d.service}`);
  lines.push(`sing-box check: ${d.singbox.ok ? 'OK' : 'FAIL'}`);
  if (!d.singbox.ok) lines.push((d.singbox.output||'').slice(0,2000));
  const s = d.summary || {};
  lines.push(`export.host: ${s.exportHost||''}`);
  lines.push(`users: ${s.usersCount}`);
  if (s.inbounds){
    lines.push(`REALITY: ${s.inbounds.realityEnabled?'on':'off'} SNI=${s.inbounds.realityServerName||''}`);
    lines.push(`WS: ${s.inbounds.wsEnabled?'on':'off'} domain=${s.inbounds.wsDomain||''}`);
    lines.push(`Hy2: ${s.inbounds.hy2Enabled?'on':'off'}`);
  }
  if (d.ports){
    const p = d.ports;
    lines.push(`listen ports: reality=${p.reality?'yes':'no'} ws=${p.ws?'yes':'no'} hy2=${p.hy2?'yes':'no'}`);
  }
  document.getElementById('health-body').textContent = lines.join('\n');
}

async function hy2Check(){
  const r = await fetch('/api/hy2/tls-check');
  const d = await r.json();
  const lines = [];
  lines.push(`enabled=${d.enabled}`);
  lines.push(`cert_path=${d.cert_path}  exists=${d.cert_exists}`);
  lines.push(`key_path=${d.key_path}    exists=${d.key_exists}`);
  document.getElementById('hy2-body').textContent = lines.join('\n');
}
function hy2Suggest(){
  document.getElementById('hy2Cert').value='/etc/ssl/fullchain.pem';
  document.getElementById('hy2Key').value='/etc/ssl/privkey.pem';
}
async function hy2Save(){
  const cert = document.getElementById('hy2Cert').value.trim();
  const key = document.getElementById('hy2Key').value.trim();
  const r = await fetch('/api/hy2/tls-set', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({cert_path: cert, key_path: key})});
  const d = await r.json();
  if (!d.ok) { alert('Save failed: '+(d.error||'unknown')); return; }
  alert('Saved. Remember to Apply.');
  await hy2Check();
}
