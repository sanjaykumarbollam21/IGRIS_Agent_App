document.addEventListener('DOMContentLoaded', () => {
    const authOverlay = document.getElementById('authOverlay');
    const appShell = document.getElementById('appShell');
    const authForm = document.getElementById('authForm');
    const logoutBtn = document.getElementById('logoutBtn');
    const navLinks = document.querySelectorAll('.nav-links a');
    const contentArea = document.getElementById('contentArea');
    const pageTitle = document.getElementById('pageTitle');
    const digitalClock = document.getElementById('digitalClock');

    // --- Auth Logic ---
    authForm.addEventListener('submit', (e) => {
        e.preventDefault();
        // In a real app, we would call the backend /auth endpoint
        // For this UI showcase, we simulate a successful link
        authOverlay.classList.add('hidden');
        appShell.classList.remove('hidden');
        localStorage.setItem('igris_auth', 'true');
    });

    logoutBtn.addEventListener('click', () => {
        localStorage.removeItem('igris_auth');
        appShell.classList.add('hidden');
        authOverlay.classList.remove('hidden');
    });

    // Check persistent session
    if (localStorage.getItem('igris_auth') === 'true') {
        authOverlay.classList.add('hidden');
        appShell.classList.remove('hidden');
    }

    // --- Navigation Logic ---
    navLinks.forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const targetPage = link.getAttribute('data-page');

            // Update active state
            navLinks.forEach(l => l.classList.remove('active'));
            link.classList.add('active');

            // Update page title
            pageTitle.textContent = link.querySelector('.label').textContent;

            // Switch page visibility
            document.querySelectorAll('.page').forEach(page => {
                page.classList.remove('active');
                if (page.id === `page-${targetPage}`) {
                    page.classList.add('active');
                }
            });
        });
    });

    // --- Real-time Elements ---
    function updateClock() {
        const now = new Date();
        digitalClock.textContent = now.toLocaleTimeString('en-US', {
            hour12: false,
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
    }
    setInterval(updateClock, 1000);
    updateClock();

    // Simulate telemetry changes
    function updateTelemetry() {
        const cpu = Math.floor(Math.random() * 30) + 5;
        const mem = (4 + Math.random()).toFixed(1);
        const lat = Math.floor(Math.random() * 10) + 20;

        const cpuEl = document.getElementById('cpu-val');
        const memEl = document.getElementById('mem-val');
        const latEl = document.getElementById('latency');

        if (cpuEl) cpuEl.textContent = `${cpu}%`;
        if (memEl) memEl.textContent = `${mem}GB`;
        if (latEl) latEl.textContent = `${lat}ms`;

        // Update CPU bars randomly
        document.querySelectorAll('.bar').forEach(bar => {
            bar.style.height = `${Math.random() * 80 + 20}%`;
        });
    }
    setInterval(updateTelemetry, 3000);
    updateTelemetry();

    // --- Neural Chat Interface ---
    const neuralInput = document.getElementById('neuralInput');
    const sendNeuralBtn = document.getElementById('sendNeuralBtn');
    const neuralMessages = document.getElementById('neuralMessages');

    function addMessage(text, sender = 'user') {
        const msgDiv = document.createElement('div');
        msgDiv.className = `msg ${sender}`;
        msgDiv.innerHTML = `<div class="bubble">${text}</div>`;
        neuralMessages.appendChild(msgDiv);
        neuralMessages.scrollTop = neuralMessages.scrollHeight;
    }

    sendNeuralBtn.addEventListener('click', () => {
        const text = neuralInput.value.trim();
        if (!text) return;

        addMessage(text, 'user');
        neuralInput.value = '';

        // Simulate AI Response
        setTimeout(() => {
            const responses = [
                "Analyzing parameters... Command acknowledged.",
                "Neural sync optimal. Proceeding with execution.",
                "Warning: Resource spike detected in Node-02. Optimizing...",
                "Query processed. The result is within expected variance.",
                "Operator, I suggest running a full diagnostic on the bridge."
            ];
            const randomRes = responses[Math.floor(Math.random() * responses.length)];
            addMessage(randomRes, 'bot');
        }, 1000);
    });

    neuralInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') sendNeuralBtn.click();
    });

    // --- Log Stream Simulation ---
    const logStream = document.getElementById('logStream');
    const logMessages = [
        "Neural bridge established.",
        "Memory buffer allocated: 64GB.",
        "AI Core synchronized.",
        "Kernel patch 0x44 applied successfully.",
        "Monitoring telemetry stream...",
        "Symmetric encryption handshake complete.",
        "Node-01 heartbeat detected.",
        "Optimizingneural weights for Operator session."
    ];

    function addLog() {
        const time = new Date().toLocaleTimeString('en-US', { hour12: false });
        const msg = logMessages[Math.floor(Math.random() * logMessages.length)];
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        entry.textContent = `[${time}] ${msg}`;
        logStream.appendChild(entry);
        if (logStream.children.length > 20) {
            logStream.removeChild(logStream.firstChild);
        }
        logStream.scrollTop = logStream.scrollHeight;
    }
    setInterval(addLog, 5000);
});
