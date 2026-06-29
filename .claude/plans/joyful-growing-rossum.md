# Telegram Account Linking — Implementation Plan

## Context

The IGRIS backend (`backend/src/routes/telegram.js`) can already proactively notify a user via Telegram — `POST /api/telegram/notify` and `POST /api/telegram/broadcast` look up `user.telegramChatId || user.telegramId` and call `sendTelegramMessage`. **The columns already exist** on the `User` model (`backend/src/models/User.js:47-55`): `telegramId` BIGINT UNIQUE and `telegramChatId` STRING. The webhook flow even auto-populates `telegramChatId` the first time a user messages the bot (`telegram.js:111-113`).

What is missing: a way for a logged-in user to **claim** a Telegram account and have `telegramId` written to their row. Today there is no end-user surface for that — the Python bot has `/login email password` (`command_handlers.py:64`) and the Node webhook only matches on a pre-existing `telegramId` (`telegram.js:103`). Users can never get linked in the first place.

This plan adds a "Link Telegram" button to the mobile app's Profile screen. The user is already logged in; tapping the button opens a Telegram deep link; the bot verifies a signed token and writes the link. No DB schema changes, no password in Telegram, no new secrets on the client. `url_launcher` is already a dependency.

## Design (decided with the user)

- **Goal**: link an already-logged-in IGRIS account to a Telegram account so existing `notify`/`broadcast` endpoints start working.
- **Bot surface**: both the Python bot (`telegram_bot/`) and the Node webhook (`backend/src/routes/telegram.js`) handle the deep link. The Python bot round-trips to the Node backend; the Node webhook completes the link directly.
- **Verify method**: signed deep link `https://t.me/<bot>?start=link_<JWT>`. The JWT itself is the proof — no DB lookup needed to verify.

## Flow

1. Mobile (already logged in): tap **Link Telegram** on Profile.
2. Mobile `POST /api/telegram/link-token` with `Authorization: Bearer <auth_token>`. Backend mints a JWT `{ userId, type: "telegram_link", iat, exp }` signed with `JWT_SECRET` (HS256, 15 min).
3. Backend returns `{ token, deepLink: "https://t.me/<TELEGRAM_BOT_USERNAME>?start=link_<jwt>", expiresInSeconds: 900 }`.
4. Mobile opens the `deepLink` via `url_launcher` (Android/iOS hand it to the Telegram app).
5. User taps **Start** in Telegram. The bot receives `/start link_<jwt>`.
6. Bot calls `POST /api/telegram/complete-link` with `{ token, telegramUserId, chatId }` (no `Authorization` — the signed token is the credential). Backend verifies, writes `telegramId` + `telegramChatId`, returns `{ success: true }`.
7. Mobile polls `GET /api/telegram/link-status` every 3 s for up to 120 s. On `linked: true`, persist and pop back to Profile showing `Telegram: Linked`.

## Files to create

- `mobile_app/igris_mobile/lib/services/telegram_service.dart` — Dio client for `/api/telegram/{link-token,link-status,link}`. Mirror of `auth_service.dart` (uses `ConfigurationService().backendUrl`, 15 s timeouts).
- `mobile_app/igris_mobile/lib/screens/settings/telegram_link_screen.dart` — full-screen "open Telegram, waiting…" UI with polling timer, cancel, and retry.
- `telegram_bot/.env.example` — new (none exists today).

## Files to modify

### Backend
- `backend/.env.example` — add `TELEGRAM_BOT_USERNAME=`, `TELEGRAM_LINK_SECRET=` (optional, falls back to `JWT_SECRET`), `TELEGRAM_LINK_EXPIRES_IN=15m`.
- `backend/src/config/auth.js` — export `linkTokenSecret` and `linkTokenExpiresIn` reading those env vars.
- `backend/src/middleware/rateLimiter.js` — add `linkLimiter` (`windowMs: 10 min`, `max: 5`, `keyGenerator: req.userId ? \`user:${req.userId}\` : \`ip:${req.ip}\``, `validate: { keyGeneratorIpFallback: false }`).
- `backend/src/middleware/validate.js` — add Zod schemas:
  - `schemas.telegram.linkTokenRequest = z.object({})` (empty body)
  - `schemas.telegram.completeLinkRequest = z.object({ token: z.string().min(20).max(2000), telegramUserId: z.number().int().positive(), chatId: z.number().int().positive() }).strict()`
