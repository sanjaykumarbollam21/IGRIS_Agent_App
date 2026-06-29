# IGRIS System Deployment Guide

This guide explains how to deploy and run the complete IGRIS (Intelligent General-purpose Robotic Intelligence System) which consists of:
1. Backend Server (Node.js)
2. Mobile Application (Flutter)
3. Desktop Application (Tauri)
4. Telegram Bot Integration

## Overview

IGRIS is a modular system where each component can be deployed independently, but they work best when all components are connected to the same backend server.

## Prerequisites

Before deploying any component, ensure you have:

### General Prerequisites
- Git (for cloning repositories)
- Docker and Docker Compose (optional, for easy backend deployment)
- A domain name or static IP for production deployment (optional)

### Backend Prerequisites
- Node.js v18 or higher
- PostgreSQL database
- Supabase account (for file storage)
- Gemini API key (from Google AI Studio)
- Murf.ai API key (for text-to-speech)
- Telegram Bot token (optional, for Telegram integration)
- Twilio account SID and auth token (optional, for WhatsApp/SMS)

### Mobile App Prerequisites
- Flutter SDK v3.0.0 or higher
- Android Studio (for Android development)
- Xcode (for iOS development, macOS only)
- Physical devices or emulators/simulators for testing

### Desktop App Prerequisites
- Rust v1.65 or higher
- Node.js v18 or higher
- Tauri CLI
- Platform-specific build tools:
  - Windows: Visual Studio Build Tools
  - macOS: Xcode command-line tools
  - Linux: WebKitGTK development libraries

### Telegram Bot Prerequisites
- Python 3.8 or higher
- pip package manager
- Telegram Bot Token (from @BotFather)

## Deployment Steps

### Step 1: Deploy the Backend Server

The backend is the core component that all other components connect to.

#### Option A: Manual Deployment

1. Clone the repository and navigate to the backend directory:
   ```bash
   git clone <repository-url>
   cd IGRIS_AGENT/backend
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Create a `.env` file based on `.env.example`:
   ```bash
   cp .env.example .env
   ```

4. Edit the `.env` file and fill in your actual values:
   - Database connection details
   - Supabase URL and keys
   - JWT secrets
   - API keys for external services
   - Telegram bot token (if using)
   - Twilio credentials (if using WhatsApp/SMS)

5. Initialize the database:
   ```bash
   # The database will be initialized automatically on first startup
   # Or you can run migrations if you have them set up
   ```

6. Start the backend server:
   ```bash
   # Development mode
   npm run dev
   
   # Production mode
   npm start
   ```

#### Option B: Docker Deployment

1. Ensure Docker and Docker Compose are installed
2. Navigate to the backend directory:
   ```bash
   cd IGRIS_AGENT/backend
   ```

3. Create a `.env` file based on `.env.example` (same as manual deployment)
4. Start the backend with PostgreSQL using Docker Compose:
   ```bash
   docker-compose up -d
   ```

5. The backend will be available at `http://localhost:5000`

### Step 2: Deploy the Mobile Application

1. Navigate to the mobile app directory:
   ```bash
   cd IGRIS_AGENT/mobile_app/igris_mobile
   ```

2. Get Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Configure the backend URL:
   - Open `lib/services/auth_service.dart`
   - Update the base URL to point to your backend:
     - For emulator: `http://10.0.2.2:5000/api`
     - For physical device: Use your computer's IP address
     - For web: Use your domain or public IP

4. Run the application:
   ```bash
   # Android emulator or device
   flutter run
   
   # iOS simulator or device
   flutter run
   
   # Web browser
   flutter run -d chrome
   ```

5. Build for release:
   ```bash
   # Android APK
   flutter build apk --release
   
   # iOS IPA
   flutter build ios --release
   
   # Web build
   flutter build web
   ```

### Step 3: Deploy the Desktop Application

1. Navigate to the desktop app directory:
   ```bash
   cd IGRIS_AGENT/desktop_app/igris_desktop
   ```

2. Install Rust dependencies:
   ```bash
   cargo fetch
   ```

3. Configure the backend URL:
   - Open `src/main.rs`
   - Update the API calls to point to your backend:
     - Change `http://localhost:5000/api` to your backend URL
     - For example: `http://your-domain.com:5000/api` or `http://192.168.1.100:5000/api`

4. Build and run the application:
   ```bash
   # Development mode
   tauri dev
   
   # Production build
   tauri build
   ```

5. The built application will be available in:
   - `src-tauri/target/release/bundle/`

### Step 4: Deploy the Telegram Bot

1. Navigate to the Telegram bot directory:
   ```bash
   cd IGRIS_AGENT/telegram_bot
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Create a `.env` file:
   ```
   TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here
   BACKEND_URL=http://localhost:5000/api
   DEBUG=false
   LOG_LEVEL=INFO
   ```

4. Run the bot:
   ```bash
   python bot.py
   ```

5. The bot will start polling for updates from Telegram

## Configuration Details

### Backend Environment Variables

See `backend/.env.example` for a complete list. Key variables include:

- `PORT`: Server port (default: 5000)
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`: PostgreSQL connection
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`: Supabase storage
- `JWT_SECRET`, `JWT_EXPIRES_IN`: Authentication settings
- `REFRESH_TOKEN_SECRET`, `REFRESH_TOKEN_EXPIRES_IN`: Refresh token settings
- `GEMINI_API_KEY_DEFAULT`, `MURF_API_KEY_DEFAULT`: Default API keys (users override in app)
- `TELEGRAM_BOT_TOKEN`: For Telegram bot integration
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_NUMBER`: For WhatsApp/SMS

