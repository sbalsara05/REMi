import { useEffect, useState } from 'react';
import RemiSprite from '~/components/Icons/RemiSprite';
import { playSpriteSequence, SPLASH_BOOT_SEQUENCE } from './spriteSequences';
import './remiSplash.css';

const MIN_VISIBLE_MS = 900;

type RemiSplashProps = {
  /** When true, the overlay begins its exit animation. */
  ready?: boolean;
};

/** Full-screen boot splash shown while auth/startup hydrate after the HTML loader. */
export default function RemiSplash({ ready = false }: RemiSplashProps) {
  const [clip, setClip] = useState<'slide' | 'run' | 'idle'>('slide');
  const [playing, setPlaying] = useState(true);
  const [loop, setLoop] = useState(false);
  const [visible, setVisible] = useState(true);
  const [exiting, setExiting] = useState(false);
  const [mountedAt] = useState(() => Date.now());

  useEffect(() => {
    const controller = playSpriteSequence(
      SPLASH_BOOT_SEQUENCE,
      (next, oneShot) => {
        setClip(next as 'slide' | 'run' | 'idle');
        setPlaying(true);
        setLoop(!oneShot);
      },
    );
    return () => controller.cancel();
  }, []);

  useEffect(() => {
    if (!ready || exiting) {
      return;
    }

    const elapsed = Date.now() - mountedAt;
    const delay = Math.max(0, MIN_VISIBLE_MS - elapsed);

    const timer = window.setTimeout(() => {
      setExiting(true);
      window.setTimeout(() => setVisible(false), 420);
    }, delay);

    return () => window.clearTimeout(timer);
  }, [ready, exiting, mountedAt]);

  if (!visible) {
    return null;
  }

  return (
    <div
      className={`remi-splash-overlay${exiting ? ' remi-splash-overlay--exit' : ''}`}
      role="status"
      aria-live="polite"
      aria-label="Loading REMi"
      data-testid="remi-splash"
    >
      <div className="remi-splash-overlay__inner">
        <RemiSprite clip={clip} scale={2.75} playing={playing} loop={loop} />
        <span className="remi-splash-overlay__title">REMi</span>
      </div>
    </div>
  );
}
