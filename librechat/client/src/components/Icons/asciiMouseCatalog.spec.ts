import {
  ASCII_MOUSE_CATALOG,
  ASCII_STREAM_CARET,
  ASCII_STREAM_PREVIEW,
  ASCII_THINKING,
  getAsciiMouseLines,
} from './asciiMouseCatalog';

describe('asciiMouseCatalog', () => {
  it('exposes stream caret strings for CSS variables', () => {
    expect(ASCII_STREAM_CARET).toBe('(_)_">');
    expect(ASCII_STREAM_PREVIEW).toBe('()>');
    expect(ASCII_THINKING).toBe('(o.o)');
  });

  it('returns multi-line hero art', () => {
    const lines = getAsciiMouseLines('logoHero');
    expect(lines.length).toBeGreaterThan(1);
    expect(ASCII_MOUSE_CATALOG.logoHero).toEqual(expect.any(Array));
  });
});
