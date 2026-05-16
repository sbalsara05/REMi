import { MOUSE_SPRITE_CLIPS, type MouseSpriteClip } from '~/components/Icons/mouseSpriteCatalog';

export const IDLE_CLIPS: readonly MouseSpriteClip[] = ['idleFront', 'idleSide', 'idleBack'];

export function idleClipForCorner(corner: SpriteFacingCorner): MouseSpriteClip {
  if (corner === 'br' || corner === 'bl') {
    return 'idleFront';
  }
  if (corner === 'tl' || corner === 'tr') {
    return 'idleBack';
  }
  return 'idleSide';
}

export const ACTION_CLIPS: readonly MouseSpriteClip[] = [
  'walkSide',
  'walkFront',
  'walkBack',
  'dashSide',
  'attackSide',
  'attackFront',
  'attackBack',
];

export const EXCITED_CLIPS: readonly MouseSpriteClip[] = [
  'dashSide',
  'attackSide',
  'attackFront',
  'attackBack',
  'powerFront',
  'powerBack',
];

export const STREAMING_CLIPS: readonly MouseSpriteClip[] = ['powerFront', 'walkSide', 'dashSide'];

/** Full sheet — for hero / showcase moments */
export const PLAYFUL_CLIPS: readonly MouseSpriteClip[] = Object.keys(
  MOUSE_SPRITE_CLIPS,
) as MouseSpriteClip[];

export type SpritePool = readonly MouseSpriteClip[];

export function pickRandomClip(
  pool: SpritePool,
  exclude?: MouseSpriteClip,
): MouseSpriteClip {
  const choices =
    exclude && pool.length > 1 ? pool.filter((clip) => clip !== exclude) : [...pool];
  return choices[Math.floor(Math.random() * choices.length)] ?? pool[0];
}

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

/** Row 1 — approach the user from bottom corners. */
export function walkClipForCorner(corner: SpriteFacingCorner): MouseSpriteClip {
  return corner === 'br' || corner === 'bl' ? 'walkFront' : 'walkBack';
}

/** Row 6–8 — slash toward the screen based on corner. */
export function attackClipForCorner(corner: SpriteFacingCorner): MouseSpriteClip {
  if (corner === 'br' || corner === 'tr') {
    return 'attackSide';
  }
  if (corner === 'bl' || corner === 'tl') {
    return 'attackSide';
  }
  return 'attackFront';
}

/** Row 4 — charge-up while the model streams. */
export function streamingClip(): MouseSpriteClip {
  return 'powerFront';
}
