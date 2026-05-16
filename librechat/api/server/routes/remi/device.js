const express = require('express');
const { logger } = require('@librechat/data-schemas');
const logHeaders = require('~/server/middleware/logHeaders');
const checkBan = require('~/server/middleware/checkBan');
const requireLocalAuth = require('~/server/middleware/requireLocalAuth');
const requireLdapAuth = require('~/server/middleware/requireLdapAuth');
const { loginLimiter } = require('~/server/middleware/limiters');
const { generate2FATempToken } = require('~/server/services/twoFactorService');
const {
  createDeviceSession,
  refreshDeviceSession,
  verifyDeviceTwoFactor,
} = require('~/server/services/remi/deviceAuthService');

const router = express.Router();

const ldapAuth = !!process.env.LDAP_URL && !!process.env.LDAP_USER_SEARCH_BASE;

router.post(
  '/login',
  logHeaders,
  loginLimiter,
  checkBan,
  ldapAuth ? requireLdapAuth : requireLocalAuth,
  async (req, res) => {
    try {
      if (!req.user) {
        return res.status(401).json({ error: 'Invalid credentials' });
      }

      if (req.user.twoFactorEnabled) {
        const tempToken = generate2FATempToken(req.user._id);
        return res.status(200).json({ twoFAPending: true, tempToken });
      }

      const session = await createDeviceSession(req.user);
      return res.status(200).json(session);
    } catch (error) {
      logger.error('[remi] device login failed', error);
      return res.status(500).json({ error: 'Device login failed' });
    }
  },
);

router.post('/login/2fa', async (req, res) => {
  try {
    const { tempToken, token, backupCode } = req.body ?? {};
    const session = await verifyDeviceTwoFactor({ tempToken, token, backupCode });
    return res.status(200).json(session);
  } catch (error) {
    if (error.status === 400 || error.status === 401) {
      return res.status(error.status).json({ message: error.message });
    }
    logger.error('[remi] device 2FA login failed', error);
    return res.status(500).json({ error: 'Device 2FA login failed' });
  }
});

router.post('/refresh', async (req, res) => {
  try {
    const { refreshToken } = req.body ?? {};
    const session = await refreshDeviceSession(refreshToken);
    return res.status(200).json(session);
  } catch (error) {
    if (error.status === 400) {
      return res.status(400).json({ error: error.message });
    }
    if (error.status === 401) {
      return res.status(401).json({ error: error.message });
    }
    logger.error('[remi] device refresh failed', error);
    return res.status(500).json({ error: 'Device refresh failed' });
  }
});

module.exports = router;
