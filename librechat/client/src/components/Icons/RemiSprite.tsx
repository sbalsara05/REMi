import { useId, useMemo } from 'react';
import { cn } from '~/utils';
import './mouseSprite.css';
import {
  SPRITE,
  clipAllowsBleed,
  clipAnimationDuration,
  clipBackgroundPosition,
  clipBackgroundSize,
  clipFrameSize,
  clipKeyframeCss,
  getClipDef,
  getClipFrameRange,
  getClipFrames,
  isIdleLikeClip,
  type MouseSpriteClip,
} from './mouseSpriteCatalog';

export type RemiSpriteProps = {
  clip?: MouseSpriteClip;
  scale?: number;
  playing?: boolean;
  loop?: boolean;
  /** Stagger sprite cycles (e.g. history cards). */
  animationDelayMs?: number;
  className?: string;
  title?: string;
  'aria-label'?: string;
  'data-testid'?: string;
  onAnimationEnd?: () => void;
};

export default function RemiSprite({
  clip = 'idle',
  scale = 1,
  playing = true,
  loop: loopProp,
  animationDelayMs = 0,
  className,
  title,
  'aria-label': ariaLabel,
  'data-testid': dataTestId = 'remi-sprite-mouse',
  onAnimationEnd,
}: RemiSpriteProps) {
  const reactId = useId();
  const animName = `remi-sprite-${reactId.replace(/:/g, '')}`;
  const clipDef = getClipDef(clip);
  const frameCells = getClipFrames(clip);
  const { count } = getClipFrameRange(clip);
  const loop = loopProp ?? clipDef.loop ?? true;
  const bgSize = clipBackgroundSize(scale);
  const frameSize = clipFrameSize(clip, scale);
  const duration = clipAnimationDuration(clip);
  const idleBob = isIdleLikeClip(clip);
  const animateFrames = playing && count > 1;
  const staticPosition = clipBackgroundPosition(clip, 0, scale);

  const keyframeCss = useMemo(
    () => (playing ? clipKeyframeCss(animName, clip, scale) : ''),
    [playing, animName, clip, scale],
  );

  const label = ariaLabel ?? title;

  return (
    <>
      {keyframeCss ? <style>{keyframeCss}</style> : null}
      <span
        role="img"
        aria-label={label}
        title={title}
        data-testid={dataTestId}
        data-clip={clip}
        data-frame-label={frameCells[0]?.label}
        className={cn(
          'remi-sprite',
          idleBob && playing && 'remi-sprite--idle',
          clipAllowsBleed(clip) && 'remi-sprite--bleed',
          !playing && 'remi-sprite--paused',
          className,
        )}
        onAnimationEnd={loop ? undefined : onAnimationEnd}
        style={{
          width: frameSize.w,
          height: frameSize.h,
          backgroundImage: `url(${SPRITE.url})`,
          backgroundSize: `${bgSize.w}px ${bgSize.h}px`,
          backgroundPosition: staticPosition,
          ...(playing
            ? animateFrames
              ? {
                  animationName: animName,
                  animationDuration: duration,
                  animationTimingFunction: 'linear',
                  animationIterationCount: loop ? 'infinite' : '1',
                  animationDelay: animationDelayMs > 0 ? `${animationDelayMs}ms` : undefined,
                }
              : idleBob
                ? {
                    animationName: 'remi-sprite-idle-bob',
                    animationDuration: '2.8s',
                    animationTimingFunction: 'ease-in-out',
                    animationIterationCount: 'infinite',
                    animationDelay: animationDelayMs > 0 ? `${animationDelayMs}ms` : undefined,
                  }
                : {}
            : {}),
        }}
      />
    </>
  );
}
