/**
 * ASCII mouse art catalog for REMi branding.
 * Micro/caret variants adapted from classic one-line rodent art (asciiart.eu / Joan G. Stark).
 */

export type AsciiMouseVariant =
  | 'micro'
  | 'caret'
  | 'thinking'
  | 'peek'
  | 'logoCompact'
  | 'logoHero'
  | 'agent'
  | 'skills'
  | 'prompts'
  | 'memories'
  | 'bookmarks'
  | 'parameters'
  | 'newChat'
  | 'hidePanel'
  | 'sidebarToggle'
  | 'warning'
  | 'attach'
  | 'mcp'
  | 'ai'
  | 'menu'
  | 'preset'
  | 'bookmark'
  | 'model'
  | 'tempChat';

export type AsciiMouseArt = string | readonly string[];

export const ASCII_MOUSE_CATALOG: Record<AsciiMouseVariant, AsciiMouseArt> = {
  micro: '()-()',
  caret: '(_)_">',
  thinking: '(o.o)',
  peek: ['(o)(o)--.', ' \\../'],
  logoCompact: ['  _ ', ' (c).-.', " .-'`"],
  logoHero: [
    ')   _   _',
    '  (^)-~-(^)',
    " __,-.\\_( 6 6 )",
    " 'M' \\ / 'M'",
    '   >o<',
  ],
  agent: '[=o=]',
  skills: '(^.^)',
  prompts: '(:_)',
  memories: '(°o°)',
  bookmarks: '(-.-)',
  parameters: '(=.=)',
  newChat: '(>o<)',
  hidePanel: "(<')",
  sidebarToggle: '<=)',
  warning: '(x_x)',
  attach: '[@]',
  mcp: 'MCP',
  ai: 'AI',
  menu: '<=>',
  preset: '[::]',
  bookmark: '(-)',
  model: '{AI}',
  tempChat: '(~) ',
};

export function getAsciiMouseLines(variant: AsciiMouseVariant): string[] {
  const art = ASCII_MOUSE_CATALOG[variant];
  if (typeof art === 'string') {
    return [art];
  }
  return [...art];
}

export const ASCII_STREAM_CARET = ASCII_MOUSE_CATALOG.caret as string;
export const ASCII_STREAM_PREVIEW = '()>' as string;
export const ASCII_THINKING = ASCII_MOUSE_CATALOG.thinking as string;
