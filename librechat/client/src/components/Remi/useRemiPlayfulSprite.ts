import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { MouseSpriteClip } from '~/components/Icons/mouseSpriteCatalog';
import { clipAnimationDurationMs } from '~/components/Icons/mouseSpriteCatalog';
import {
  ACTION_CLIPS,
  EXCITED_CLIPS,
  IDLE_CLIPS,
  PLAYFUL_CLIPS,
  attackClipForCorner,
  idleClipForCorner,
  pickRandomClip,
  randomIntBetween,
  type SpriteFacingCorner,
} from './mouseSpritePools';

export type PlayfulSpriteProfile = 'hero' | 'companion';

const HERO_IDLE: readonly MouseSpriteClip[] = ['idleFront'];
const HERO_ACTION: readonly MouseSpriteClip[] = ['walkFront', 'walkSide', 'dashSide'];

const PROFILE = {
  hero: {
    scale: 3.25,
    idleMs: { min: 2200, max: 5500 },
    actionMs: { min: 4000, max: 9000 },
    actionChance: 0.55,
    surprisePool: HERO_ACTION,
  },
  companion: {
    scale: 1.65,
    idleMs: { min: 2800, max: 6500 },
    actionMs: { min: 6000, max: 14000 },
    actionChance: 0.55,
    surprisePool: EXCITED_CLIPS,
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

  const [clip, setClip] = useState<MouseSpriteClip>('idleFront');
  const [playing, setPlaying] = useState(true);
  const [loop, setLoop] = useState(true);
  const [pop, setPop] = useState(false);

  const clipRef = useRef(clip);
  const oneShotTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const popTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastHoverRef = useRef(0);

  clipRef.current = clip;

  const clearOneShotTimeout = useCallback(() => {
    if (oneShotTimeoutRef.current) {
      clearTimeout(oneShotTimeoutRef.current);
      oneShotTimeoutRef.current = null;
    }
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
    if (profile === 'hero') {
      return HERO_IDLE;
    }
    if (context?.corner != null) {
      return [idleClipForCorner(context.corner)] as const;
    }
    return IDLE_CLIPS;
  }, [profile, context?.corner]);

  const actionPool = profile === 'hero' ? HERO_ACTION : ACTION_CLIPS;

  const goIdle = useCallback(
    (exclude?: MouseSpriteClip) => {
      clearOneShotTimeout();
      setLoop(true);
      setPlaying(true);
      setClip(pickRandomClip(idlePool, exclude));
    },
    [clearOneShotTimeout, idlePool],
  );

  const playClip = useCallback(
    (next: MouseSpriteClip, oneShot: boolean) => {
      clearOneShotTimeout();
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
    [clearOneShotTimeout, goIdle],
  );

  const surprise = useCallback(() => {
    if (!active) {
      return;
    }
    triggerPop();
    const next =
      context?.corner != null
        ? attackClipForCorner(context.corner)
        : pickRandomClip(cfg.surprisePool, clipRef.current);
    playClip(next, true);
  }, [active, cfg.surprisePool, context?.corner, playClip, triggerPop]);

  const handleClick = useCallback(() => {
    surprise();
  }, [surprise]);

  const handleDoubleClick = useCallback(() => {
    if (!active) {
      return;
    }
    triggerPop();
    playClip(pickRandomClip(EXCITED_CLIPS, clipRef.current), true);
    setTimeout(() => {
      playClip(pickRandomClip(ACTION_CLIPS, clipRef.current), true);
    }, clipAnimationDurationMs(clipRef.current) + 80);
  }, [active, playClip, triggerPop]);

  const handlePointerEnter = useCallback(() => {
    if (!active) {
      return;
    }
    const now = Date.now();
    if (now - lastHoverRef.current < 1200) {
      return;
    }
    lastHoverRef.current = now;
    if (Math.random() < 0.65) {
      playClip(pickRandomClip([...IDLE_CLIPS, 'powerFront'] as const, clipRef.current), true);
    }
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
      setPlaying(false);
      setClip('idleFront');
      setLoop(true);
      return;
    }
    if (profile === 'hero') {
      playClip('walkFront', true);
    } else {
      playClip(pickRandomClip(PLAYFUL_CLIPS), false);
    }
  }, [active, clearOneShotTimeout, playClip, profile]);

  useEffect(() => {
    if (!active) {
      return;
    }

    let timeoutId: ReturnType<typeof setTimeout>;

    const scheduleIdle = () => {
      const delay = randomIntBetween(cfg.idleMs.min, cfg.idleMs.max);
      timeoutId = setTimeout(() => {
        goIdle(clipRef.current);
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
      if (popTimeoutRef.current) {
        clearTimeout(popTimeoutRef.current);
      }
    },
    [clearOneShotTimeout],
  );

  return {
    clip,
    playing: active ? playing : false,
    loop: active ? loop : true,
    scale: cfg.scale,
    pop,
    playClip: playClipExternal,
    handleClick,
    handleDoubleClick,
    handlePointerEnter,
    handleAnimationEnd,
    prefersReducedMotion,
  };
}