- `backend/src/routes/telegram.js`:
  - `POST /link-token` (new, above `/notify`): `authenticateToken` → `linkLimiter` → `validate(schemas.telegram.linkTokenRequest)`. 503 if `TELEGRAM_BOT_USERNAME` missing. `jwt.sign({ userId: req.userId, type: 'telegram_link' }, linkTokenSecret, { expiresIn: linkTokenExpiresIn, algorithm: 'HS256' })`. Return `{ token, deepLink, expiresInSeconds: 900 }`.
  - `GET /link-status` (new, auth): return `{ linked: !!user.telegramId && !!user.telegramChatId, telegramId: user.telegramId ? String(user.telegramId) : null }`.
  - `POST /complete-link` (new, **no auth**): `validate(schemas.telegram.completeLinkRequest)` → verify token, require `decoded.type === 'telegram_link'`, find user, `user.update({ telegramId: String(telegramUserId), telegramChatId: String(chatId) })`. 400 on bad/expired token, 404 on no user, 200 on success.
  - `DELETE /link` (new, auth): sets `telegramId` and `telegramChatId` to null for `req.userId`.
  - Extend `handleCommand` for `/start`: if `args.startsWith('link_')`, call `POST /complete-link` (webhook path does it locally instead, see below). On any failure, fall back to the existing welcome at `telegram.js:137`.
  - **Note**: the webhook is the canonical path. In the webhook's `handleMessage` (`telegram.js:97-128`), insert a branch for messages whose text starts with `/start link_`: parse the JWT, verify, look up the user, update `telegramId` + `telegramChatId`, reply with the success text. Do this **before** the existing auto-link check.

### Python bot
- `telegram_bot/igris_bot/utils/config.py` — add `self.telegram_bot_username` from `TELEGRAM_BOT_USERNAME`. Add `self.link_secret` (load `TELEGRAM_LINK_SECRET` falling back to `JWT_SECRET`) — used to pre-validate locally for a fast 400 on bad tokens; the backend's `complete-link` remains the source of truth.
- `telegram_bot/igris_bot/services/backend_service.py` — add `complete_telegram_link(token, telegram_user_id, chat_id)` calling `POST /api/telegram/complete-link` (no Authorization header).
- `telegram_bot/igris_bot/handlers/command_handlers.py` — extend `start()`: if `context.args[0].startswith('link_')`, extract JWT, call `complete_telegram_link`, reply success/failure. Otherwise keep current welcome.

### Mobile
- `mobile_app/igris_mobile/.env.example` — add `IGRIS_TELEGRAM_BOT_USERNAME=` and a comment with the build example showing the new `--dart-define`.
- `mobile_app/igris_mobile/lib/services/configuration_service.dart` — add `String get telegramBotUsername => const String.fromEnvironment('IGRIS_TELEGRAM_BOT_USERNAME', defaultValue: '');`. In `initialize()`, throw a `StateError` (matching the existing pattern at line 38) if empty.
- `mobile_app/igris_mobile/lib/screens/settings/profile_screen.dart`:
  - In `_loadProfile` (line 50), also read `'telegram_linked_id'` from secure storage into `_tgLinkedId` (bool: `id != null`) and `_tgLinkedIdValue` (string).
  - After the Gender block (line 182), before the column closes, add a `Container` mirroring the Gender block styling: icon `Icons.telegram`, title "Telegram", subtitle `Telegram: ${_tgLinkedIdValue ?? 'Not linked'}`, with a trailing `TextButton` that says **Link** or **Unlink**. **Link** pushes `TelegramLinkScreen`; **Unlink** calls `_unlink()` which POSTs `DELETE /api/telegram/link` and clears the secure storage key.
  - Reload `_loadProfile()` on `Navigator.pop` result.
- `mobile_app/igris_mobile/pubspec.yaml` — **no change** (`url_launcher: ^6.2.0` is already present at line 55).
- `mobile_app/igris_mobile/android/app/src/main/AndroidManifest.xml` — **no change** for the bot's `t.me` URL (Android hands it to the Telegram app). Optionally add a `igris://` intent filter for a future "Return to App" button; not required for this plan.

