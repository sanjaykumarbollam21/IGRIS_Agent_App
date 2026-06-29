#!/bin/bash
BASE=http://localhost:8080

echo "=========================================="
echo "  IGRIS Complete System Audit"
echo "  $(date)"
echo "=========================================="

# Login
LOGIN_RESP=$(curl -s -X POST $BASE/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@igris.ai","password":"Admin123!"}')
TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "❌ LOGIN FAILED"
  echo "$LOGIN_RESP"
  exit 1
fi
echo "✅ Login: OK (token: ${TOKEN:0:20}...)"
AUTH="Authorization: Bearer $TOKEN"

# Test each endpoint
test_endpoint() {
  local name=$1
  local method=$2
  local url=$3
  local data=$4
  local expected=$5
  
  if [ "$method" = "GET" ]; then
    RESP=$(curl -sf -w "\n%{http_code}" -H "$AUTH" "$BASE$url" 2>/dev/null)
  else
    RESP=$(curl -sf -w "\n%{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" -d "$data" "$BASE$url" 2>/dev/null)
  fi
  
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | head -n -1)
  
  if [ "$CODE" = "$expected" ] || [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    echo "✅ $name: HTTP $CODE"
  else
    echo "❌ $name: HTTP $CODE — $(echo "$BODY" | head -c 120)"
  fi
}

echo ""
echo "── Core API ──────────────────────────────"
test_endpoint "Health" GET "/health" "" "200"
test_endpoint "Dashboard" GET "/api/users/dashboard" "" "200"
test_endpoint "Settings" GET "/api/settings" "" "200"

echo ""
echo "── AI Features ─────────────────────────────"
test_endpoint "Chat" POST "/api/ai/chat" '{"message":"hi","sessionId":"test1"}' "200"
test_endpoint "Image Gen" POST "/api/ai/generate-image" '{"prompt":"a cat"}' "200"
test_endpoint "Transcribe" POST "/api/ai/transcribe" '{"audioData":"dGVzdA=="}' "200"
test_endpoint "Analyze Image" POST "/api/ai/analyze-image" '{"imageData":"dGVzdA=="}' "200"

echo ""
echo "── Communication ──────────────────────────"
test_endpoint "Gmail Status" GET "/api/gmail/status" "" "200"
test_endpoint "Calendar Status" GET "/api/calendar/status" "" "200"
test_endpoint "Calendar Test" GET "/api/calendar/test" "" "200"

echo ""
echo "── Tasks & Automation ────────────────────"
test_endpoint "Automations" GET "/api/automations" "" "200"
test_endpoint "Conversations" GET "/api/conversations/sessions" "" "200"

echo ""
echo "── Device Control ────────────────────────"
test_endpoint "System Status" GET "/api/system/status" "" "200"
test_endpoint "System Command" POST "/api/system/command" '{"action":"lock"}' "200"

echo ""
echo "── Socket.IO ─────────────────────────────"
# Check if Socket.IO is accepting connections
SOCKET_CHECK=$(curl -sf "$BASE/socket.io/?EIO=4&transport=polling" 2>/dev/null)
if echo "$SOCKET_CHECK" | grep -q "sid"; then
  echo "✅ Socket.IO: Accepting connections"
else
  echo "❌ Socket.IO: Not responding"
fi

echo ""
echo "── ENV Keys Status ───────────────────────"
echo "GEMINI_API_KEY_DEFAULT: $(if [ -n "$GEMINI_API_KEY_DEFAULT" ]; then echo 'SET'; else echo 'EMPTY (users must set personal key)'; fi)"
echo "GMAIL_CLIENT_ID: $(if [ -n "$GMAIL_CLIENT_ID" ]; then echo 'SET'; else echo 'EMPTY (Gmail OAuth disabled)'; fi)"
echo "TELEGRAM_BOT_TOKEN: $(if [ -n "$TELEGRAM_BOT_TOKEN" ]; then echo 'SET'; else echo 'EMPTY'; fi)"

echo ""
echo "=========================================="
echo "  Audit Complete"
echo "=========================================="
