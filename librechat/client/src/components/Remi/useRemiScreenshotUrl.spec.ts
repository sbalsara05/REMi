import { renderHook, waitFor } from '@testing-library/react';
import { request } from 'librechat-data-provider';
import { useRemiScreenshotUrl } from './useRemiScreenshotUrl';

jest.mock('librechat-data-provider', () => ({
  request: {
    getResponse: jest.fn(),
  },
}));

const mockGetResponse = request.getResponse as jest.MockedFunction<typeof request.getResponse>;

describe('useRemiScreenshotUrl', () => {
  const createObjectURL = jest.fn(() => 'blob:remi-shot');
  const revokeObjectURL = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    global.URL.createObjectURL = createObjectURL;
    global.URL.revokeObjectURL = revokeObjectURL;
    createObjectURL.mockReturnValue('blob:remi-shot');
  });

  it('does not fetch when disabled', () => {
    const { result } = renderHook(() => useRemiScreenshotUrl('id-1', false));
    expect(result.current.url).toBeNull();
    expect(result.current.state).toBe('idle');
    expect(mockGetResponse).not.toHaveBeenCalled();
  });

  it('returns a blob URL after a successful fetch', async () => {
    mockGetResponse.mockResolvedValue({
      status: 200,
      headers: { 'content-type': 'image/png' },
      data: new Blob(['png'], { type: 'image/png' }),
    } as Awaited<ReturnType<typeof request.getResponse>>);

    const { result } = renderHook(() => useRemiScreenshotUrl('id-1', true));

    await waitFor(() => {
      expect(result.current.url).toBe('blob:remi-shot');
      expect(result.current.state).toBe('ready');
    });
    expect(mockGetResponse).toHaveBeenCalledWith('/api/remi/interactions/id-1/screenshot', {
      responseType: 'blob',
      headers: { Accept: 'image/png, image/*' },
    });
    expect(createObjectURL).toHaveBeenCalled();
  });

  it('marks missing when the response is not an image', async () => {
    mockGetResponse.mockResolvedValue({
      status: 401,
      headers: { 'content-type': 'application/json' },
      data: new Blob(['{}'], { type: 'application/json' }),
    } as Awaited<ReturnType<typeof request.getResponse>>);

    const { result } = renderHook(() => useRemiScreenshotUrl('id-1', true));

    await waitFor(() => {
      expect(result.current.state).toBe('missing');
      expect(result.current.url).toBeNull();
    });
  });
});
