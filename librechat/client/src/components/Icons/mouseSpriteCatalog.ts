/**
 * REMi mouse spritesheet clip catalog.
 * Asset: Foozle Critters Mouse (_Main Player Spritesheet), CC0.
 * Sheet: 960×624px, 15×13 grid, 64×48px cells (side-view platformer).
 *
 * Per-frame labels and viewports: mouseSpriteFrameCatalog.ts
 * UI `idle` = double_jump.dj_stand (row 3 col 0) — not Foozle “Player Idle” (row 0 lunge bob).
 */

import {
  getSheetRowFrames,
  type FrameViewport,
  type SheetFrameLabel,
} from './mouseSpriteFrameCatalog';

const baseUrl = (import.meta.env.BASE_URL ?? '/').replace(/\/?$/, '/');

export const SPRITE = {
  url: `${baseUrl}assets/mouse-spritesheet.png`,
  cols: 15,
  rows: 13,
  frameW: 64,
  frameH: 48,
} as const;

/** @deprecated Use FrameViewport from mouseSpriteFrameCatalog */
export type ClipViewport = FrameViewport;

/** Primary semantic clips mapped to Foozle sheet rows. */
export type SemanticMouseClip =
  | 'idle'
  | 'run'
  | 'jump'
  | 'fall'
  | 'land'
  | 'slide'
  | 'lookUp'
  | 'hurt'
  | 'slash'
  | 'thrust'
  | 'heavy'
  | 'combo';

/** Legacy names kept for existing call sites. */
export type LegacyMouseClip =
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

export type MouseSpriteClip = SemanticMouseClip | LegacyMouseClip;

export type MouseSpriteClipDef = {
  row: number;
  /** Total frames in the source row (for docs); animation uses frameCount when set. */
  frames: number;
  frameStart?: number;
  frameCount?: number;
  fps?: number;
  loop?: boolean;
};

const CLIP_DEFS: Record<SemanticMouseClip, MouseSpriteClipDef> = {
  /** double_jump.dj_stand — upright, single frame (no sheet-step blink). */
  idle: { row: 3, frames: 8, frameStart: 0, frameCount: 1, fps: 4 },
  run: { row: 1, frames: 8, fps: 11 },
  jump: { row: 2, frames: 6, fps: 12 },
  fall: { row: 3, frames: 8, fps: 10 },
  /** jump.jump_4 — crouch / settle */
  land: { row: 2, frames: 6, frameStart: 4, frameCount: 1, fps: 10 },
  slide: { row: 4, frames: 4, fps: 12 },
  /** jump.jump_0 — anticipation; no look-up strip in pack */
  lookUp: { row: 2, frames: 6, frameStart: 0, frameCount: 1, fps: 8 },
  hurt: { row: 11, frames: 4, fps: 10 },
  slash: { row: 7, frames: 10, fps: 12 },
  thrust: { row: 8, frames: 5, fps: 12 },
  heavy: { row: 9, frames: 7, fps: 10 },
  combo: { row: 10, frames: 7, fps: 12 },
};

const LEGACY_ALIASES: Record<LegacyMouseClip, SemanticMouseClip> = {
  idleFront: 'idle',
  idleSide: 'idle',
  idleBack: 'idle',
  walkSide: 'idle',
  walkFront: 'idle',
  walkBack: 'idle',
  dashSide: 'slide',
  powerFront: 'heavy',
  powerBack: 'fall',
  attackSide: 'slash',
  attackFront: 'thrust',
  attackBack: 'combo',
};

export const IDLE_LIKE_CLIPS: ReadonlySet<MouseSpriteClip> = new Set([
  'idle',
  'idleFront',
  'idleSide',
  'idleBack',
  'walkSide',
  'walkFront',
  'walkBack',
]);

/** Clips with VFX that extend outside the tight viewport. */
export const CLIPS_WITH_BLEED: ReadonlySet<MouseSpriteClip> = new Set([
  'slide',
  'dashSide',
  'fall',
  'heavy',
  'powerFront',
  'powerBack',
  'slash',
  'thrust',
  'combo',
  'attackSide',
  'attackFront',
  'attackBack',
]);

export function resolveSemanticClip(clip: MouseSpriteClip): SemanticMouseClip {
  if (clip in CLIP_DEFS) {
    return clip as SemanticMouseClip;
  }
  return LEGACY_ALIASES[clip as LegacyMouseClip];
}

export function clipAllowsBleed(clip: MouseSpriteClip): boolean {
  return CLIPS_WITH_BLEED.has(clip);
}

