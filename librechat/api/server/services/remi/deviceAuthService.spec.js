const jwt = require('jsonwebtoken');

jest.mock('~/models', () => ({
  getUserById: jest.fn(),
  findSession: jest.fn(),
  createSession: jest.fn(),
  generateToken: jest.fn(),
  generateRefreshToken: jest.fn(),
}));

const {
  getUserById,
  findSession,
  createSession,
  generateToken,
  generateRefreshToken,
} = require('~/models');
const { refreshDeviceSession } = require('./deviceAuthService');

describe('deviceAuthService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
  });

  it('refreshes a valid device session', async () => {
    const refreshToken = jwt.sign({ id: 'user-1' }, process.env.JWT_REFRESH_SECRET);
    const expiration = new Date(Date.now() + 60_000);

    getUserById.mockResolvedValue({ _id: 'user-1', email: 'a@b.com' });
    findSession.mockResolvedValue({ expiration });
    generateRefreshToken.mockResolvedValue('new-refresh');
    generateToken.mockResolvedValue('new-access');

    const result = await refreshDeviceSession(refreshToken);

    expect(result).toMatchObject({
      token: 'new-access',
      refreshToken: 'new-refresh',
      user: { id: 'user-1', email: 'a@b.com' },
    });
    expect(result.expiresAt).toBe(expiration.getTime());
  });

  it('rejects missing refreshToken', async () => {
    await expect(refreshDeviceSession('')).rejects.toMatchObject({
      status: 400,
      message: 'refreshToken is required',
    });
  });

  it('rejects expired sessions', async () => {
    const refreshToken = jwt.sign({ id: 'user-1' }, process.env.JWT_REFRESH_SECRET);

    getUserById.mockResolvedValue({ _id: 'user-1', email: 'a@b.com' });
    findSession.mockResolvedValue({ expiration: new Date(Date.now() - 1000) });

    await expect(refreshDeviceSession(refreshToken)).rejects.toMatchObject({
      status: 401,
    });
  });
});
