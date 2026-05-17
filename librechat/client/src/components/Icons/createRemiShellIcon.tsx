import type { FC, HTMLAttributes } from 'react';
import { cn } from '~/utils';
import RemiMouse from './RemiMouse';
import type { MouseSpriteClip } from './mouseSpriteCatalog';

export type ShellIconComponent = FC<HTMLAttributes<HTMLSpanElement>>;

export function createRemiShellIcon(clip: MouseSpriteClip = 'idle'): ShellIconComponent {
  function RemiShellIcon({ className, ...rest }: HTMLAttributes<HTMLSpanElement>) {
    return (
      <span
        className={cn('inline-flex size-full items-center justify-center overflow-hidden', className)}
        {...rest}
      >
        <RemiMouse clip={clip === 'idleFront' ? 'idle' : clip} size="micro" playing={false} />
      </span>
    );
  }
  RemiShellIcon.displayName = `RemiShellIcon_${clip}`;
  return RemiShellIcon;
}
