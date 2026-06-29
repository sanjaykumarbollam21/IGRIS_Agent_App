module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.js'],
  collectCoverageFrom: [
    'src/**/*.js',
    '!src/**/*.config.js',
    '!src/**/*.index.js'
  ],
  testTimeout: 10000,
  verbose: true,
  // Force Jest to exit after all tests complete to avoid hanging on open
  // handles from Express/Sequelize connections in the test environment.
  forceExit: true,
};