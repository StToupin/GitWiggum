const { defineConfig } = require('@playwright/test');
const { resolveAppBaseUrl } = require('./playwright/helpers/app-base-url');

const appBaseUrl = resolveAppBaseUrl();

module.exports = defineConfig({
  testDir: './playwright',
  fullyParallel: false,
  workers: 1,
  timeout: 60 * 1000,
  expect: {
    timeout: 10 * 1000,
  },
  use: {
    baseURL: appBaseUrl,
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
  },
});
