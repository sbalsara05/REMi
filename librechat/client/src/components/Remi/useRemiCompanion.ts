import { useCallback, useEffect, useRef, useState } from 'react';
import { useRecoilValue } from 'recoil';
import store from '~/store';
import { clipAnimationDurationMs } from '~/components/Icons/mouseSpriteCatalog';
import {
  pickRandomCorner,
  randomIntBetween,
  streamingClip,
  walkClipForCorner,
} from './mouseSpritePools';
import { useRemiPlayfulSprite } from './useRemiPlayfulSprite';

export type RemiCompanionCorner = 'br' | 'bl' | 'tl' | 'tr';

const CORNER_ORDER: readonly RemiCompanionCorner[] = ['br', 'bl', 'tl', 'tr'];
const DRIFT_MS = { min: 10000, max: 22000 };
const RANDOM_CORNER_CHANCE = 0.45;

export type UseRemiCompanionOptions = {
  enabled?: boolean;
  variant?: 'default' | 'auth';
};

export function useRemiCompanion({ enabled = true, variant = 'default' }: UseRemiCompanionOptions = {}) {
  const isSubmitting = useRecoilValue(store.isSubmittingFamily(0));
  const active = enabled;

  const [corner, setCorner] = useState<RemiCompanionCorner>('br');
  const playful = useRemiPlayfulSprite('companion', active, { corner });
  const { playClip, prefersReducedMotion } = playful;
  const cornerRef = useRef(corner);
  cornerRef.current = corner;

  const wasSubmittingRef = useRef(false);
  const prevCornerRef = useRef<RemiCompanionCorner | null>(null);

  const flipped = corner === 'bl' || corner === 'tl';

  const advanceCorner = useCallback(() => {
    if (variant === 'auth') {
      return;
    }
    if (Math.random() < RANDOM_CORNER_CHANCE) {
      setCorner(pickRandomCorner(CORNER_ORDER, cornerRef.current));
      return;
    }
    const idx = CORNER_ORDER.indexOf(cornerRef.current);
    setCorner(CORNER_ORDER[(idx + 1) % CORNER_ORDER.length]);
  }, [variant]);

  useEffect(() => {
    if (!active || prefersReducedMotion || variant === 'auth') {
      return;
    }

    if (isSubmitting && !wasSubmittingRef.current) {
      playClip(streamingClip(), false);
    }
    wasSubmittingRef.current = isSubmitting;
  }, [isSubmitting, active, prefersReducedMotion, variant, playClip]);

  useEffect(() => {
    if (!active || prefersReducedMotion || variant === 'auth') {
      prevCornerRef.current = corner;
      return;
    }

    const prev = prevCornerRef.current;
    prevCornerRef.current = corner;

    if (prev == null || prev === corner) {
      return;
    }

    playClip('dashSide', true);
    const dashMs = clipAnimationDurationMs('dashSide');
    const walkTimer = setTimeout(() => {
      playClip(walkClipForCorner(corner), true);
    }, dashMs + 40);

    return () => clearTimeout(walkTimer);
  }, [corner, active, prefersReducedMotion, variant, playClip]);

  useEffect(() => {
    if (!active || prefersReducedMotion || variant === 'auth') {
      return;
    }

    let timeoutId: ReturnType<typeof setTimeout>;

    const scheduleDrift = () => {
      const delay = randomIntBetween(DRIFT_MS.min, DRIFT_MS.max);
      timeoutId = setTimeout(() => {
        advanceCorner();
        scheduleDrift();
      }, delay);
    };

    scheduleDrift();
    return () => clearTimeout(timeoutId);
  }, [active, prefersReducedMotion, variant, advanceCorner]);

  return {
    corner,
    flipped,
    ...playful,
  };
}
