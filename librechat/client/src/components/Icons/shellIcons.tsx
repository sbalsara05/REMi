import {
  Bookmark,
  Bot,
  Brain,
  History,
  MessageSquarePlus,
  PanelLeftClose,
  PanelRightClose,
  ScrollText,
  SlidersHorizontal,
  Sparkles,
  SquareSlash,
  Tags,
  Zap,
} from 'lucide-react';
import { AttachmentIcon, MCPIcon, NewChatIcon } from '@librechat/client';
import { createLucideShellIcon } from './createLucideShellIcon';

export { createLucideShellIcon } from './createLucideShellIcon';
export type { ShellIconComponent } from './createLucideShellIcon';
export { createRemiShellIcon } from './createRemiShellIcon';
/** @deprecated Use createLucideShellIcon */
export { createLucideShellIcon as createAsciiShellIcon } from './createLucideShellIcon';

/** Standard UI icons for nav, header, and chrome (not mouse sprites). */
export const ShellIcons = {
  agent: createLucideShellIcon(Bot),
  skills: createLucideShellIcon(ScrollText),
  prompts: createLucideShellIcon(SquareSlash),
  memories: createLucideShellIcon(Brain),
  bookmarks: createLucideShellIcon(Tags),
  remiMouseHistory: createLucideShellIcon(History),
  parameters: createLucideShellIcon(SlidersHorizontal),
  hidePanel: createLucideShellIcon(PanelRightClose),
  newChat: NewChatIcon,
  sidebarToggle: createLucideShellIcon(PanelLeftClose),
  sparkle: createLucideShellIcon(Sparkles),
  warning: createLucideShellIcon(Zap),
  attach: AttachmentIcon,
  mcp: MCPIcon,
  ai: createLucideShellIcon(Sparkles),
  menu: createLucideShellIcon(SquareSlash),
  preset: createLucideShellIcon(SlidersHorizontal),
  bookmark: createLucideShellIcon(Bookmark),
  model: createLucideShellIcon(Bot),
  tempChat: createLucideShellIcon(MessageSquarePlus),
} as const;

export { default as RemiMouse } from './RemiMouse';
export { default as RemiSprite } from './RemiSprite';
export { default as AsciiMouse } from './AsciiMouse';
export {
  ASCII_MOUSE_CATALOG,
  ASCII_STREAM_CARET,
  ASCII_STREAM_PREVIEW,
  ASCII_THINKING,
} from './asciiMouseCatalog';
export {
  MOUSE_SPRITE_CLIPS,
  SPRITE,
  type MouseSpriteClip,
} from './mouseSpriteCatalog';
