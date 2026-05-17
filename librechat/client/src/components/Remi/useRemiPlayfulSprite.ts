import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { MouseSpriteClip } from '~/components/Icons/mouseSpriteCatalog';
import { clipAnimationDurationMs } from '~/components/Icons/mouseSpriteCatalog';
import {
  ACTION_CLIPS,
  CLICK_SURPRISE_WEIGHTS,
  EXCITED_CLIPS,
  IDLE_CLIPS,
  attackClipForCorner,
  idleClipForCorner,
  pickRandomClip,
  pickWeightedClip,
  randomIntBetween,
  type SpriteFacingCorner,
} from './mouseSpritePools';
import {
  COMPANION_MOUNT,
  DOUBLE_CLICK_CHAIN,
  HERO_MOUNT,
  playSpriteSequence,
  type SequenceController,
} from './spriteSequences';

export type PlayfulSpriteProfile = 'hero' | 'companion';

const PROFILE = {
  hero: {
    scale: 3.25,
    idleMs: { min: 4000, max: 9000 },
    actionMs: { min: 12000, max: 24000 },
    actionChance: 0.25,
  },
  companion: {
    scale: 1.65,
    idleMs: { min: 4000, max: 9000 },
    actionMs: { min: 14000, max: 28000 },
    actionChance: 0.2,
  },
} as const;

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() => {
    if (typeof window === 'undefined') {
      return false;
    }
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  });

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    const onChange = () => setReduced(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  return reduced;
}

export type PlayfulSpriteContext = {
  corner?: SpriteFacingCorner;
};

