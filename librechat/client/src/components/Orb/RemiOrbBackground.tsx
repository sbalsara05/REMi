import { useEffect, useState } from 'react';
import { useRecoilValue } from 'recoil';
import { useMediaQuery } from '@librechat/client';
import { cn } from '~/utils';
import Orb from './Orb';
import store from '~/store';

const AMBIENT_VAR = '--remi-ambient-1';

function readAmbientColor(fallback: string) {
  if (typeof document === 'undefined') {
    return fallback;
  }
  const value = getComputedStyle(document.documentElement).getPropertyValue(AMBIENT_VAR).trim();
  return value || fallback;
}

function useRemiAmbientColor(fallback = '#0a0a0f') {
  const [backgroundColor, setBackgroundColor] = useState(() => readAmbientColor(fallback));

  useEffect(() => {
    const sync = () => setBackgroundColor(readAmbientColor(fallback));
    sync();

    const observer = new MutationObserver(sync);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class', 'data-theme'],
    });

    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', sync);

    return () => {
      observer.disconnect();
      media.removeEventListener('change', sync);
    };
  }, [fallback]);

  return backgroundColor;
}

type RemiOrbBackgroundProps = {
  /** Keeps a gentle orb pulse on auth/backdrop surfaces (not tied to chat streaming). */
  ambient?: boolean;
  /** Nudge orb toward the chat column (sidebar offset). */
  chatLayout?: boolean;
};

/** Full-bleed WebGL orb behind chat and auth surfaces. */
export default function RemiOrbBackground({
  ambient = false,
  chatLayout = false,
}: RemiOrbBackgroundProps) {
  const isSubmitting = useRecoilValue(store.isSubmittingFamily(0));
  const prefersReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const backgroundColor = useRemiAmbientColor('#0a0a0f');
  const streaming = ambient ? false : isSubmitting;
  const active = ambient || streaming;

  if (prefersReducedMotion) {
    return null;
  }

  return (
    <div
      className={cn(
        'remi-orb-webgl-layer pointer-events-none absolute inset-0 z-0 overflow-hidden',
        chatLayout && 'remi-orb-webgl-layer--chat',
        active && 'remi-orb-webgl-layer--streaming',
      )}
      aria-hidden
    >
      <Orb
        className="remi-orb-webgl"
        interactionMode="stream"
        active={active}
        rotateOnHover={!ambient}
        hue={248}
        hoverIntensity={ambient ? 0.06 : 0.1}
        backgroundColor={backgroundColor}
      />
    </div>
  );
}