export function isIdleLikeClip(clip: MouseSpriteClip): boolean {
  return IDLE_LIKE_CLIPS.has(clip);
}

export const DEFAULT_SPRITE_FPS = 8;

export const ALL_SPRITE_CLIPS = [
  ...Object.keys(CLIP_DEFS),
  ...Object.keys(LEGACY_ALIASES),
] as MouseSpriteClip[];

export function getClipDef(clip: MouseSpriteClip): MouseSpriteClipDef {
  return CLIP_DEFS[resolveSemanticClip(clip)];
}

export function getClipFps(clip: MouseSpriteClip): number {
  return getClipDef(clip).fps ?? DEFAULT_SPRITE_FPS;
}

export function getClipFrameRange(clip: MouseSpriteClip): {
  start: number;
  count: number;
} {
  const def = getClipDef(clip);
  const start = def.frameStart ?? 0;
  const count = def.frameCount ?? def.frames;
  return { start, count };
}

/** Resolved sheet frames for a clip (per-frame viewport from frame catalog). */
export function getClipFrames(clip: MouseSpriteClip): SheetFrameLabel[] {
  const def = getClipDef(clip);
  const { start, count } = getClipFrameRange(clip);
  return getSheetRowFrames(def.row).filter((f) => f.col >= start && f.col < start + count);
}

const px = (n: number) => Math.round(n);

export function clipBackgroundSize(scale: number): { w: number; h: number } {
  return {
    w: px(SPRITE.cols * SPRITE.frameW * scale),
    h: px(SPRITE.rows * SPRITE.frameH * scale),
  };
}

export function clipFrameSize(clip: MouseSpriteClip, scale: number): { w: number; h: number } {
  const frames = getClipFrames(clip);
  const w = Math.max(...frames.map((f) => f.viewport.w), 1);
  const h = Math.max(...frames.map((f) => f.viewport.h), 1);
  return { w: px(w * scale), h: px(h * scale) };
}

/** Background position for a frame index within the clip (0-based). */
export function clipBackgroundPosition(
  clip: MouseSpriteClip,
  frameIndex: number,
  scale: number,
): string {
  const def = getClipDef(clip);
  const frames = getClipFrames(clip);
  const fr = frames[frameIndex] ?? frames[0];
  if (!fr) {
    return '0px 0px';
  }
  const x = px(-(fr.col * SPRITE.frameW + fr.viewport.ox) * scale);
  const y = px(-(def.row * SPRITE.frameH + fr.viewport.oy) * scale);
  return `${x}px ${y}px`;
}

export function clipAnimationDuration(clip: MouseSpriteClip): string {
  const { count } = getClipFrameRange(clip);
  const fps = getClipFps(clip);
  return `${count / fps}s`;
}

export function clipAnimationDurationMs(clip: MouseSpriteClip): number {
  const { count } = getClipFrameRange(clip);
  const fps = getClipFps(clip);
  return (count / fps) * 1000;
}

/** Discrete per-frame keyframes (avoids steps() + mismatched shared viewport blink). */
export function clipKeyframeCss(animName: string, clip: MouseSpriteClip, scale: number): string {
  const frames = getClipFrames(clip);
  const n = frames.length;
  const pos0 = clipBackgroundPosition(clip, 0, scale);

  if (n <= 1) {
    return `@keyframes ${animName}{from,to{background-position:${pos0}}}`;
  }

  const stops: string[] = [];
  for (let i = 0; i < n; i++) {
    const startPct = (i / n) * 100;
    const endPct = i === n - 1 ? 100 : ((i + 1) / n) * 100 - 0.001;
    const pos = clipBackgroundPosition(clip, i, scale);
    stops.push(`${startPct}%{background-position:${pos}}`);
    stops.push(`${endPct}%{background-position:${pos}}`);
  }
  return `@keyframes ${animName}{${stops.join('')}}`;
}

/** @deprecated Prefer clipKeyframeCss; kept for tests. */
export function clipAnimationPositions(
  clip: MouseSpriteClip,
  scale: number,
): { from: string; to: string } {
  const frames = getClipFrames(clip);
  const n = frames.length;
  return {
    from: clipBackgroundPosition(clip, 0, scale),
    to: clipBackgroundPosition(clip, Math.max(0, n - 1), scale),
  };
}

/** @deprecated Use getClipDef; kept for tests referencing keys. */
export const MOUSE_SPRITE_CLIPS = Object.fromEntries(
  ALL_SPRITE_CLIPS.map((clip) => [clip, getClipDef(clip)]),
) as Record<MouseSpriteClip, MouseSpriteClipDef>;
