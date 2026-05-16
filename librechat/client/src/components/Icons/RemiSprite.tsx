import { useId, useMemo } from 'react';
import { cn } from '~/utils';
import './mouseSprite.css';
import {
  SPRITE,
  clipAllowsBleed,
  clipAnimationDuration,
  clipAnimationPositions,
  clipBackgroundPosition,
  clipBackgroundSize,
  clipFrameSize,
  getClipDef,
  type MouseSpriteClip,
} from './mouseSpriteCatalog';

export type RemiSpriteProps = {
  clip?: MouseSpriteClip;
  scale?: number;
  playing?: boolean;
  loop?: boolean;
  className?: string;
  title?: string;
  'aria-label'?: string;
  'data-testid'?: string;
  onAnimationEnd?: () => void;
};

export default function RemiSprite({
  clip = 'idleFront',
  scale = 1,
  playing = true,
  loop: loopProp,
  className,
  title,
  'aria-label': ariaLabel,
  'data-testid': dataTestId = 'remi-sprite-mouse',
  onAnimationEnd,
}: RemiSpriteProps) {
  const reactId = useId();
  const animName = `remi-sprite-${reactId.replace(/:/g, '')}`;
  const clipDef = getClipDef(clip);
  const { frames } = clipDef;
  const loop = loopProp ?? clipDef.loop ?? true;
  const bgSize = clipBackgroundSize(scale);
  const frameSize = clipFrameSize(clip, scale);
  const { from, to } = clipAnimationPositions(clip, scale);
  const duration = clipAnimationDuration(clip);

  const keyframeCss = useMemo(
    () =>
      `@keyframes ${animName}{from{background-position:${from}}to{background-position:${to}}}`,
    [animName, from, to],
  );

  const label = ariaLabel ?? title;

  return (
    <>
      {playing ? <style>{keyframeCss}</style> : null}
      <span
        role="img"
        aria-label={label}
        title={title}
        data-testid={dataTestId}
        data-clip={clip}
        className={cn(
          'remi-sprite',
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
          backgroundPosition: playing ? from : clipBackgroundPosition(clip, 0, scale),
          ...(playing
            ? {
                animationName: animName,
                animationDuration: duration,
                animationTimingFunction: `steps(${frames})`,
                animationIterationCount: loop ? 'infinite' : '1',
              }
            : {}),
        }}
      />
    </>
  );
}
