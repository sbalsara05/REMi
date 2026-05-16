import { cn } from '~/utils';
import type { AsciiMouseVariant } from './asciiMouseCatalog';
import RemiSprite from './RemiSprite';
import type { MouseSpriteClip } from './mouseSpriteCatalog';

/** Display scale presets (native frame is 48×36px). */
const SIZE_SCALE = {
  sm: 0.85,
  md: 1.1,
  lg: 1.65,
  hero: 2.5,
} as const;

const VARIANT_TO_CLIP: Partial<Record<AsciiMouseVariant, MouseSpriteClip>> = {
  micro: 'idleSide',
  caret: 'walkSide',
  thinking: 'powerFront',
  peek: 'idleBack',
  logoCompact: 'idleFront',
  logoHero: 'walkFront',
};

type RemiMouseProps = {
  variant?: AsciiMouseVariant;
  clip?: MouseSpriteClip;
  size?: keyof typeof SIZE_SCALE;
  scale?: number;
  playing?: boolean;
  className?: string;
  title?: string;
  'data-testid'?: string;
};

/** Pixel-sprite REMi for branding surfaces (not sidebar chrome). */
export default function RemiMouse({
  variant = 'micro',
  clip,
  size = 'md',
  scale,
  playing = true,
  className,
  title,
  'data-testid': dataTestId = 'remi-sprite-mouse',
}: RemiMouseProps) {
  const resolvedClip = clip ?? VARIANT_TO_CLIP[variant] ?? 'idleFront';
  const resolvedScale = scale ?? SIZE_SCALE[size];

  return (
    <RemiSprite
      clip={resolvedClip}
      scale={resolvedScale}
      playing={playing}
      className={cn('m-0 inline-flex shrink-0', className)}
      title={title}
      data-testid={dataTestId}
    />
  );
}
