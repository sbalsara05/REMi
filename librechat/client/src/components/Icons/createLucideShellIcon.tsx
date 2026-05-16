import type { LucideIcon } from 'lucide-react';
import type { FC, HTMLAttributes } from 'react';
import { cn } from '~/utils';

export type ShellIconComponent = FC<HTMLAttributes<HTMLSpanElement>>;

export function createLucideShellIcon(Icon: LucideIcon): ShellIconComponent {
  function LucideShellIcon({ className, ...rest }: HTMLAttributes<HTMLSpanElement>) {
    return (
      <span
        className={cn('inline-flex size-full items-center justify-center', className)}
        {...rest}
      >
        <Icon className="size-full" strokeWidth={2} aria-hidden />
      </span>
    );
  }
  LucideShellIcon.displayName = `LucideShellIcon_${Icon.displayName ?? 'Icon'}`;
  return LucideShellIcon;
}
