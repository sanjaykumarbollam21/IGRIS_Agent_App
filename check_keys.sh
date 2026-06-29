#!/bin/bash
# Check if user has Gemini key in database
sudo docker exec igris_backend-backend-1 node -e "
const { User } = require('./src/models');
(async () => {
  try {
    const users = await User.findAll();
    users.forEach(u => {
      console.log('User:', u.email);
      console.log('  geminiApiKey:', u.geminiApiKey ? 'SET (' + u.geminiApiKey.substring(0,8) + '...)' : 'NOT SET');
    });
  } catch(e) { console.log('Error:', e.message); }
  process.exit(0);
})();
"
