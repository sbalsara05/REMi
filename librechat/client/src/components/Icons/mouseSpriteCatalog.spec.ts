import {
  SPRITE,
  getClipDef,
  getClipFrames,
  getClipFrameRange,
  clipAnimationDuration,
  clipAnimationDurationMs,
  clipAnimationPositions,
  clipBackgroundPosition,
  clipBackgroundSize,
  clipFrameSize,
  resolveSemanticClip,
} from './mouseSpriteCatalog';

describe('mouseSpriteCatalog', () => {
  it('defines Foozle sheet geometry', () => {
    expect(SPRITE.frameW).toBe(64);
    expect(SPRITE.frameH).toBe(48);
    expect(SPRITE.cols).toBe(15);
    expect(SPRITE.rows).toBe(13);
  });

  it('computes scaled background size from sheet geometry', () => {
    expect(clipBackgroundSize(1)).toEqual({
      w: SPRITE.cols * SPRITE.frameW,
      h: SPRITE.rows * SPRITE.frameH,
    });
  });

  it('computes viewport display size from per-frame catalog', () => {
    const clip = 'idle';
    expect(clipFrameSize(clip, 1)).toEqual({ w: 22, h: 32 });
  });

  it('positions frames using per-frame viewport from catalog', () => {
    const clip = 'run';
    const { row } = getClipDef(clip);
    const frameIndex = 2;
    const fr = getClipFrames(clip)[frameIndex];
    const x = -(fr.col * SPRITE.frameW + fr.viewport.ox);
    const y = -(row * SPRITE.frameH + fr.viewport.oy);
    expect(clipBackgroundPosition(clip, frameIndex, 1)).toBe(`${x}px ${y}px`);
  });

  it('supports frameStart subsets for land clip', () => {
    expect(getClipFrameRange('land')).toEqual({ start: 4, count: 1 });
    expect(clipAnimationPositions('land', 1).from).toBe(clipAnimationPositions('land', 1).to);
  });

  it('derives animation duration from fps and frame count', () => {
    const clip = 'idle';
    const { count } = getClipFrameRange(clip);
    const fps = getClipDef(clip).fps ?? 8;
    expect(clipAnimationDuration(clip)).toBe(`${count / fps}s`);
    expect(clipAnimationDurationMs(clip)).toBe((count / fps) * 1000);
  });

  it('resolves legacy aliases to semantic clips', () => {
    expect(resolveSemanticClip('walkSide')).toBe('idle');
    expect(resolveSemanticClip('attackSide')).toBe('slash');
    expect(resolveSemanticClip('dashSide')).toBe('slide');
  });

  it('maps idle to dj_stand on the double-jump row', () => {
    expect(getClipDef('idle').row).toBe(3);
    expect(getClipFrameRange('idle')).toEqual({ start: 0, count: 1 });
  });

  it('uses BASE_URL for sprite asset path', () => {
    expect(SPRITE.url).toMatch(/assets\/mouse-spritesheet\.png$/);
  });
});
