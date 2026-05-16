import {
  ACTION_CLIPS,
  EXCITED_CLIPS,
  IDLE_CLIPS,
  PLAYFUL_CLIPS,
  attackClipForCorner,
  pickRandomClip,
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
    const pool = ['idleFront', 'idleSide', 'idleBack'] as const;
    for (let i = 0; i < 30; i++) {
      const next = pickRandomClip(pool, 'idleFront');
      expect(next).not.toBe('idleFront');
    }
  });

  it('defines non-empty pools', () => {
    expect(IDLE_CLIPS.length).toBeGreaterThan(0);
    expect(ACTION_CLIPS.length).toBeGreaterThan(0);
    expect(EXCITED_CLIPS.length).toBeGreaterThan(0);
  });

  it('pickRandomCorner excludes current corner when possible', () => {
    const corners = ['br', 'bl', 'tl', 'tr'] as const;
    for (let i = 0; i < 20; i++) {
      expect(corners).toContain(pickRandomCorner(corners, 'br'));
      expect(pickRandomCorner(corners, 'br')).not.toBe('br');
    }
  });

  it('playful pool includes all sheet clips', () => {
    expect(PLAYFUL_CLIPS.length).toBe(12);
  });

  it('maps corners to directional walk and attack clips', () => {
    expect(walkClipForCorner('br')).toBe('walkFront');
    expect(walkClipForCorner('tl')).toBe('walkBack');
    expect(attackClipForCorner('br')).toBe('attackSide');
    expect(streamingClip()).toBe('powerFront');
  });

  it('randomIntBetween stays in range', () => {
    for (let i = 0; i < 50; i++) {
      const n = randomIntBetween(6, 14);
      expect(n).toBeGreaterThanOrEqual(6);
      expect(n).toBeLessThanOrEqual(14);
    }
  });
});
