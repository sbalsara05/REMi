import { resolveSemanticClip } from '~/components/Icons/mouseSpriteCatalog';
import {
  ACTION_CLIPS,
  CLICK_SURPRISE_WEIGHTS,
  EXCITED_CLIPS,
  IDLE_CLIPS,
  attackClipForCorner,
  pickRandomClip,
  pickWeightedClip,
  pickRandomCorner,
  randomIntBetween,
  streamingClip,
  walkClipForCorner,
} from './mouseSpritePools';

describe('mouseSpritePools', () => {
  it('pickRandomClip returns a clip from the pool', () => {
    for (let i = 0; i < 20; i++) {
      expect(IDLE_CLIPS).toContain(pickRandomClip(IDLE_CLIPS));
    }
  });

  it('pickRandomClip can exclude the current clip', () => {
    const pool = ['idle', 'run'] as const;
    for (let i = 0; i < 30; i++) {
      const next = pickRandomClip(pool, 'idle');
      expect(next).not.toBe('idle');
    }
  });

  it('pickWeightedClip returns a weighted clip', () => {
    for (let i = 0; i < 20; i++) {
      const clip = pickWeightedClip(CLICK_SURPRISE_WEIGHTS);
      expect(['slash', 'thrust']).toContain(clip);
    }
  });

  it('defines semantic pools', () => {
    expect(IDLE_CLIPS).toEqual(['idle']);
    expect(ACTION_CLIPS).toContain('lookUp');
    expect(ACTION_CLIPS).not.toContain('run');
    expect(EXCITED_CLIPS).toContain('slash');
  });

  it('pickRandomCorner excludes current corner when possible', () => {
    const corners = ['br', 'bl', 'tl', 'tr'] as const;
    for (let i = 0; i < 20; i++) {
      expect(pickRandomCorner(corners, 'br')).not.toBe('br');
    }
  });

  it('maps corners to idle and attack clips', () => {
    expect(walkClipForCorner('br')).toBe('idle');
    expect(resolveSemanticClip('walkSide')).toBe('idle');
    expect(attackClipForCorner('br')).toBe('slash');
    expect(attackClipForCorner('bl')).toBe('thrust');
    expect(attackClipForCorner('tl')).toBe('combo');
    expect(streamingClip()).toBe('lookUp');
  });

  it('randomIntBetween stays in range', () => {
    for (let i = 0; i < 50; i++) {
      const n = randomIntBetween(6, 14);
      expect(n).toBeGreaterThanOrEqual(6);
      expect(n).toBeLessThanOrEqual(14);
    }
  });
});