export function useRemiPlayfulSprite(
  profile: PlayfulSpriteProfile,
  enabled = true,
  context?: PlayfulSpriteContext,
) {
  const cfg = PROFILE[profile];
  const prefersReducedMotion = usePrefersReducedMotion();
  const active = enabled && !prefersReducedMotion;

  const [clip, setClip] = useState<MouseSpriteClip>('idle');
  const [playing, setPlaying] = useState(true);
  const [loop, setLoop] = useState(true);
  const [pop, setPop] = useState(false);

  const clipRef = useRef(clip);
  const oneShotTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sequenceRef = useRef<SequenceController | null>(null);
  const popTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastHoverRef = useRef(0);

  clipRef.current = clip;

  const clearOneShotTimeout = useCallback(() => {
    if (oneShotTimeoutRef.current) {
      clearTimeout(oneShotTimeoutRef.current);
      oneShotTimeoutRef.current = null;
    }
  }, []);

  const cancelSequence = useCallback(() => {
    sequenceRef.current?.cancel();
    sequenceRef.current = null;
  }, []);

  const triggerPop = useCallback(() => {
    if (popTimeoutRef.current) {
      clearTimeout(popTimeoutRef.current);
    }
    setPop(true);
    popTimeoutRef.current = setTimeout(() => {
      popTimeoutRef.current = null;
      setPop(false);
    }, 320);
  }, []);

  const idlePool = useMemo(() => {
    if (context?.corner != null) {
      return [idleClipForCorner(context.corner)] as const;
    }
    return IDLE_CLIPS;
  }, [context?.corner]);

  const actionPool = ACTION_CLIPS;

  const goIdle = useCallback(
    (exclude?: MouseSpriteClip) => {
      clearOneShotTimeout();
      cancelSequence();
      setLoop(true);
      setPlaying(true);
      setClip(pickRandomClip(idlePool, exclude));
    },
    [clearOneShotTimeout, cancelSequence, idlePool],
  );

  const playClip = useCallback(
    (next: MouseSpriteClip, oneShot: boolean) => {
      clearOneShotTimeout();
      cancelSequence();
      setClip(next);
      setPlaying(true);
      setLoop(!oneShot);

      if (oneShot) {
        const ms = clipAnimationDurationMs(next) + 50;
        oneShotTimeoutRef.current = setTimeout(() => {
          oneShotTimeoutRef.current = null;
          goIdle(next);
        }, ms);
      }
    },
    [clearOneShotTimeout, cancelSequence, goIdle],
  );

  const playSequence = useCallback(
    (steps: Parameters<typeof playSpriteSequence>[0], onDone?: () => void) => {
      clearOneShotTimeout();
      cancelSequence();
      sequenceRef.current = playSpriteSequence(steps, playClip, onDone);
    },
    [clearOneShotTimeout, cancelSequence, playClip],
  );

  const surprise = useCallback(() => {
    if (!active) {
      return;
    }
    triggerPop();
    const next =
      context?.corner != null
        ? attackClipForCorner(context.corner)
        : pickWeightedClip(CLICK_SURPRISE_WEIGHTS, clipRef.current);
    playClip(next, true);
  }, [active, context?.corner, playClip, triggerPop]);

  const handleClick = useCallback(() => {
    surprise();
  }, [surprise]);

  const handleDoubleClick = useCallback(() => {
    if (!active) {
      return;
    }
    triggerPop();
    playSequence(DOUBLE_CLICK_CHAIN);
  }, [active, playSequence, triggerPop]);

  const handlePointerEnter = useCallback(() => {
    if (!active) {
      return;
    }
    const now = Date.now();
    if (now - lastHoverRef.current < 1200) {
      return;
    }
    lastHoverRef.current = now;
    playClip('lookUp', true);
  }, [active, playClip]);

  const handleAnimationEnd = useCallback(() => {
    if (loop) {
      return;
    }
    clearOneShotTimeout();
    goIdle(clipRef.current);
  }, [loop, clearOneShotTimeout, goIdle]);

  const playClipExternal = useCallback(
    (next: MouseSpriteClip, oneShot: boolean) => {
      playClip(next, oneShot);
    },
    [playClip],
  );

  useEffect(() => {
    if (!active) {
      clearOneShotTimeout();
      cancelSequence();
      setPlaying(false);
      setClip('idle');
      setLoop(true);
      return;
    }
    if (profile === 'hero') {
      playSequence(HERO_MOUNT);
    } else {
      playSequence(COMPANION_MOUNT);
    }
  }, [active, clearOneShotTimeout, cancelSequence, playSequence, profile]);

  useEffect(() => {
    if (!active) {
      return;
    }

    let timeoutId: ReturnType<typeof setTimeout>;

    const scheduleIdle = () => {
      const delay = randomIntBetween(cfg.idleMs.min, cfg.idleMs.max);
      timeoutId = setTimeout(() => {
        if (clipRef.current !== 'idle' && clipRef.current !== 'idleFront') {
          goIdle(clipRef.current);
        }
        scheduleIdle();
      }, delay);
    };

    scheduleIdle();
    return () => clearTimeout(timeoutId);
  }, [active, cfg.idleMs.min, cfg.idleMs.max, goIdle]);

  useEffect(() => {
    if (!active) {
      return;
    }

    let timeoutId: ReturnType<typeof setTimeout>;

    const scheduleAction = () => {
      const delay = randomIntBetween(cfg.actionMs.min, cfg.actionMs.max);
      timeoutId = setTimeout(() => {
        if (Math.random() < cfg.actionChance) {
          playClip(pickRandomClip(actionPool, clipRef.current), true);
        }
        scheduleAction();
      }, delay);
    };

    scheduleAction();
    return () => clearTimeout(timeoutId);
  }, [active, cfg.actionMs.min, cfg.actionMs.max, cfg.actionChance, playClip, actionPool]);

  useEffect(
    () => () => {
      clearOneShotTimeout();
      cancelSequence();
      if (popTimeoutRef.current) {
        clearTimeout(popTimeoutRef.current);
      }
    },
    [clearOneShotTimeout, cancelSequence],
  );

  return {
    clip,
    playing: active ? playing : false,
    loop: active ? loop : true,
    scale: cfg.scale,
    pop,
    playClip: playClipExternal,
    playSequence,
    cancelSequence,
    goIdle,
    handleClick,
    handleDoubleClick,
    handlePointerEnter,
    handleAnimationEnd,
    prefersReducedMotion,
  };
}
