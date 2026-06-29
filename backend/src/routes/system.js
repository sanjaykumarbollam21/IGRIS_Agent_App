const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const os = require('os');
const si = require('systeminformation');
const { authenticateToken } = require('../middleware/auth');
const cacheService = require('../services/cacheService');
const logger = require('../utils/logger');
const notificationService = require('../services/notificationService');

// Rule #3 — Only whitelisted system actions allowed
const ALLOWED_ACTIONS = new Set([
  'shutdown', 'restart', 'sleep', 'lock', 'cancel_shutdown',
  'volume_up', 'volume_down', 'volume_mute',
  'screen_off', 'brightness_up', 'brightness_down',
  'open_app', 'open_url', 'screenshot', 'open_explorer', 'task_manager'
]);

/**
 * Sanitize string parameters to prevent command injection (Rule #3)
 */
function sanitizeAppName(input) {
  if (typeof input !== 'string') return '';
  const trimmed = input.trim();
  // Allow only alphanumeric, spaces, dashes, underscores, and dots (e.g. notepad.exe)
  if (/^[a-zA-Z0-9\s-_\.]+$/.test(trimmed)) {
    return trimmed.substring(0, 100);
  }
  return '';
}

function sanitizeUrl(input) {
  if (typeof input !== 'string') return '';
  try {
    const parsed = new URL(input.trim());
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
      return parsed.href.substring(0, 500);
    }
  } catch (e) {
    // Invalid URL
  }
  return '';
}

// Rule #4 — System status requires authentication
router.get('/status', authenticateToken, async (req, res) => {
  try {
    // Check if we have a fresh status from the Desktop Agent (Online)
    const cachedStatus = await cacheService.get(`agent_status:${req.userId}`);
    if (cachedStatus) {
      return res.json({
        success: true,
        isOnline: true,
        ...cachedStatus,
        source: 'agent'
      });
    }

    // Check if we have last known status from the Desktop Agent (Offline)
    let lastKnownStatus = await cacheService.get(`agent_status_last_known:${req.userId}`);
    if (!lastKnownStatus) {
      try {
        const fs = require('fs');
        const path = require('path');
        const filePath = path.join(__dirname, `../data/last_known_${req.userId}.json`);
        if (fs.existsSync(filePath)) {
          const fileData = fs.readFileSync(filePath, 'utf8');
          lastKnownStatus = JSON.parse(fileData);
          // Restore back to cache
          await cacheService.set(`agent_status_last_known:${req.userId}`, lastKnownStatus, 315360000);
        }
      } catch (err) {
        logger.error(`Error reading persistent agent status: ${err.message}`);
      }
    }

    if (lastKnownStatus) {
      return res.json({
        success: true,
        isOnline: false,
        ...lastKnownStatus,
        source: 'agent_last_known'
      });
    }

    // If no agent status is recorded yet, do not return server stats on production host
    if (process.env.ALLOW_LOCAL_COMMANDS !== 'true') {
      return res.json({
        success: false,
        message: 'No desktop agent status recorded yet. Please run the desktop agent on your laptop.'
      });
    }

    const cpuData = await si.currentLoad();
    const memData = await si.mem();
    const batteryData = await si.battery();
    const diskData = await si.fsSize();
    const osInfo = await si.osInfo();
    const networkInterfaces = await si.networkInterfaces();

    const activeNet = networkInterfaces.find(n => n.operstate === 'up' && !n.internal);

    res.json({
      success: true,
      isOnline: false,
      source: 'server',
      device: {
        name: os.hostname(),
        platform: os.platform(),
        os: `${osInfo.distro} ${osInfo.release}`,
        arch: os.arch(),
        uptime: os.uptime(),
        type: 'laptop',
      },
      cpu: {
        model: os.cpus()[0]?.model || 'Unknown',
        cores: os.cpus().length,
        usage: Math.round(cpuData.currentLoad),
      },
      memory: {
        total: Math.round(memData.total / (1024 * 1024 * 1024) * 10) / 10,
        used: Math.round(memData.active / (1024 * 1024 * 1024) * 10) / 10,
        free: Math.round(memData.available / (1024 * 1024 * 1024) * 10) / 10,
        usagePercent: Math.round((memData.active / memData.total) * 100),
      },
      battery: {
        hasBattery: batteryData.hasBattery,
        percent: batteryData.percent,
        isCharging: batteryData.isCharging,
        timeRemaining: batteryData.timeRemaining,
      },
      disk: diskData.map(d => ({
        fs: d.fs,
        size: Math.round(d.size / (1024 * 1024 * 1024) * 10) / 10,
        used: Math.round(d.used / (1024 * 1024 * 1024) * 10) / 10,
        usagePercent: Math.round(d.use),
      })).slice(0, 3),
      network: activeNet ? {
        interface: activeNet.iface,
        ip: activeNet.ip4,
        type: activeNet.type,
        speed: activeNet.speed,
      } : null,
    });
  } catch (error) {
    // Fallback with basic os info if systeminformation fails
    res.json({
      success: true,
      isOnline: false,
      source: 'server',
      device: {
        name: os.hostname(),
        platform: os.platform(),
        os: `${os.type()} ${os.release()}`,
        arch: os.arch(),
        uptime: os.uptime(),
        type: 'laptop',
      },
      cpu: {
        model: os.cpus()[0]?.model || 'Unknown',
        cores: os.cpus().length,
        usage: 0,
      },
      memory: {
        total: Math.round(os.totalmem() / (1024 * 1024 * 1024) * 10) / 10,
        free: Math.round(os.freemem() / (1024 * 1024 * 1024) * 10) / 10,
        used: Math.round((os.totalmem() - os.freemem()) / (1024 * 1024 * 1024) * 10) / 10,
        usagePercent: Math.round(((os.totalmem() - os.freemem()) / os.totalmem()) * 100),
      },
      battery: { hasBattery: false, percent: 0, isCharging: false },
      disk: [],
      network: null,
    });
  }
});

