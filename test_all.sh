#!/bin/bash
BASE=http://localhost:8080

echo "=== 1. Health ==="
curl -s $BASE/health

echo ""
echo "=== 2. Login ==="
LOGIN_RESP=$(curl -s -X POST $BASE/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@igris.ai","password":"Admin123!"}')
echo "$LOGIN_RESP" | head -c 200

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo ""
  echo "LOGIN FAILED - cannot continue"
  exit 1
fi
echo ""
echo "TOKEN OK: ${TOKEN:0:30}..."

AUTH="Authorization: Bearer $TOKEN"

echo ""
echo "=== 3. Dashboard ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/users/dashboard" | tail -c 200

echo ""
echo "=== 4. Settings ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/settings" | tail -c 200

echo ""
echo "=== 5. Conversations ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/conversations/sessions" | tail -c 200

echo ""
echo "=== 6. Automations ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/automations" | tail -c 200

echo ""
echo "=== 7. Gmail Status ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/gmail/status" | tail -c 200

echo ""
echo "=== 8. Calendar Status ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/calendar/status" | tail -c 200

echo ""
echo "=== 9. Calendar Test ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/calendar/test" | tail -c 200

echo ""
echo "=== 10. System Status ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/system/status" | tail -c 200

echo ""
echo "=== 11. Voice Settings ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/voice/settings" | tail -c 200

echo ""
echo "=== 12. AI Chat ==="
curl -s -w "\nHTTP: %{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"message":"hello","sessionId":"test123"}' "$BASE/api/ai/chat" | tail -c 300

echo ""
echo "=== 13. 404 Test ==="
curl -s -w "\nHTTP: %{http_code}" -H "$AUTH" "$BASE/api/doesnotexist" | tail -c 200

echo ""
echo "=== ALL TESTS DONE ==="
