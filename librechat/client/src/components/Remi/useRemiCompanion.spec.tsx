import { act, renderHook } from '@testing-library/react';
import { RecoilRoot } from 'recoil';
import { attackClipForCorner } from './mouseSpritePools';
import { useRemiCompanion } from './useRemiCompanion';

function wrapper({ children }: { children: React.ReactNode }) {
  return <RecoilRoot>{children}</RecoilRoot>;
}

describe('useRemiCompanion', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('starts in bottom-right with a playful clip', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: true }), { wrapper });
    expect(result.current.corner).toBe('br');
    expect(result.current.playing).toBe(true);
    expect(result.current.scale).toBeGreaterThan(1.5);
  });

  it('plays excited clip on click with pop', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: true }), { wrapper });

    act(() => {
      result.current.handleClick();
    });

    expect(result.current.clip).toBe(attackClipForCorner('br'));
    expect(result.current.loop).toBe(false);
    expect(result.current.pop).toBe(true);
  });

  it('may change corner after drift interval', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: true }), { wrapper });
    const start = result.current.corner;

    act(() => {
      jest.advanceTimersByTime(80000);
    });

    const corners = new Set<string>();
    for (let i = 0; i < 5; i++) {
      corners.add(result.current.corner);
      act(() => {
        jest.advanceTimersByTime(15000);
      });
    }
    expect(corners.size).toBeGreaterThan(1);
    expect(['br', 'bl', 'tl', 'tr']).toContain(start);
  });

  it('does not run when disabled', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: false }), { wrapper });
    expect(result.current.playing).toBe(false);
    expect(result.current.clip).toBe('idleFront');
  });
});
