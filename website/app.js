// IGRIS Web Dashboard — Backend Integration
// SECURITY: never hardcode a production backend URL in this file. The user
// must set it via the Config page (saved to localStorage) or, for production
// deploys, by setting `window.IGRIS_BACKEND_URL` before this script loads.
const DEFAULT_BASE = (typeof window !== 'undefined' && window.IGRIS_BACKEND_URL)
  || 'http://43.205.136.242:8080';
const ADMIN_EMAIL = 'admin@igris.ai';

function getBase() { return localStorage.getItem('igris_backend_url') || DEFAULT_BASE; }
function getApi() { return getBase() + '/api'; }

let token = sessionStorage.getItem('igris_token') || '';
// SECURITY (Rule #1, Rule AI/LLM): The Gemini API key is the user's own
// per-account key. Storing it in localStorage would expose it to any XSS that
// fires on this origin and persist it across sessions. We use sessionStorage
// so it disappears when the tab closes. For production, prefer routing AI
// calls through the backend (X-Gemini-API-Key header on the server) so the
// key never reaches the browser at all.
let geminiKey = sessionStorage.getItem('igris_gemini_key') || '';
let isProcessing = false, isListening = false, recognition = null;
let chatHistory = JSON.parse(localStorage.getItem('igris_chat') || '[]');
let isAdmin = false;

const $ = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);

// ─── Auth ───
function checkAuth() {
  if (!token) { $('#loginOverlay').classList.remove('hidden'); return false; }
  $('#loginOverlay').classList.add('hidden');
  loadUserInfo();
  return true;
}

$('#loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  const email = $('#loginEmail').value.trim(), password = $('#loginPassword').value;
  $('#loginError').textContent = '';
  try {
    const r = await fetch(`${getApi()}/auth/login`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email,password}) });
    const d = await r.json();
    if (r.ok && d.token) {
      token = d.token;
      sessionStorage.setItem('igris_token', token);
      if (d.refreshToken) sessionStorage.setItem('igris_refresh_token', d.refreshToken);
      isAdmin = email === ADMIN_EMAIL;
      localStorage.setItem('igris_user_email', email);
      $('#loginOverlay').classList.add('hidden');
      setupAdminUI();
      loadUserInfo();
      checkBackend();
      updateAgent();
    } else { $('#loginError').textContent = d.message || 'Auth failed'; }
  } catch(e) { $('#loginError').textContent = 'Cannot reach backend.'; }
});

$('#btnLogout').addEventListener('click', () => {
  token = '';
  sessionStorage.clear();
  $('#loginOverlay').classList.remove('hidden');
});

async function loadUserInfo() {
  const email = localStorage.getItem('igris_user_email') || '';
  isAdmin = email === ADMIN_EMAIL;
  setupAdminUI();
  try {
    const r = await apiFetch('/users/dashboard');
    if (r.ok) {
      const d = await r.json();
      const name = d.user?.firstName || email.split('@')[0] || 'User';
      $('#userName').textContent = name;
      $('#userAvatar').textContent = name.charAt(0).toUpperCase();
      $('#userRole').textContent = isAdmin ? 'ADMIN' : 'USER';
    }
  } catch(_){}
}

function setupAdminUI() {
  $$('.admin-only').forEach(el => {
    if (isAdmin) el.classList.add('visible');
    else el.classList.remove('visible');
  });
}

async function apiFetch(path, opts = {}) {
  const headers = { 'Content-Type':'application/json', ...(token ? {'Authorization':`Bearer ${token}`} : {}), ...(geminiKey ? {'X-Gemini-API-Key':geminiKey} : {}), ...(opts.headers||{}) };
  const r = await fetch(`${getApi()}${path}`, {...opts, headers});
  if (r.status === 401 && !path.includes('/auth/login')) {
    token = '';
    sessionStorage.removeItem('igris_token');
    sessionStorage.removeItem('igris_refresh_token');
    $('#loginOverlay').classList.remove('hidden');
  }
  return r;
}

// ─── Navigation ───
$$('.nav-item[data-page]').forEach(item => {
  item.addEventListener('click', () => {
    $$('.nav-item').forEach(n => n.classList.remove('active'));
    item.classList.add('active');
    $$('.page').forEach(p => p.classList.remove('active'));
    const pg = $(`#page-${item.dataset.page}`);
    if (pg) pg.classList.add('active');
    if (item.dataset.page === 'dashboard') loadDashboard();
    if (item.dataset.page === 'logs') loadLogs();
    if (item.dataset.page === 'config') loadConfig();
  });
});

