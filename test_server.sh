#!/bin/bash
cd /home/ubuntu/igris_backend

echo "=== Testing server startup ==="
sudo docker run --rm \
  --network igris_backend_default \
  --env-file /home/ubuntu/igris_backend/.env \
  -v /home/ubuntu/igris_backend/src:/app/src \
  -v /home/ubuntu/igris_backend/node_modules:/app/node_modules \
  igris_backend-backend \
  node src/server.js 2>&1 &

SERVER_PID=$!
sleep 12
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null
echo "=== Done ==="
