const jwt = require('jsonwebtoken');
const { math } = require('@librechat/api');
const { DEFAULT_REFRESH_TOKEN_EXPIRY } = require('@librechat/data-schemas');
const {
  getTOTPSecret,
  verifyBackupCode,
  verifyTOTP,
} = require('~/server/services/twoFactorService');
const {
  getUserById,
  findSession,
  createSession,
  generateToken,
  generateRefreshToken,
} = require('~/models');

function sanitizeDeviceUser(user) {
  if (!user) {
    return null;
  }
  return {
    id: user._id?.toString?.() ?? user.id,
    email: user.email,
    name: user.name,
    username: user.username,
  };
}

async function createDeviceSession(user) {
  const expiresIn = math(process.env.REFRESH_TOKEN_EXPIRY, DEFAULT_REFRESH_TOKEN_EXPIRY);
  const { session, refreshToken } = await createSession(user._id ?? user.id, { expiresIn });
  const token = await generateToken(user);
  const expiresAt = session.expiration.getTime();

  return {
    token,
    refreshToken,
    expiresAt,
    user: sanitizeDeviceUser(user),
  };
}

async function refreshDeviceSession(refreshToken) {
  if (!refreshToken || typeof refreshToken !== 'string') {
    const error = new Error('refreshToken is required');
    error.status = 400;
    throw error;
  }

  let payload;
  try {
    payload = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
  } catch {
    const error = new Error('Invalid refresh token');
    error.status = 401;
    throw error;
  }

  const user = await getUserById(payload.id);
  if (!user) {
    const error = new Error('User not found');
    error.status = 401;
    throw error;
  }

  const session = await findSession(
    {
      userId: payload.id,
      refreshToken,
    },
    { lean: false },
  );

  if (!session || session.expiration <= new Date()) {
    const error = new Error('Refresh token expired or not found');
    error.status = 401;
    throw error;
  }

  const newRefreshToken = await generateRefreshToken(session);
  const token = await generateToken(user);

  return {
    token,
    refreshToken: newRefreshToken,
    expiresAt: session.expiration.getTime(),
    user: sanitizeDeviceUser(user),
  };
}

async function verifyDeviceTwoFactor({ tempToken, token, backupCode }) {
  if (!tempToken) {
    const error = new Error('Missing temporary token');
    error.status = 400;
    throw error;
  }

  let payload;
  try {
    payload = jwt.verify(tempToken, process.env.JWT_SECRET);
  } catch {
    const error = new Error('Invalid or expired temporary token');
    error.status = 401;
    throw error;
  }

  const user = await getUserById(payload.userId, '+totpSecret +backupCodes');
  if (!user || !user.twoFactorEnabled) {
    const error = new Error('2FA is not enabled for this user');
    error.status = 400;
    throw error;
  }

  const secret = await getTOTPSecret(user.totpSecret);
  let isVerified = false;
  if (token) {
    isVerified = await verifyTOTP(secret, token);
  } else if (backupCode) {
    isVerified = await verifyBackupCode({ user, backupCode });
  }

  if (!isVerified) {
    const error = new Error('Invalid 2FA code or backup code');
    error.status = 401;
    throw error;
  }

  return createDeviceSession(user);
}

module.exports = {
  sanitizeDeviceUser,
  createDeviceSession,
  refreshDeviceSession,
  verifyDeviceTwoFactor,
};
