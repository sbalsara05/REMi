import type { AsciiMouseVariant } from './mouseVariant';

describe('mouseVariant', () => {
  it('includes sprite-era variants used by RemiMouse', () => {
    const variants: AsciiMouseVariant[] = ['micro', 'caret', 'thinking', 'logoHero'];
    expect(variants).toHaveLength(4);
  });
});
