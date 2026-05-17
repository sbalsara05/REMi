import { act, renderHook } from '@testing-library/react';
import { RecoilRoot, useSetRecoilState } from 'recoil';
import store from '~/store';
import { useRemiCompanion } from './useRemiCompanion';

function wrapper({ children }: { children: React.ReactNode }) {
  return <RecoilRoot>{children}</RecoilRoot>;
}

function useSubmittingHarness() {
  const setSubmitting = useSetRecoilState(store.isSubmittingFamily(0));
  const companion = useRemiCompanion({ enabled: true });
  return { setSubmitting, ...companion };
}

describe('useRemiCompanion', () => {
  it('is idle when not submitting', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: true }), { wrapper });
    expect(result.current.isWaiting).toBe(false);
    expect(result.current.playing).toBe(false);
    expect(result.current.clip).toBe('run');
  });

  it('runs while waiting for a model response', () => {
    const { result } = renderHook(() => useSubmittingHarness(), { wrapper });

    act(() => {
      result.current.setSubmitting(true);
    });

    expect(result.current.isWaiting).toBe(true);
    expect(result.current.clip).toBe('run');
    expect(result.current.loop).toBe(true);
    expect(result.current.playing).toBe(true);
  });

  it('does not run when disabled', () => {
    const { result } = renderHook(() => useRemiCompanion({ enabled: false }), { wrapper });
    expect(result.current.isWaiting).toBe(false);
    expect(result.current.playing).toBe(false);
  });
});
