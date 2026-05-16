import type { FC } from 'react';
import type { Icon, IconProps } from '@phosphor-icons/react';
import {
  ArrowLineRight,
  BookmarkSimple,
  Brain,
  CursorClick,
  Notebook,
  PencilSimple,
  Robot,
  Scroll,
  SidebarSimple,
  SlidersHorizontal,
  Sparkle,
  WarningCircle,
} from '@phosphor-icons/react';

export type ShellIconComponent = FC<{ className?: string }>;

export function createShellIcon(
  PhosphorIcon: Icon,
  weight: IconProps['weight'] = 'duotone',
): ShellIconComponent {
  function ShellIcon({ className }: { className?: string }) {
    return <PhosphorIcon className={className} weight={weight} aria-hidden />;
  }
  ShellIcon.displayName = PhosphorIcon.displayName ?? 'ShellIcon';
  return ShellIcon;
}

export const ShellIcons = {
  agent: createShellIcon(Robot),
  skills: createShellIcon(Scroll),
  prompts: createShellIcon(Notebook),
  memories: createShellIcon(Brain),
  bookmarks: createShellIcon(BookmarkSimple),
  remiMouseHistory: createShellIcon(CursorClick),
  parameters: createShellIcon(SlidersHorizontal, 'regular'),
  hidePanel: createShellIcon(ArrowLineRight, 'regular'),
  newChat: createShellIcon(PencilSimple, 'regular'),
  sidebarToggle: createShellIcon(SidebarSimple, 'regular'),
  sparkle: createShellIcon(Sparkle),
  warning: createShellIcon(WarningCircle, 'regular'),
} as const;

export { CursorClick, Sparkle, WarningCircle };
