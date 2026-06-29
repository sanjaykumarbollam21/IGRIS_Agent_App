#!/bin/bash
BASE=http://localhost:8080

# Login
TOKEN=$(curl -s -X POST $BASE/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@igris.ai","password":"Admin123!"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

echo "Token: ${TOKEN:0:20}..."

# Test image generation
echo ""
echo "=== Testing Image Generation ==="
RESULT=$(curl -s -X POST $BASE/api/ai/generate-image \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"a cute robot","style":"digital_art"}')

# Check result
echo "$RESULT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if d.get('success'):
        img = d.get('imageData','')
        print(f'SUCCESS! Image data length: {len(img)} chars')
        print(f'Prompt used: {d.get(\"prompt\",\"?\")}')
    else:
        print(f'FAILED: {d.get(\"error\",\"?\")} - {d.get(\"message\",\"?\")}')
except Exception as e:
    print(f'Parse error: {e}')
" 2>/dev/null