// ─── Chat ───
function renderChat() {
  const el = $('#chatMessages'), empty = $('#chatEmpty');
  if (!chatHistory.length) { empty.style.display = 'flex'; return; }
  empty.style.display = 'none';
  el.innerHTML = chatHistory.map(m => {
    const t = new Date(m.time), ts = `${t.getHours().toString().padStart(2,'0')}:${t.getMinutes().toString().padStart(2,'0')}`;
    return `<div class="msg ${m.isUser?'user':'bot'}"><div class="msg-avatar">${m.isUser?'👤':'⚔'}</div><div><div class="msg-bubble">${esc(m.text)}</div><div class="msg-time">${ts}</div></div></div>`;
  }).join('');
  el.scrollTop = el.scrollHeight;
}

function addMsg(text, isUser) {
  chatHistory.push({ text: (text||'').substring(0,10000), isUser, time: new Date().toISOString() });
  if (chatHistory.length > 100) chatHistory = chatHistory.slice(-100);
  localStorage.setItem('igris_chat', JSON.stringify(chatHistory));
  renderChat();
}

function showTyping() {
  $('#chatMessages').innerHTML += `<div class="msg bot" id="typingMsg"><div class="msg-avatar">⚔</div><div><div class="msg-bubble"><span class="typing-dots"><span></span><span></span><span></span></span></div></div></div>`;
  $('#chatMessages').scrollTop = $('#chatMessages').scrollHeight;
}

function removeTyping() { const t = $('#typingMsg'); if(t) t.remove(); }

async function sendChat() {
  const input = $('#chatInput'), text = input.value.trim();
  if (!text || isProcessing) return;
  input.value = '';
  isProcessing = true;
  addMsg(text, true);

  const local = handleLocal(text);
  if (local) { showTyping(); await new Promise(r=>setTimeout(r,400)); removeTyping(); addMsg(local, false); isProcessing = false; return; }

  showTyping();
  try {
    const r = await apiFetch('/ai/chat', { method:'POST', body:JSON.stringify({message:text, sessionId:'web-session'}) });
    removeTyping();
    if (r.status === 401) { addMsg('Session expired. Please log out and log in again.', false); }
    else { const d = await r.json(); addMsg(d.response || d.reply || d.message || 'No response.', false); }
  } catch(e) { removeTyping(); addMsg('Cannot reach backend.', false); }
  isProcessing = false;
}

function handleLocal(text) {
  const l = text.toLowerCase().trim();
  const map = {'lock':'lock','lock laptop':'lock','sleep':'sleep','shutdown':'shutdown','restart':'restart','mute':'volume_mute','volume up':'volume_up','volume down':'volume_down','screenshot':'screenshot','screen off':'screen_off'};
  for (const [p,a] of Object.entries(map)) { if (l===p||l.includes(p)) { sendCmd(a); return `Executing "${a.replace(/_/g,' ')}"...`; } }
  const m = l.match(/^open\s+(.+)/);
  if (m) { sendCmd('open_app', {appName:m[1].trim()}); return `Opening ${m[1].trim()}...`; }
  return null;
}

$('#chatInput').addEventListener('keydown', e => { if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendChat()} });
$('#sendBtn').addEventListener('click', sendChat);
$$('.chip').forEach(c => c.addEventListener('click', () => { $('#chatInput').value = c.dataset.q; sendChat(); }));

// ─── Voice ───
$('#micBtn').addEventListener('click', toggleMic);
function toggleMic() {
  if (!('webkitSpeechRecognition' in window || 'SpeechRecognition' in window)) return;
  if (isListening) { recognition.stop(); return; }
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  recognition = new SR(); recognition.continuous=false; recognition.interimResults=false; recognition.lang='en-US';
  recognition.onstart = () => { isListening=true; $('#micBtn').classList.add('active'); $('#micBtn').textContent='⏹'; };
  recognition.onresult = e => { $('#chatInput').value = e.results[0][0].transcript; sendChat(); };
  recognition.onend = () => { isListening=false; $('#micBtn').classList.remove('active'); $('#micBtn').textContent='🎙'; };
  recognition.onerror = () => { isListening=false; $('#micBtn').classList.remove('active'); $('#micBtn').textContent='🎙'; };
  recognition.start();
}

// ─── System Commands ───
async function sendCmd(action, params={}) {
  try { const r = await apiFetch('/system/command', {method:'POST', body:JSON.stringify({action,params})}); return await r.json(); }
  catch(e) { return {success:false}; }
}

$$('.control-btn[data-action]').forEach(btn => {
  btn.addEventListener('click', async () => {
    btn.style.opacity='.5';
    const r = await sendCmd(btn.dataset.action);
    btn.style.opacity='1';
    btn.classList.add(r?.success!==false?'success':'error');
    setTimeout(()=>btn.classList.remove('success','error'),1500);
  });
});

