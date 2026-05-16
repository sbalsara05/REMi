import { defineConfig, type PlaywrightTestConfig } from '@playwright/test';
import baseConfig from './playwright.config';

const { webServer: _omit, globalTeardown: _omitTeardown, ...authConfig } =
  baseConfig as PlaywrightTestConfig;

/** Local-only: run globalSetup (auth) without tests or teardown. Requires app on baseURL. */
export default defineConfig({
  ...authConfig,
  testIgnore: ['**/*'],
});
