document.addEventListener('DOMContentLoaded', () => {
    const authOverlay = document.getElementById('authOverlay');
    const appShell = document.getElementById('appShell');
    const authForm = document.getElementById('authForm');
    const logoutBtn = document.getElementById('logoutBtn');
    const navItems = document.querySelectorAll('.nav-item');
    const pageContent = document.getElementById('pageContent');
    const pageHeading = document.getElementById('pageHeading');
    const currentTimeEl = document.getElementById('currentTime');
    const activityList = document.getElementById('activityList');

    // --- Auth Logic ---
    authForm.addEventListener('submit', (e) => {
        e.preventDefault();
        authOverlay.classList.add('hidden');
        appShell.classList.remove('hidden');
        localStorage.setItem('igris_sync_auth', 'true');
    });

    logoutBtn.addEventListener('click', () => {
        localStorage.removeItem('igris_sync_auth');
        appShell.classList.add('hidden');
        authOverlay.classList.remove('hidden');
    });

    if (localStorage.getItem('igris_sync_auth') === 'true') {
        authOverlay.classList.add('hidden');
        appShell.classList.remove('hidden');
    }

    // --- Navigation ---
    function navigateTo(pageId) {
        // Update nav state
        navItems.forEach(item => {
            item.classList.toggle('active', item.getAttribute('data-page') === pageId);
        });

        // Update page visibility
        document.querySelectorAll('.page').forEach(page => {
            page.classList.toggle('active', page.id === `page-${pageId}`);
        });

        // Update header
        const activeNav = document.querySelector(`.nav-item[data-page="${pageId}"]`);
        pageHeading.textContent = activeNav ? activeNav.querySelector('.label').textContent : 'Dashboard';
    }

    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            navigateTo(item.getAttribute('data-page'));
        });
    });

    // Quick Action buttons also trigger navigation
    document.querySelectorAll('.action-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            navigateTo(btn.getAttribute('data-page'));
        });
    });

    // --- Utilities ---
    function updateTime() {
        const now = new Date();
        currentTimeEl.textContent = now.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
        });
    }
    setInterval(updateTime, 1000);
    updateTime();

    // --- Dashboard Activity Simulation ---
    const mockActivities = [
        { action: "AI Chat: Analysis completed", time: "2m ago", icon: "✨" },
        { action: "Device: Primary Mobile connected", time: "15m ago", icon: "📱" },
        { action: "Calendar: Meeting at 3 PM", time: "1h ago", icon: "📅" },
        { action: "Sync: 142 files updated", time: "3h ago", icon: "☁️" },
        { action: "Auth: New login from Chrome", time: "5h ago", icon: "🔑" },
    ];

    function renderActivity() {
        activityList.innerHTML = mockActivities.map(act => `
            <div class="activity-item">
                <span class="act-icon">${act.icon}</span>
                <span class="act-text">${act.action}</span>
                <span class="time">${act.time}</span>
            </div>
        `).join('');
    }
    renderActivity();

    // --- AI Chat Logic ---
    const aiInput = document.getElementById('aiInput');
    const aiSend = document.getElementById('aiSend');
    const aiMessages = document.getElementById('aiMessages');

    function addAiMessage(text, sender = 'bot') {
        const msgDiv = document.createElement('div');
        msgDiv.className = `message ${sender}`;
        msgDiv.innerHTML = `<div class="bubble">${text}</div>`;
        aiMessages.appendChild(msgDiv);
        aiMessages.scrollTop = aiMessages.scrollHeight;
    }

    aiSend.addEventListener('click', () => {
        const text = aiInput.value.trim();
        if (!text) return;

        addAiMessage(text, 'user');
        aiInput.value = '';

        setTimeout(() => {
            const responses = [
                "I've analyzed the data from your mobile device. Everything looks correct.",
                "Executing a web search for the latest updates... One moment.",
                "Based on your calendar, you have a conflict at 4 PM. Should I reschedule?",
                "Image generated successfully. You can find it in your mobile gallery.",
                "I'm now monitoring your device's Ringer Mode via the sync bridge."
            ];
            addAiMessage(responses[Math.floor(Math.random() * responses.length)], 'bot');
        }, 800);
    });

    aiInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') aiSend.click();
    });

    // --- Capability Tab switching (Simple) ---
    document.querySelectorAll('.cap-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.cap-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            // In a real app, this would change the chat mode or input type
        });
    });
});
