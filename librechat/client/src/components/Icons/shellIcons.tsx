import { createAsciiShellIcon } from './createAsciiShellIcon';

export { createAsciiShellIcon } from './createAsciiShellIcon';
export type { ShellIconComponent } from './createAsciiShellIcon';

export const ShellIcons = {
  agent: createAsciiShellIcon('agent'),
  skills: createAsciiShellIcon('skills'),
  prompts: createAsciiShellIcon('prompts'),
  memories: createAsciiShellIcon('memories'),
  bookmarks: createAsciiShellIcon('bookmarks'),
  remiMouseHistory: createAsciiShellIcon('micro'),
  parameters: createAsciiShellIcon('parameters'),
  hidePanel: createAsciiShellIcon('hidePanel'),
  newChat: createAsciiShellIcon('newChat'),
  sidebarToggle: createAsciiShellIcon('sidebarToggle'),
  sparkle: createAsciiShellIcon('peek'),
  warning: createAsciiShellIcon('warning'),
  attach: createAsciiShellIcon('attach'),
  mcp: createAsciiShellIcon('mcp'),
  ai: createAsciiShellIcon('ai'),
  menu: createAsciiShellIcon('menu'),
  preset: createAsciiShellIcon('preset'),
  bookmark: createAsciiShellIcon('bookmark'),
  model: createAsciiShellIcon('model'),
  tempChat: createAsciiShellIcon('tempChat'),
} as const;

export { default as AsciiMouse } from './AsciiMouse';
export {
  ASCII_MOUSE_CATALOG,
  ASCII_STREAM_CARET,
  ASCII_STREAM_PREVIEW,
  ASCII_THINKING,
} from './asciiMouseCatalog';
