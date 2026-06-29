# IGRIS Backend

This is the backend for the IGRIS (Intelligent General-purpose Robotic Intelligence System) personal AI agent.

## Features

- User authentication and management
- Attendance automation for MyNiat college system
- Voice processing with Gemini AI and Murf.ai TTS
- Tool integration (messaging, app control, calling, web search, file operations)
- Telegram bot integration
- Scheduled tasks for automated attendance marking
- Notification system (WhatsApp, Telegram, Email, in-app)
- Real-time communication with Socket.IO
- Secure data storage with Supabase/PostgreSQL

## Setup Instructions

### Prerequisites

- Node.js (v18 or higher)
- PostgreSQL database
- Supabase account (for storage and authentication)
- Gemini API key (from Google AI Studio)
- Murf.ai API key (for text-to-speech)
- Telegram Bot token (optional, for Telegram integration)
- Twilio account SID and auth token (optional, for WhatsApp/SMS)

### Installation

1. Clone the repository
2. Navigate to the backend directory:
   ```bash
   cd backend
   ```

3. Install dependencies:
   ```bash
   npm install
   ```

4. Create a `.env` file based on `.env.example`:
   ```bash
   cp .env.example .env
   ```

5. Edit the `.env` file and fill in your actual values:
   - Database connection details
   - Supabase URL and keys
   - JWT secrets
   - API keys for external services
   - Telegram bot token (if using)
   - Twilio credentials (if using WhatsApp/SMS)

6. Initialize the database:
   ```bash
   # If using Supabase, tables will be created automatically via migrations
   # Otherwise, run your PostgreSQL setup script
   ```

### Development

To start the development server:
```bash
npm run dev
```

This will start the server with nodemon for automatic restarts on file changes.

To start the production server:
```bash
npm start
```

### API Endpoints

#### Authentication
- `POST /api/auth/register` - Register a new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/refresh-token` - Refresh access token
- `POST /api/auth/logout` - Logout user
- `GET /api/auth/profile` - Get user profile (protected)

#### Users
- `PUT /api/users/profile` - Update user profile (protected)
- `PUT /api/users/api-keys` - Update API keys (protected)
- `PUT /api/users/myniat` - Update MyNiat credentials (protected)
- `GET /api/users/dashboard` - Get user dashboard data (protected)

#### Attendance
- `GET /api/attendance/current-session` - Get current session info (protected)
- `POST /api/attendance/mark` - Mark attendance for current session (protected)
- `GET /api/attendance/history` - Get attendance history (protected)
- `GET /api/attendance/stats` - Get attendance statistics (protected)

#### Tools
- `POST /api/tools/send-message` - Send message via WhatsApp/SMS/Telegram/Email (protected)
- `POST /api/tools/open-app` - Open application on device (protected)
- `POST /api/tools/make-call` - Make phone call (protected)
- `POST /api/tools/web-search` - Perform web search (protected)
- `POST /api/tools/file-operation` - Perform file operations (protected)

#### Voice
- `POST /api/voice/process` - Process voice input with Gemini (protected)
- `POST /api/voice/synthesize` - Synthesize speech with Murf.ai (protected)
- `POST /api/voice/wake-word` - Detect wake word in audio (protected)

#### Telegram
- `POST /api/telegram/webhook` - Receive updates from Telegram Bot (public)
- `GET /api/telegram/set-webhook` - Set Telegram webhook (protected)
- `GET /api/telegram/delete-webhook` - Delete Telegram webhook (protected)

#### Health
- `GET /health` - Health check endpoint

### Database Schema

The backend uses PostgreSQL with the following main tables:

- `users` - User information and API keys
- `attendance` - Attendance records
- `tool_usages` - Log of tool usage by users
- (Additional tables can be added as needed)

### Security Features

- JWT-based authentication
- Password hashing with bcrypt
- Helmet.js for security headers
- CORS protection
- Input validation
- Environment variable configuration
- Secure API key storage (encrypted in database)

### Environment Variables

See `.env.example` for a complete list of environment variables.

### Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request

### License

This project is proprietary and confidential. All rights reserved.