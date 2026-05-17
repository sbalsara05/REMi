import { cn } from '~/utils';
import type { AsciiMouseVariant } from './mouseVariant';
import RemiSprite from './RemiSprite';
import type { MouseSpriteClip } from './mouseSpriteCatalog';

/** Display scale presets (native cell is 64×48px; viewports are tighter). */
const SIZE_SCALE = {
  sm: 0.75,
  md: 1,
  lg: 1.45,
  hero: 2.1,
} as const;

const VARIANT_TO_CLIP: Partial<Record<AsciiMouseVariant, MouseSpriteClip>> = {
  micro: 'idle',
  caret: 'idle',
  thinking: 'lookUp',
  peek: 'idle',
  logoCompact: 'idle',
  logoHero: 'idle',
};

type RemiMouseProps = {
  variant?: AsciiMouseVariant;
  clip?: MouseSpriteClip;
  size?: keyof typeof SIZE_SCALE;
  scale?: number;
  playing?: boolean;
  loop?: boolean;
  animationDelayMs?: number;
  className?: string;
  title?: string;
  'data-testid'?: string;
  onAnimationEnd?: () => void;
};

/** Pixel-sprite REMi for branding surfaces (not sidebar chrome). */
export default function RemiMouse({
  variant = 'micro',
  clip,
  size = 'md',
  scale,
  playing = true,
  loop,
  animationDelayMs,
  className,
  title,
  'data-testid': dataTestId = 'remi-sprite-mouse',
  onAnimationEnd,
}: RemiMouseProps) {
  const resolvedClip = clip ?? VARIANT_TO_CLIP[variant] ?? 'idle';
  const resolvedScale = scale ?? SIZE_SCALE[size];

  return (
    <RemiSprite
      clip={resolvedClip}
      scale={resolvedScale}
      playing={playing}
      loop={loop}
      animationDelayMs={animationDelayMs}
      className={cn('m-0 inline-flex shrink-0', className)}
      title={title}
      data-testid={dataTestId}
      onAnimationEnd={onAnimationEnd}
    />
  );
}
