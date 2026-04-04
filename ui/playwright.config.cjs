const fs = require('node:fs');
const { defineConfig } = require('@playwright/test');

const localChromiumPath = '/snap/bin/chromium';
const executablePath =
  process.env.CHROMIUM_EXECUTABLE ||
  (fs.existsSync(localChromiumPath) ? localChromiumPath : undefined);

module.exports = defineConfig({
  testDir: './playwright',
  timeout: 60_000,
  fullyParallel: false,
  retries: 0,
  reporter: 'list',
  use: {
    headless: true,
    trace: 'retain-on-failure',
    launchOptions: {
      ...(executablePath ? { executablePath } : {}),
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    },
  },
});
