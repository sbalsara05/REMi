import type { AsciiMouseVariant } from './asciiMouseCatalog';
import { createLucideShellIcon, type ShellIconComponent } from './createLucideShellIcon';
import { Bot } from 'lucide-react';

/** @deprecated Use createLucideShellIcon */
export function createAsciiShellIcon(_variant: AsciiMouseVariant): ShellIconComponent {
  return createLucideShellIcon(Bot);
}

export type { ShellIconComponent };
