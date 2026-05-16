/**
 * REMi mouse spritesheet clip catalog.
 * Sheet: 192×432px, 4×12 grid, 48×36px cells.
 * Viewports derived from per-cell content bounds (avoids cropping VFX / empty padding).
 */

const baseUrl = (import.meta.env.BASE_URL ?? '/').replace(/\/?$/, '/');

export const SPRITE = {
  url: `${baseUrl}assets/mouse-spritesheet.png`,
  cols: 4,
  rows: 12,
  frameW: 48,
  frameH: 36,
} as const;

export type MouseSpriteClip =
  | 'walkSide'
  | 'walkFront'
  | 'walkBack'
  | 'dashSide'
  | 'powerFront'
  | 'powerBack'
  | 'attackSide'
  | 'attackFront'
  | 'attackBack'
  | 'idleFront'
  | 'idleSide'
  | 'idleBack';

/** Visible region inside each 48×36 cell (source pixels). */
export type ClipViewport = {
  w: number;
  h: number;
  ox: number;
  oy: number;
};

export type MouseSpriteClipDef = {
  row: number;
  frames: number;
  fps?: number;
  loop?: boolean;
  viewport: ClipViewport;
};

/** Per-row viewports from sheet alpha bounds (+1px pad). */
export const MOUSE_SPRITE_CLIPS: Record<MouseSpriteClip, MouseSpriteClipDef> = {
  walkSide: { row: 0, frames: 4, fps: 8, viewport: { w: 24, h: 20, ox: 8, oy: 13 } },
  walkFront: { row: 1, frames: 4, fps: 8, viewport: { w: 18, h: 20, ox: 15, oy: 9 } },
  walkBack: { row: 2, frames: 4, fps: 8, viewport: { w: 18, h: 20, ox: 15, oy: 5 } },
  dashSide: { row: 3, frames: 4, fps: 10, viewport: { w: 48, h: 36, ox: 0, oy: 0 } },
  powerFront: { row: 4, frames: 4, fps: 8, viewport: { w: 20, h: 36, ox: 14, oy: 0 } },
  powerBack: { row: 5, frames: 4, fps: 8, viewport: { w: 19, h: 22, ox: 14, oy: 0 } },
  attackSide: { row: 6, frames: 4, fps: 10, viewport: { w: 48, h: 20, ox: 5, oy: 5 } },
  attackFront: { row: 7, frames: 4, fps: 10, viewport: { w: 21, h: 31, ox: 13, oy: 0 } },
  attackBack: { row: 8, frames: 4, fps: 10, viewport: { w: 21, h: 29, ox: 13, oy: 5 } },
  idleFront: { row: 9, frames: 2, fps: 4, viewport: { w: 18, h: 10, ox: 15, oy: 26 } },
  idleSide: { row: 10, frames: 2, fps: 4, viewport: { w: 20, h: 28, ox: 12, oy: 7 } },
  idleBack: { row: 11, frames: 2, fps: 4, viewport: { w: 21, h: 28, ox: 12, oy: 7 } },
};

/** Clips with effects that extend outside the tight viewport. */
export const CLIPS_WITH_BLEED: ReadonlySet<MouseSpriteClip> = new Set([
  'dashSide',
  'powerFront',
  'powerBack',
  'attackSide',
  'attackFront',
  'attackBack',
]);

export function clipAllowsBleed(clip: MouseSpriteClip): boolean {
  return CLIPS_WITH_BLEED.has(clip);
}

export const DEFAULT_SPRITE_FPS = 8;

export const ALL_SPRITE_CLIPS = Object.keys(MOUSE_SPRITE_CLIPS) as MouseSpriteClip[];

export function getClipDef(clip: MouseSpriteClip): MouseSpriteClipDef {
  return MOUSE_SPRITE_CLIPS[clip];
}

export function getClipFps(clip: MouseSpriteClip): number {
  return MOUSE_SPRITE_CLIPS[clip].fps ?? DEFAULT_SPRITE_FPS;
}

const px = (n: number) => Math.round(n);

export function clipBackgroundSize(scale: number): { w: number; h: number } {
  return {
    w: px(SPRITE.cols * SPRITE.frameW * scale),
    h: px(SPRITE.rows * SPRITE.frameH * scale),
  };
}

export function clipFrameSize(clip: MouseSpriteClip, scale: number): { w: number; h: number } {
  const { viewport } = getClipDef(clip);
  return {
    w: px(viewport.w * scale),
    h: px(viewport.h * scale),
  };
}

/** Background position for a single frame (top-left of viewport in scaled sheet space). */
export function clipBackgroundPosition(
  clip: MouseSpriteClip,
  frameIndex: number,
  scale: number,
): string {
  const { row, viewport } = getClipDef(clip);
  const x = px(-(frameIndex * SPRITE.frameW + viewport.ox) * scale);
  const y = px(-(row * SPRITE.frameH + viewport.oy) * scale);
  return `${x}px ${y}px`;
}

export function clipAnimationDuration(clip: MouseSpriteClip): string {
  const { frames } = getClipDef(clip);
  const fps = getClipFps(clip);
  return `${frames / fps}s`;
}

export function clipAnimationDurationMs(clip: MouseSpriteClip): number {
  const { frames } = getClipDef(clip);
  const fps = getClipFps(clip);
  return (frames / fps) * 1000;
}

/** Keyframe endpoints — steps(n) shows n frames, so end at (frames - 1). */
export function clipAnimationPositions(
  clip: MouseSpriteClip,
  scale: number,
): { from: string; to: string } {
  const { row, frames, viewport } = getClipDef(clip);
  const frameW = px(SPRITE.frameW * scale);
  const frameH = px(SPRITE.frameH * scale);
  const y = px(-(row * frameH + viewport.oy * scale));
  return {
    from: `${px(-viewport.ox * scale)}px ${y}px`,
    to: `${px(-((frames - 1) * frameW + viewport.ox * scale))}px ${y}px`,
  };
}
