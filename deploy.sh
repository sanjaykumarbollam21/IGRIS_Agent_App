#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH=$PATH:/usr/local/bin:/usr/bin

echo "=== Node: $(node --version) ==="
echo "=== npm: $(npm --version) ==="
echo "=== PM2 location: $(which pm2) ==="

cd /home/ubuntu/igris_backend
echo "=== Installing dependencies ==="
npm install --silent

echo "=== Restarting PM2 ==="
pm2 restart igris_backend --update-env || pm2 start src/server.js --name igris_backend

echo "=== PM2 Status ==="
pm2 status

echo "=== Recent Logs ==="
pm2 logs igris_backend --lines 20 --nostream
