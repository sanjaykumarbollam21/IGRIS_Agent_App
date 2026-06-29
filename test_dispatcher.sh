#!/bin/bash
cd /home/ubuntu/igris_backend
sudo docker run --rm \
  --env-file /home/ubuntu/igris_backend/.env \
  -v /home/ubuntu/igris_backend:/app \
  igris_backend-backend \
  node -e "
const d = require('./src/services/dispatcherService');
d.init({telegram: process.env.TELEGRAM_BOT_TOKEN, whatsapp: {sid: '', token: ''}, email: ''})
  .then(() => console.log('DISPATCHER OK'))
  .catch(e => console.error('DISPATCHER ERROR:', e.message, e.stack));
" 2>&1 | tail -20
