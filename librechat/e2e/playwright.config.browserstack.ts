import { defineConfig, type PlaywrightTestConfig } from '@playwright/test';
import baseConfig from './playwright.config';

const { webServer: _omit, globalSetup: _omitSetup, globalTeardown: _omitTeardown, ...bsConfig } =
  baseConfig as PlaywrightTestConfig;

/** BrowserStack cloud run: pre-auth via `npm run e2e:browserstack:auth`, app on :3080. */
export default defineConfig(bsConfig);
