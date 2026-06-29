const logger = require('../utils/logger');
const { User } = require('../models');

/**
 * MyNiat Attendance Automation Service
 *
 * This service handles the automated marking of attendance on the MyNiat college portal.
 * It uses a headless browser to perform the login and interaction.
 */
class MyNiatService {
  constructor() {
    this.portalUrl = process.env.MYNIAT_PORTAL_URL || 'https://myniat.college.edu'; // Placeholder
    this.selectors = {
      usernameField: '#username',
      passwordField: '#password',
      loginButton: 'button[type="submit"]',
      attendanceTab: 'a[href*="attendance"]',
      markButton: 'button.mark-attendance',
      successMessage: '.alert-success',
    };
  }

  /**
   * Mark attendance for a specific user.
   * @param {string} userId - The ID of the user.
   * @returns {Promise<{success: boolean, message: string}>}
   */
  async markAttendance(userId) {
    const user = await User.findByPk(userId);
    if (!user || !user.myniatUsername || !user.myniatPassword) {
      throw new Error('MyNiat credentials not configured for this user.');
    }

    logger.info({ event: 'myniat_automation_start', userId });
    const puppeteer = require('puppeteer');
    const browser = await puppeteer.launch({
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    try {
      const page = await browser.newPage();

      // 1. Navigate to Login Page
      await page.goto(this.portalUrl, { waitUntil: 'networkidle2' });
      logger.info(`[MyNiat] Navigated to ${this.portalUrl}`);

      // 2. Perform Login
      await page.type(this.selectors.usernameField, user.myniatUsername);
      await page.type(this.selectors.passwordField, user.myniatPassword);
      await page.click(this.selectors.loginButton);
      await page.waitForNavigation({ waitUntil: 'networkidle2' });
      logger.info(`[MyNiat] Logged in as ${user.myniatUsername}`);

      // 3. Navigate to Attendance Section
      await page.click(this.selectors.attendanceTab);
      await page.waitForNavigation({ waitUntil: 'networkidle2' });

      // 4. Mark Attendance
      // This part depends on the actual portal's UI.
      // We attempt to find the "Mark Attendance" button for the current session.
      const markBtn = await page.$(this.selectors.markButton);
      if (!markBtn) {
        throw new Error('Could not find the "Mark Attendance" button. Session might not be open.');
      }

      await markBtn.click();

      // 5. Verify Success
      const success = await page.waitForSelector(this.selectors.successMessage, { timeout: 5000 })
        .then(() => true)
        .catch(() => false);

      if (!success) {
        throw new Error('Attendance marked but no success message was found.');
      }

      logger.info({ event: 'myniat_automation_success', userId });
      return { success: true, message: 'Attendance marked successfully on MyNiat portal.' };

    } catch (error) {
      logger.error({ event: 'myniat_automation_error', userId, error: error.message });
      return { success: false, message: error.message };
    } finally {
      await browser.close();
    }
  }
}

module.exports = new MyNiatService();
