import type { MouseSpriteClip } from '~/components/Icons/mouseSpriteCatalog';

export const IDLE_CLIPS: readonly MouseSpriteClip[] = ['idle'];

export function idleClipForCorner(_corner: SpriteFacingCorner): MouseSpriteClip {
  return 'idle';
}

/** Subtle ambient clips — no run/slide (platformer stride drifts out of UI crop). */
export const ACTION_CLIPS: readonly MouseSpriteClip[] = ['lookUp', 'jump', 'hurt'];

export const EXCITED_CLIPS: readonly MouseSpriteClip[] = ['slash', 'thrust', 'combo', 'jump'];

export const STREAMING_CLIPS: readonly MouseSpriteClip[] = ['lookUp'];

export type SpritePool = readonly MouseSpriteClip[];

export type WeightedClip = { clip: MouseSpriteClip; weight: number };

export function pickRandomClip(
  pool: SpritePool,
  exclude?: MouseSpriteClip,
): MouseSpriteClip {
  const choices =
    exclude && pool.length > 1 ? pool.filter((clip) => clip !== exclude) : [...pool];
  return choices[Math.floor(Math.random() * choices.length)] ?? pool[0];
}

export function pickWeightedClip(entries: readonly WeightedClip[], exclude?: MouseSpriteClip): MouseSpriteClip {
  const pool =
    exclude && entries.length > 1
      ? entries.filter((e) => e.clip !== exclude)
      : [...entries];
  const total = pool.reduce((sum, e) => sum + e.weight, 0);
  let roll = Math.random() * total;
  for (const entry of pool) {
    roll -= entry.weight;
    if (roll <= 0) {
      return entry.clip;
    }
  }
  return pool[pool.length - 1]?.clip ?? entries[0].clip;
}

export const CLICK_SURPRISE_WEIGHTS: readonly WeightedClip[] = [
  { clip: 'slash', weight: 3 },
  { clip: 'thrust', weight: 2 },
];

export function randomBetween(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

export function randomIntBetween(min: number, max: number): number {
  return Math.floor(randomBetween(min, max + 1));
}

export function pickRandomCorner<T>(corners: readonly T[], exclude?: T): T {
  const choices =
    exclude && corners.length > 1 ? corners.filter((c) => c !== exclude) : [...corners];
  return choices[Math.floor(Math.random() * choices.length)] ?? corners[0];
}

export type SpriteFacingCorner = 'br' | 'bl' | 'tl' | 'tr';

export function walkClipForCorner(_corner: SpriteFacingCorner): MouseSpriteClip {
  return 'idle';
}

export function attackClipForCorner(corner: SpriteFacingCorner): MouseSpriteClip {
  if (corner === 'bl') {
    return 'thrust';
  }
  if (corner === 'tl') {
    return 'combo';
  }
  return 'slash';
}

export function streamingClip(): MouseSpriteClip {
  return 'lookUp';
}
