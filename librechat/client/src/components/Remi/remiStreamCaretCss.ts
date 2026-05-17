import {
  SPRITE,
  clipAnimationDuration,
  clipBackgroundPosition,
  clipBackgroundSize,
  clipFrameSize,
  clipKeyframeCss,
  type MouseSpriteClip,
} from '~/components/Icons/mouseSpriteCatalog';

export const STREAM_CARET_CLIP: MouseSpriteClip = 'run';
export const STREAM_CARET_SCALE = 0.58;

const ANIM_NAME = 'remi-stream-caret-run';

function streamCaretPseudoRules(): string {
  const bgSize = clipBackgroundSize(STREAM_CARET_SCALE);
  const frameSize = clipFrameSize(STREAM_CARET_CLIP, STREAM_CARET_SCALE);
  const duration = clipAnimationDuration(STREAM_CARET_CLIP);
  const pos0 = clipBackgroundPosition(STREAM_CARET_CLIP, 0, STREAM_CARET_SCALE);

  return `
    content: '';
    display: inline-block;
    width: ${frameSize.w}px;
    height: ${frameSize.h}px;
    margin-left: 0.3rem;
    vertical-align: middle;
    background-image: url(${SPRITE.url});
    background-repeat: no-repeat;
    background-size: ${bgSize.w}px ${bgSize.h}px;
    background-position: ${pos0};
    image-rendering: pixelated;
    image-rendering: crisp-edges;
    -webkit-animation: ${ANIM_NAME} ${duration} linear infinite;
    animation: ${ANIM_NAME} ${duration} linear infinite;
  `;
}

const BASE_STREAM_CARET_SELECTORS = [
  '.result-streaming > :not(ol):not(ul):not(pre):last-child:after',
  '.result-streaming > pre:last-child code:after',
  '.remi-preview-streaming::after',
].join(',\n');

const HAS_SUPPORT_SELECTORS = [
  '.result-streaming > :is(ul, ol):last-child > li:last-child:not(:has(> :is(ul, ol, pre))):after',
].join(',\n');

const NO_HAS_SUPPORT_SELECTORS = [
  '.result-streaming > ol:last-child > li:last-child:after',
  '.result-streaming > ul:last-child > li:last-child:after',
  '.result-streaming > ol:last-child > li:last-child > pre:last-child code:after',
  '.result-streaming > ul:last-child > li:last-child > pre:last-child code:after',
].join(',\n');

function rulesForSelectors(selectors: string, pseudo: string): string {
  return `${selectors} {\n${pseudo}\n}`;
}

export function getRemiStreamCaretCss(): string {
  const keyframes = clipKeyframeCss(ANIM_NAME, STREAM_CARET_CLIP, STREAM_CARET_SCALE);
  const pseudo = streamCaretPseudoRules();

  return `
${keyframes}
${rulesForSelectors(BASE_STREAM_CARET_SELECTORS, pseudo)}
@supports (selector(:has(*))) {
  ${rulesForSelectors(HAS_SUPPORT_SELECTORS, pseudo)}
}
@supports not (selector(:has(*))) {
  ${rulesForSelectors(NO_HAS_SUPPORT_SELECTORS, pseudo)}
}
@media (prefers-reduced-motion: reduce) {
  ${BASE_STREAM_CARET_SELECTORS},
  ${HAS_SUPPORT_SELECTORS},
  ${NO_HAS_SUPPORT_SELECTORS} {
    animation: none;
    opacity: 0.9;
  }
}
`;
}
