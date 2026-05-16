import type { FC, HTMLAttributes } from 'react';
import { cn } from '~/utils';
import AsciiMouse from './AsciiMouse';
import type { AsciiMouseVariant } from './asciiMouseCatalog';

export type ShellIconComponent = FC<HTMLAttributes<HTMLSpanElement>>;

export function createAsciiShellIcon(variant: AsciiMouseVariant): ShellIconComponent {
  function AsciiShellIcon({ className, ...rest }: HTMLAttributes<HTMLSpanElement>) {
    return (
      <span
        className={cn('inline-flex size-full items-center justify-center overflow-hidden', className)}
        {...rest}
      >
        <AsciiMouse variant={variant} size="sm" />
      </span>
    );
  }
  AsciiShellIcon.displayName = `AsciiShellIcon_${variant}`;
  return AsciiShellIcon;
}