// Rule #4 — Execute system command — authentication required
// Rule #3 — Only whitelisted actions accepted; params sanitized
router.post('/command', authenticateToken, (req, res) => {
  const { action, params } = req.body;
  
  // Per design requirements, "Device Controls" should be executed on the USER'S hardware,
  // not on the backend server. We use Socket.IO to bridge to the desktop agent.
  const platform = params?.platform || 'win32'; // Default to win32 for the laptop agent

  // Rule #3 — Reject any action not on the whitelist
  if (!action || !ALLOWED_ACTIONS.has(action)) {
    return res.status(400).json({
      success: false,
      message: 'Invalid or disallowed action.'
    });
  }

  let command = '';

  // Determine the command for the target platform (Desktop Agent will execute this)
  switch (action) {
    // Power controls
    case 'shutdown':
      command = platform === 'win32' ? 'shutdown /s /t 30' : 'shutdown -h +0.5';
      break;
    case 'restart':
      command = platform === 'win32' ? 'shutdown /r /t 30' : 'shutdown -r +0.5';
      break;
    case 'sleep':
      command = platform === 'win32' ? 'rundll32.exe powrprof.dll,SetSuspendState 0,1,0' : 'pmset sleepnow';
      break;
    case 'lock':
      command = platform === 'win32' ? 'rundll32.exe user32.dll,LockWorkStation' : 'pmset displaysleepnow';
      break;
    case 'cancel_shutdown':
      command = platform === 'win32' ? 'shutdown /a' : 'shutdown -c';
      break;

    // Volume controls
    case 'volume_up':
      command = platform === 'win32'
        ? 'powershell -Command "$w = Add-Type -MemberDefinition \'[DllImport(\\\"user32.dll\\\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, uint dwExtraInfo);\' -Name KBUp -PassThru; $w::keybd_event(0xAF, 0, 0, 0); $w::keybd_event(0xAF, 0, 2, 0)"'
        : 'osascript -e "set volume output volume ((output volume of (get volume settings)) + 10)"';
      break;
    case 'volume_down':
      command = platform === 'win32'
        ? 'powershell -Command "$w = Add-Type -MemberDefinition \'[DllImport(\\\"user32.dll\\\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, uint dwExtraInfo);\' -Name KBDown -PassThru; $w::keybd_event(0xAE, 0, 0, 0); $w::keybd_event(0xAE, 0, 2, 0)"'
        : 'osascript -e "set volume output volume ((output volume of (get volume settings)) - 10)"';
      break;
    case 'volume_mute':
      command = platform === 'win32'
        ? 'powershell -Command "$w = Add-Type -MemberDefinition \'[DllImport(\\\"user32.dll\\\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, uint dwExtraInfo);\' -Name KBMute -PassThru; $w::keybd_event(0xAD, 0, 0, 0); $w::keybd_event(0xAD, 0, 2, 0)"'
        : 'osascript -e "set volume with output muted"';
      break;

    // Screen controls
    case 'screen_off':
      command = platform === 'win32'
        ? 'powershell -c "(Add-Type \'[DllImport(\\"user32.dll\\")]public static extern int SendMessage(int hWnd,int hMsg,int wParam,int lParam);\' -Name a -Pas)::SendMessage(-1,0x0112,0xF170,2)"'
        : 'pmset displaysleepnow';
      break;
    case 'brightness_up':
      command = platform === 'win32'
        ? 'powershell -c "Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods | Invoke-WmiMethod -Name WmiSetBrightness -Args @(0, [Math]::Min(100, (Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightness).CurrentBrightness + 10))"'
        : 'brightness up';
      break;
    case 'brightness_down':
      command = platform === 'win32'
        ? 'powershell -c "Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods | Invoke-WmiMethod -Name WmiSetBrightness -Args @(0, [Math]::Max(0, (Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightness).CurrentBrightness - 10))"'
        : 'brightness down';
      break;

    // App controls
    case 'open_app':
      if (params?.appName) {
        const safeName = sanitizeAppName(params.appName);
        if (safeName) {
          command = platform === 'win32' ? `start "" "${safeName}"` : `open -a "${safeName}"`;
        }
      }
      break;
    case 'open_url':
      if (params?.url) {
        const safeUrl = sanitizeUrl(params.url);
        if (safeUrl) {
          command = platform === 'win32' ? `start "" "${safeUrl}"` : `open "${safeUrl}"`;
        }
      }
      break;

    case 'screenshot':
      command = platform === 'win32' ? 'snippingtool' : 'screencapture ~/Desktop/screenshot.png';
      break;
    case 'open_explorer':
      command = platform === 'win32' ? 'explorer.exe' : 'open ~/';
      break;
    case 'task_manager':
      command = platform === 'win32' ? 'taskmgr.exe' : 'open -a "Activity Monitor"';
      break;
  }

  // Dispatch to Socket.IO room (Rule Bridge — from Cloud back to Local Host)
  notificationService.notifyUser(req.userId, 'SYSTEM_COMMAND', {
    action,
    params,
    command,
    timestamp: new Date().toISOString()
  });

  // If running locally, execute command directly. SECURITY: this path is
  // opt-in (ALLOW_LOCAL_COMMANDS=true) and the `command` string is built
  // from a fixed switch on `action` above — not from raw user input. The
  // socket dispatch above is the normal path; local exec is just a dev
  // convenience. The desktop_agent (which the socket targets) is what
  // enforces the action allowlist.
  if (process.env.ALLOW_LOCAL_COMMANDS === 'true' && command) {
    exec(command, { shell: true, timeout: 10000 }, (error) => {
      if (error) logger.error(`Local command execution failed: ${error.message}`);
      else logger.info(`Local command executed: ${action}`);
    });
  }

  // Log dispatch
  logger.info({ event: 'system_command_dispatched', action, userId: req.userId });

  res.json({
    success: true,
    message: process.env.ALLOW_LOCAL_COMMANDS === 'true' 
      ? `Action "${action}" executed locally.`
      : `Action "${action}" dispatched to your desktop agent.`,
    dispatched: true
  });
});

module.exports = router;