### Mobile App Configuration

The mobile app gets its configuration from:
- Backend API (user-specific settings like API keys)
- Local storage (device preferences)
- Hardcoded values in service classes (backend URLs)

### Desktop App Configuration

Similar to mobile app, the desktop app gets configuration from:
- Backend API
- Local storage
- Hardcoded values in `src/main.rs`

### Telegram Bot Configuration

See `telegram_bot/requirements.txt` for dependencies and `telegram_bot/.env` for environment variables.

## Verification

After deploying each component, verify that:

1. **Backend is running**: Visit `http://your-backend-url:5000/health` should return `{"status":"OK"}`
2. **Mobile app connects**: Launch the app and verify it can reach the backend
3. **Desktop app connects**: Launch the app and verify backend connection status
4. **Telegram bot responds**: Send `/start` to your bot and verify it responds

## Scaling and Production Considerations

### Database
- Use managed PostgreSQL service (AWS RDS, Google Cloud SQL, etc.) for production
- Configure backups and replication
- Monitor performance and scale as needed

### Backend
- Use a process manager like PM2 for Node.js in production
- Deploy behind a reverse proxy (NGINX) for SSL termination
- Enable caching (Redis) for frequently accessed data
- Use load balancing for high availability

### Storage
- Configure Supabase buckets for file storage
- Set up CDN for serving static assets
- Implement lifecycle policies for old files

### Monitoring
- Set up logging aggregation (ELK stack, etc.)
- Monitor API response times and error rates
- Track user engagement and feature usage
- Set up alerts for system health

### Security
- Enable HTTPS everywhere
- Use secure cookies and HTTP-only flags
- Implement rate limiting on API endpoints
- Regularly update dependencies
- Conduct security audits

## Troubleshooting

### Common Backend Issues
- **Database connection failed**: Check credentials and network access
- **Supabase connection failed**: Verify URL and keys are correct
- **JWT authentication failed**: Check secret key and token expiry
- **External API failures**: Verify API keys and service status

### Common Mobile App Issues
- **Backend connection failed**: Check URL and network permissions
- **Missing permissions**: Ensure all required permissions are granted in AndroidManifest.xml/Info.plist
- **Build failures**: Run `flutter clean` and `flutter pub get` again
- **Performance issues**: Enable profiling and optimize widget tree

### Common Desktop App Issues
- **Backend connection failed**: Verify URL and firewall settings
- **Tauri build errors**: Ensure Rust toolchain is up to date
- **Missing dependencies**: Install platform-specific build tools
- **Security restrictions**: Adjust allowlist in tauri.conf.json as needed

### Common Telegram Bot Issues
- **Bot not responding**: Check that the script is running and has network access
- **Invalid token**: Verify your TELEGRAM_BOT_TOKEN is correct
- **Backend connection errors**: Ensure the IGRIS backend is running and accessible
- **Missing dependencies**: Reinstall with `pip install -r requirements.txt`

## Updates and Maintenance

### Backend Updates
1. Pull latest code: `git pull`
2. Install new dependencies: `npm install`
3. Run database migrations if needed: `npx prisma migrate deploy` (if using Prisma)
4. Restart the server: `npm run restart` or restart Docker container

### Mobile App Updates
1. Pull latest code: `git pull`
2. Get new dependencies: `flutter pub get`
3. Increment version number in pubspec.yaml
4. Build and distribute update

### Desktop App Updates
1. Pull latest code: `git pull`
2. Fetch new Rust dependencies: `cargo fetch`
3. Rebuild: `tauri build`
4. Distribute updated installer

### Telegram Bot Updates
1. Pull latest code: `git pull`
2. Install new dependencies: `pip install -r requirements.txt`
3. Restart the bot: `pkill -f bot.py && python bot.py`

## Support

For issues and questions:
1. Check the logs of each component
2. Verify network connectivity between components
3. Ensure all required API keys and credentials are configured
4. Consult the individual README files in each component directory
5. For backend issues, check both backend logs and database logs

## Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   Mobile App    │    │  Desktop App     │    │  Telegram Bot    │
│ (Flutter)       │    │ (Tauri)          │    │ (Python)         │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬────────┘
          │                      │                      │
          │   HTTPS/WebSocket    │   HTTPS/WebSocket    │   HTTPS
          ▼                      ▼                      ▼
                    ┌─────────────────────────────┐
                    │      IGRIS Backend          │
                    │  (Node.js + PostgreSQL)     │
                    │                             │
                    │  ┌─────────────────────┐    │
                    │  │   Supabase Storage  │    │
                    │  └─────────────────────┘    │
                    │  ┌─────────────────────┐    │
                    │  │   External APIs     │    │
                    │  │ (Gemini, Murf.ai,   │    │
                    │  │  Twilio, etc.)      │    │
                    │  └─────────────────────┘    │
                    └─────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  PostgreSQL Database│
                    │  (Users, Attendance,│
                    │   Tool Usage, etc.) │
                    └─────────────────────┘
```

## License

This project is proprietary and confidential. All rights reserved.