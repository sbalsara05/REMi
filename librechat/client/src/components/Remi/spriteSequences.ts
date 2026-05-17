import type { MouseSpriteClip } from '~/components/Icons/mouseSpriteCatalog';
import { clipAnimationDurationMs } from '~/components/Icons/mouseSpriteCatalog';

export type SequenceStep = {
  clip: MouseSpriteClip;
  /** When true, sequence stops on this step until cancelled. */
  loop?: boolean;
};

export type SequenceController = {
  cancel: () => void;
};

export function playSpriteSequence(
  steps: readonly SequenceStep[],
  playClip: (clip: MouseSpriteClip, oneShot: boolean) => void,
  onDone?: () => void,
): SequenceController {
  let stepIndex = 0;
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  let cancelled = false;

  const cancel = () => {
    cancelled = true;
    if (timeoutId != null) {
      clearTimeout(timeoutId);
      timeoutId = null;
    }
  };

  const runStep = () => {
    if (cancelled || stepIndex >= steps.length) {
      onDone?.();
      return;
    }

    const step = steps[stepIndex];
    stepIndex += 1;
    const oneShot = !step.loop;
    playClip(step.clip, oneShot);

    if (step.loop) {
      return;
    }

    timeoutId = setTimeout(() => {
      timeoutId = null;
      runStep();
    }, clipAnimationDurationMs(step.clip) + 50);
  };

  runStep();
  return { cancel };
}

/** UI surfaces default to calm idle — run/slide read as “walking off” in tight crops. */
export const COMPANION_MOUNT: SequenceStep[] = [{ clip: 'idle', loop: true }];

export const SPLASH_BOOT_SEQUENCE: SequenceStep[] = [
  { clip: 'slide' },
  { clip: 'run' },
  { clip: 'idle', loop: true },
];

export const HERO_MOUNT: SequenceStep[] = [{ clip: 'idle', loop: true }];

export const DOUBLE_CLICK_CHAIN: SequenceStep[] = [
  { clip: 'slash' },
  { clip: 'thrust' },
  { clip: 'combo' },
  { clip: 'idle', loop: true },
];