## JWT shape (link token)

- Algorithm: `HS256` (matches `backend/src/middleware/auth.js`).
- Signing key: `process.env.TELEGRAM_LINK_SECRET ?? process.env.JWT_SECRET`.
- Expiry: `process.env.TELEGRAM_LINK_EXPIRES_IN ?? '15m'`.
- Claims: `{ userId: <uuid>, type: 'telegram_link', iat, exp }`.
- Transport: URL-encoded as `https://t.me/<TELEGRAM_BOT_USERNAME>?start=link_<jwt>` (well under the 2 KB t.me limit).

## Security notes (CLAUDE.md compliance)

- `TELEGRAM_BOT_TOKEN` stays server-side in `backend/.env` and `telegram_bot/.env`; never touches the client.
- `TELEGRAM_BOT_USERNAME` is **public** (BotFather-assigned, identifies the bot to users) — safe to ship in the APK via `--dart-define`. Treat it as a publishable key; comment that in `.env.example`.
- `POST /link-token` is rate-limited per user (`linkLimiter`); `complete-link` is one-shot per JWT (15 min expiry) and idempotent.
- No stack traces leak: errors funnel through the existing `errorHandler` (`backend/src/middleware/errorHandler.js`) and the existing `errorHandler` in the Python bot's `error_handler` (`bot.py:55`).
- `Authorization` is never sent to `/complete-link`; the signed link token is the only credential. After the link is written, `/link-status` and future `notify` calls require the user's normal JWT.

## Verification (end-to-end manual test)

1. **Backend**: set `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `JWT_SECRET` in `backend/.env`. `cd backend && npm start`. Confirm `:5000` up.
2. **Bot** (Node webhook path): same envs; the webhook in `telegram.js` handles the link without needing the Python bot. **Bot** (Python long-poll path): set matching `TELEGRAM_LINK_SECRET` in `telegram_bot/.env`. `cd telegram_bot && python -m igris_bot.bot` — confirm polling.
3. **Mobile**: `flutter run --dart-define=IGRIS_BACKEND_URL=http://10.0.2.2:5000/api --dart-define=IGRIS_TELEGRAM_BOT_USERNAME=<your_bot>`.
4. Log in to a test account. Open **Settings → Profile** — confirm "Telegram: Not linked".
5. Tap **Link**. App calls `POST /api/telegram/link-token`, receives a `deepLink`, opens Telegram to the bot with `?start=link_<jwt>`.
6. In Telegram, tap **Start**. Bot/webhook verifies the JWT and replies "✅ Your IGRIS account is now linked to Telegram."
7. Within ~3 s, the mobile poller resolves `linked=true`, persists secure storage, and pops back to Profile showing the linked status.
8. **Proactive notify**: `curl -X POST $BACKEND/api/telegram/notify -H "Authorization: Bearer $USER_TOKEN" -H "Content-Type: application/json" -d '{"message":"hello from IGRIS"}'` — confirm the `🤖 IGRIS` message arrives.
9. **Negative tests**:
   - Wait >15 min between steps 5 and 6 → 400 "Token expired" + mobile "Link timed out".
   - Hit `POST /api/telegram/link-token` 6× in 10 min → 429 on the 6th, proving `linkLimiter` per userId.
   - **Unlink**: tap "Unlink" on Profile → row clears; subsequent `notify` returns 404.

## Critical files

- `backend/src/routes/telegram.js` — main surface; add 4 routes + extend `handleMessage`/`handleCommand`.
- `backend/src/middleware/rateLimiter.js` — add `linkLimiter`.
- `backend/src/middleware/validate.js` — add 2 Zod schemas.
- `telegram_bot/igris_bot/handlers/command_handlers.py` — extend `start()`.
- `telegram_bot/igris_bot/services/backend_service.py` — add `complete_telegram_link`.
- `mobile_app/igris_mobile/lib/screens/settings/profile_screen.dart` — add Telegram row.
- `mobile_app/igris_mobile/lib/screens/settings/telegram_link_screen.dart` — new screen.
- `mobile_app/igris_mobile/lib/services/telegram_service.dart` — new service.
- `mobile_app/igris_mobile/lib/services/configuration_service.dart` — add `telegramBotUsername` getter + init check.