$$('.control-btn.app-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    btn.style.opacity='.5';
    await sendCmd('open_app', {appName:btn.dataset.app});
    btn.style.opacity='1';
    btn.classList.add('success');
    setTimeout(()=>btn.classList.remove('success'),1500);
  });
});

$('#launchAppBtn').addEventListener('click', () => {
  const n=$('#appNameInput').value.trim().substring(0,100);
  if(n){sendCmd('open_app',{appName:n});$('#appNameInput').value='';}
});
$('#appNameInput').addEventListener('keydown', e => {
  if(e.key==='Enter'){const n=$('#appNameInput').value.trim().substring(0,100);if(n){sendCmd('open_app',{appName:n});$('#appNameInput').value='';}}
});

// ─── Neural admin commands ───
$('#neuralSendBtn')?.addEventListener('click', sendNeural);
$('#neuralInput')?.addEventListener('keydown', e => { if(e.key==='Enter') sendNeural(); });
async function sendNeural() {
  const input=$('#neuralInput'), text=input?.value?.trim();
  if(!text||isProcessing) return;
  input.value=''; isProcessing=true;
  const resp=$('#neuralResponse');
  resp.textContent='Processing...'; resp.classList.add('has-content');
  const local = handleLocal(text);
  if(local){resp.textContent=local;isProcessing=false;return;}
  try{const r=await apiFetch('/ai/chat',{method:'POST',body:JSON.stringify({message:text,sessionId:'neural-admin'})});const d=await r.json();resp.textContent=d.response||d.reply||d.message||'No response.';}
  catch(e){resp.textContent='Backend unreachable.';}
  isProcessing=false;
}

$$('.qbtn[data-action]').forEach(btn=>{
  btn.addEventListener('click', async()=>{
    btn.style.opacity='.5';
    const r=await sendCmd(btn.dataset.action);
    btn.style.opacity='1';
    btn.classList.add(r?.success!==false?'success':'error');
    setTimeout(()=>btn.classList.remove('success','error'),1500);
  });
});

$('#voiceOrb')?.addEventListener('click', () => {
  if(!('webkitSpeechRecognition' in window||'SpeechRecognition' in window)) return;
  if(isListening){recognition.stop();return;}
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  recognition=new SR();recognition.continuous=false;recognition.interimResults=false;recognition.lang='en-US';
  recognition.onstart=()=>{isListening=true;$('#voiceOrb').classList.add('listening');$('#orbLabel').textContent='LISTENING...'};
  recognition.onresult=e=>{$('#neuralInput').value=e.results[0][0].transcript;sendNeural()};
  recognition.onend=()=>{isListening=false;$('#voiceOrb').classList.remove('listening');$('#orbLabel').textContent='IGRIS ACTIVE'};
  recognition.onerror=()=>{isListening=false;$('#voiceOrb').classList.remove('listening');$('#orbLabel').textContent='IGRIS ACTIVE'};
  recognition.start();
});

// ─── Dashboard ───
async function loadDashboard() {
  try {
    const r = await apiFetch('/system/status');
    const d = await r.json();
    if(!d.success) return;
    const cpu=d.cpu?.usage||0; $('#cpuUsage').textContent=cpu+'%'; $('#cpuBar').style.width=cpu+'%'; $('#cpuBar').className='fill'+(cpu>80?' danger':'');
    const mem=d.memory?.usagePercent||0; $('#memUsage').textContent=mem+'%'; $('#memBar').style.width=mem+'%'; $('#memBar').className='fill purple'+(mem>80?' danger':'');
    if(d.battery?.hasBattery){$('#batteryVal').textContent=d.battery.percent+'%';$('#batterySub').textContent=d.battery.isCharging?'⚡ Charging':'On battery';}
    else{$('#batteryVal').textContent='N/A';$('#batterySub').textContent='No battery';}
    const up=d.device?.uptime||0;$('#uptimeVal').textContent=`${Math.floor(up/3600)}h ${Math.floor((up%3600)/60)}m`;$('#uptimeSub').textContent=d.device?.os||'';
    const di=$('#deviceInfo');di.textContent='';
    [`Name: ${d.device?.name||'--'}`,`OS: ${d.device?.os||'--'}`,`CPU: ${d.cpu?.model||'--'} (${d.cpu?.cores||0} cores)`,`RAM: ${d.memory?.used||0} / ${d.memory?.total||0} GB`,`Network: ${d.network?.ip||'N/A'}`].forEach(l=>{const v=document.createElement('div');v.textContent=l;di.appendChild(v)});
    const dk=$('#diskInfo');dk.textContent='';
    if(d.disk?.length){d.disk.forEach(x=>{const w=document.createElement('div');w.style.marginBottom='8px';const lb=document.createElement('div');lb.textContent=`${x.fs} — ${x.used}/${x.size} GB (${x.usagePercent}%)`;const bar=document.createElement('div');bar.className='progress-bar';const fill=document.createElement('div');fill.className=`fill${x.usagePercent>80?' danger':''}`;fill.style.width=`${x.usagePercent}%`;bar.appendChild(fill);w.appendChild(lb);w.appendChild(bar);dk.appendChild(w)});}
  } catch(e){console.error('Dashboard error:',e)}
}

