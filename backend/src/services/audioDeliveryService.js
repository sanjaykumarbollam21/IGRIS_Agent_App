const express = require('express');
const path = require('path');
const fs = require('fs');

/**
 * Audio Delivery Service
 * Handles serving and managing generated audio files
 */
class AudioDeliveryService {
  constructor() {
    this.storagePath = path.join(__dirname, '../../uploads/voice');
    this.ensureStorageExists();
  }

  ensureStorageExists() {
    if (!fs.existsSync(this.storagePath)) {
      fs.mkdirSync(this.storagePath, { recursive: true });
    }
  }

  /**
   * Get local path for a remote audio URL or ID
   * @param {string} audioUrl
   * @returns {string} local path
   */
  async getLocalAudioPath(audioUrl) {
    // In a real implementation, this would download the file from Murf.ai
    // and cache it locally to avoid repeated API calls and latency.
    const fileName = `cached_${Date.now()}.mp3`;
    const localPath = path.join(this.storagePath, fileName);

    // Simulation: Create an empty file to represent a cached audio asset
    fs.writeFileSync(localPath, 'simulated audio content');

    return localPath;
  }

  /**
   * Clean up old audio files to save space
   */
  async cleanupOldFiles(maxAgeDays = 1) {
    const files = fs.readdirSync(this.storagePath);
    const now = Date.now();

    files.forEach(file => {
      const filePath = path.join(this.storagePath, file);
      const stats = fs.statSync(filePath);
      if (now - stats.mtimeMs > maxAgeDays * 24 * 60 * 60 * 1000) {
        fs.unlinkSync(filePath);
      }
    });
  }
}

module.exports = new AudioDeliveryService();
