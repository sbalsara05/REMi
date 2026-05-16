const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

/** LibreChat root (librechat/) */
const librechatRoot = path.resolve(__dirname, '../..');

/** REMi: single env file at repo root; librechat/.env is an optional symlink to the same file. */
const envPaths = [
  path.join(librechatRoot, '.env'),
  path.join(librechatRoot, '..', 'env.local'),
];

let loaded = false;
for (const envPath of envPaths) {
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
    loaded = true;
    break;
  }
}

if (!loaded) {
  dotenv.config();
}

module.exports = { librechatRoot, envPaths };
