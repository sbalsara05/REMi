import { renderHook, act } from '@testing-library/react';
import { useRemiPreviewStreaming } from './useRemiPreviewStreaming';

describe('useRemiPreviewStreaming', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('returns false on first non-empty value', () => {
    const { result, rerender } = renderHook(
      ({ text }) => useRemiPreviewStreaming('id-1', text),
      { initialProps: { text: null as string | null } },
    );

    rerender({ text: 'Hello' });
    expect(result.current).toBe(false);
  });

  it('returns true when responseSoFar grows after initial value', () => {
    const { result, rerender } = renderHook(
      ({ text }) => useRemiPreviewStreaming('id-1', text),
      { initialProps: { text: 'Hello' as string | null } },
    );

    rerender({ text: 'Hello world' });
    expect(result.current).toBe(true);

    act(() => {
      jest.advanceTimersByTime(600);
    });
    expect(result.current).toBe(false);
  });
});