// ─── Backend & Agent Status ───
async function checkBackend() {
  try {
    const r = await fetch(`${getBase()}/health`, {signal:AbortSignal.timeout(5000)});
    if(r.ok){$('#statusDot').classList.add('online');$('#statusLabel').textContent='Online';$('#coreBadge')&&($('#coreBadge').classList.add('online'),$('#coreBadge').textContent='● NEURAL CORE ACTIVE');$('#cloudBadge')&&($('#cloudBadge').textContent='CONNECTED',$('#cloudBadge').className='badge connected');return true;}
  }catch(_){}
  $('#statusDot').classList.remove('online');$('#statusLabel').textContent='Offline';
  return false;
}

async function updateAgent() {
  try {
    const r = await apiFetch('/system/status');
    if(r.ok){const d=await r.json();const on=d.success&&d.agentConnected!==false;$('#agentDot')&&($('#agentDot').className=`dot ${on?'online':'offline'}`);$('#agentStatus')&&($('#agentStatus').textContent=on?'ONLINE':'OFFLINE',$('#agentStatus').style.color=on?'var(--cyan)':'var(--red)');$('#agentBadge')&&($('#agentBadge').textContent=on?'ONLINE':'OFFLINE',$('#agentBadge').className=`badge ${on?'connected':'pending'}`);}
  } catch(_){$('#agentDot')&&($('#agentDot').className='dot offline');$('#agentStatus')&&($('#agentStatus').textContent='OFFLINE');}
}

$('#btnRefreshDevices')?.addEventListener('click', updateAgent);
$('#btnAgentPing')?.addEventListener('click', updateAgent);

// ─── Logs ───
async function loadLogs() {
  const c=$('#logsContainer');
  try {
    const r=await apiFetch('/conversations/sessions');
    if(!r.ok){c.innerHTML='<div class="log-empty">Failed to load.</div>';return;}
    const d=await r.json(), s=d.sessions||[];
    if(!s.length){c.innerHTML='<div class="log-empty">No conversations yet.</div>';return;}
    c.innerHTML=s.slice(0,50).map(x=>{const t=new Date(x.updatedAt||x.createdAt).toLocaleString();return `<div class="log-entry"><div class="log-time">${esc(t)}</div><div class="log-user">${esc(x.title||x.sessionId||'Untitled')}</div><div class="log-bot">${esc((x.lastMessage||'').substring(0,100))}</div></div>`;}).join('');
  } catch(_){c.innerHTML='<div class="log-empty">Cannot connect.</div>';}
}
$('#btnRefreshLogs')?.addEventListener('click', loadLogs);

// ─── Config ───
function loadConfig() {
  $('#configBackendUrl').value=getBase();
  if(geminiKey) $('#configGeminiKey').value='•'.repeat(12);
  checkBackend().then(ok=>{$('#configStatus').textContent=ok?'✅ Connected':'❌ Offline';$('#configStatus').style.color=ok?'var(--cyan)':'var(--red)';});
}
$('#btnSaveConfig')?.addEventListener('click', ()=>{const u=$('#configBackendUrl').value.trim().replace(/\/+$/,'');if(u){localStorage.setItem('igris_backend_url',u);checkBackend().then(ok=>{$('#configStatus').textContent=ok?'✅ Connected':'❌ Offline'});}});
$('#btnSaveGemini')?.addEventListener('click', ()=>{const k=$('#configGeminiKey').value.trim();if(k&&!k.startsWith('•')){geminiKey=k;sessionStorage.setItem('igris_gemini_key',k);$('#configGeminiKey').value='•'.repeat(12);}});

function esc(t){return typeof t!=='string'?'':t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/\n/g,'<br>');}

// ─── Init ───
document.addEventListener('DOMContentLoaded', ()=>{
  let savedUrl = localStorage.getItem('igris_backend_url');
  if (!savedUrl || savedUrl === 'http://localhost:5000' || savedUrl === 'http://localhost:8080') {
    localStorage.setItem('igris_backend_url', DEFAULT_BASE);
    savedUrl = DEFAULT_BASE;
  }
  checkAuth();
  checkBackend();
  updateAgent();
  renderChat();
  setInterval(()=>{checkBackend();updateAgent()},30000);
});
