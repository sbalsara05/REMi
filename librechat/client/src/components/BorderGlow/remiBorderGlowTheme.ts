export const REMI_GRADIENT_COLORS = ['#ab68ff', '#2dd4bf', '#60a5fa'] as const;

export const REMI_GLOW_HSL = '268 85 72';

export type RemiBorderGlowVariant = 'card' | 'modal' | 'composer' | 'popover';

const STREAM_VARIANTS = new Set<RemiBorderGlowVariant>(['composer']);

export function remiBorderGlowMode(variant: RemiBorderGlowVariant) {
  return STREAM_VARIANTS.has(variant) ? 'stream' : 'hover';
}

export const REMI_BORDER_GLOW_PRESETS: Record<
  RemiBorderGlowVariant,
  {
    borderRadius: number;
    glowRadius: number;
    edgeSensitivity: number;
    coneSpread: number;
    fillOpacity: number;
    animated?: boolean;
  }
> = {
  card: {
    borderRadius: 16,
    glowRadius: 28,
    edgeSensitivity: 28,
    coneSpread: 22,
    fillOpacity: 0.32,
  },
  modal: {
    borderRadius: 16,
    glowRadius: 36,
    edgeSensitivity: 24,
    coneSpread: 25,
    fillOpacity: 0.4,
    animated: true,
  },
  composer: {
    borderRadius: 24,
    glowRadius: 32,
    edgeSensitivity: 22,
    coneSpread: 20,
    fillOpacity: 0.35,
  },
  popover: {
    borderRadius: 16,
    glowRadius: 24,
    edgeSensitivity: 32,
    coneSpread: 28,
    fillOpacity: 0.4,
  },
};
