import { getRemiStreamCaretCss, STREAM_CARET_CLIP } from './remiStreamCaretCss';

describe('remiStreamCaretCss', () => {
  it('emits run-clip keyframes and stream caret selectors', () => {
    const css = getRemiStreamCaretCss();
    expect(css).toContain('@keyframes remi-stream-caret-run');
    expect(css).toContain('.result-streaming > :not(ol):not(ul):not(pre):last-child:after');
    expect(css).toContain(`url(`);
    expect(STREAM_CARET_CLIP).toBe('run');
  });
});
