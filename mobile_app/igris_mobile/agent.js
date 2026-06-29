/**
 * IGRIS Desktop Agent
 * Run this on your laptop to enable mobile device controls.
 * 
 * Setup:
 * 1. npm install socket.io-client
 * 2. Update BACKEND_URL and USER_TOKEN
 * 3. node agent.js
 */

const { io } = require("socket.io-client");
const { exec } = require("child_process");
const os = require("os");

// ── CONFIGURATION ───────────────────────────────────────────────────
const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:8080";
const USER_TOKEN = process.env.USER_TOKEN || ""; 

if (!USER_TOKEN) {
    console.error("❌ Error: USER_TOKEN environment variable is not set.");
    console.error("Please launch the agent with the USER_TOKEN environment variable, for example:");
    console.error("  Windows (PowerShell): $env:USER_TOKEN=\"your_token\"; node agent.js");
    console.error("  Linux/macOS: USER_TOKEN=\"your_token\" node agent.js\n");
    process.exit(1);
}
// ────────────────────────────────────────────────────────────────────

const socket = io(BACKEND_URL, {
    withCredentials: true,
});

let statusInterval;

socket.on("connect", () => {
    console.log("🟢 Connected to IGRIS Backend");
    socket.emit("authenticate", { token: USER_TOKEN });
});

socket.on("auth_success", ({ userId }) => {
    console.log(`✅ Authenticated as user: ${userId}`);
    console.log("🚀 Waiting for commands from mobile app...");
    
    // Start reporting status every 10 seconds
    if (statusInterval) clearInterval(statusInterval);
    statusInterval = setInterval(() => reportStatus(userId), 10000);
    reportStatus(userId);
});

function reportStatus(userId) {
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;
    
    const status = {
        userId,
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
            usage: 0, // Simplified for agent
        },
        memory: {
            total: Math.round(totalMem / (1024 * 1024 * 1024) * 10) / 10,
            used: Math.round(usedMem / (1024 * 1024 * 1024) * 10) / 10,
            free: Math.round(freeMem / (1024 * 1024 * 1024) * 10) / 10,
            usagePercent: Math.round((usedMem / totalMem) * 100),
        },
        lastSeen: new Date().toISOString()
    };
    
    socket.emit("AGENT_STATUS_UPDATE", status);
}

socket.on("auth_error", ({ message }) => {
    console.error("❌ Authentication failed:", message);
    process.exit(1);
});

socket.on("SYSTEM_COMMAND", (data) => {
    console.log(`\n📥 Received command: ${data.action}`);
    if (data.command) {
        console.log(`🖥️ Executing: ${data.command}`);
        
        exec(data.command, (error, stdout, stderr) => {
            if (error) {
                console.error(`❌ Error: ${error.message}`);
                return;
            }
            if (stderr) console.warn(`⚠️ Stderr: ${stderr}`);
            console.log(`✅ Success: ${stdout.trim() || "Action completed"}`);
        });
    }
});

socket.on("disconnect", () => {
    console.log("🔴 Disconnected from backend");
    if (statusInterval) clearInterval(statusInterval);
});

socket.on("connect_error", (err) => {
    console.error("🔌 Connection error:", err.message);
});
