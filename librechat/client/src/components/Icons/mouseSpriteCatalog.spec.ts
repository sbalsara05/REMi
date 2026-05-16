import {
  SPRITE,
  clipAnimationDuration,
  clipAnimationPositions,
  clipBackgroundPosition,
  clipBackgroundSize,
  clipFrameSize,
  getClipDef,
} from './mouseSpriteCatalog';

describe('mouseSpriteCatalog', () => {
  it('defines sheet geometry', () => {
    expect(SPRITE.frameW).toBe(48);
    expect(SPRITE.frameH).toBe(36);
    expect(SPRITE.cols).toBe(4);
    expect(SPRITE.rows).toBe(12);
  });

  it('computes scaled background size', () => {
    expect(clipBackgroundSize(1)).toEqual({ w: 192, h: 432 });
    expect(clipBackgroundSize(0.5)).toEqual({ w: 96, h: 216 });
  });

  it('computes viewport display size', () => {
    expect(clipFrameSize('idleFront', 1)).toEqual({ w: 18, h: 10 });
    expect(clipFrameSize('walkSide', 1)).toEqual({ w: 24, h: 20 });
    expect(clipFrameSize('walkSide', 0.5)).toEqual({ w: 12, h: 10 });
  });

  it('positions walkSide frame 2 with viewport offset', () => {
    expect(clipBackgroundPosition('walkSide', 2, 1)).toBe('-104px -13px');
  });

  it('positions idleFront frame 1 at row 9', () => {
    expect(clipBackgroundPosition('idleFront', 1, 1)).toBe('-63px -350px');
  });

  it('derives animation duration from fps and frame count', () => {
    expect(clipAnimationDuration('idleFront')).toBe('0.5s');
    expect(clipAnimationDuration('walkSide')).toBe('0.5s');
  });

  it('keyframes end at last frame (steps n-1)', () => {
    expect(clipAnimationPositions('walkSide', 1)).toEqual({
      from: '-8px -13px',
      to: '-152px -13px',
    });
    expect(clipAnimationPositions('idleFront', 1)).toEqual({
      from: '-15px -350px',
      to: '-63px -350px',
    });
  });

  it('uses BASE_URL for sprite asset path', () => {
    expect(SPRITE.url).toMatch(/assets\/mouse-spritesheet\.png$/);
  });

  it('maps clip rows', () => {
    expect(getClipDef('dashSide').row).toBe(3);
    expect(getClipDef('idleBack').frames).toBe(2);
  });
});
