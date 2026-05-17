import { useRecoilValue } from 'recoil';
import store from '~/store';

const COMPANION_SCALE = 1.65;

export type UseRemiCompanionOptions = {
  enabled?: boolean;
  variant?: 'default' | 'auth';
};

export function useRemiCompanion({ enabled = true }: UseRemiCompanionOptions = {}) {
  const isSubmitting = useRecoilValue(store.isSubmittingFamily(0));
  const isWaiting = enabled && isSubmitting;

  return {
    isWaiting,
    clip: 'run' as const,
    playing: isWaiting,
    loop: true,
    scale: COMPANION_SCALE,
  };
}
