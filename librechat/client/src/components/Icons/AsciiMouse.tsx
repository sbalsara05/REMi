import { cn } from '~/utils';
import {
  getAsciiMouseLines,
  type AsciiMouseVariant,
} from './asciiMouseCatalog';

const sizeClass = {
  micro: 'text-[8px] leading-none',
  sm: 'text-[9px] leading-none',
  md: 'text-[10px] leading-tight',
  hero: 'text-[11px] leading-tight',
} as const;

type AsciiMouseProps = {
  variant?: AsciiMouseVariant;
  size?: keyof typeof sizeClass;
  className?: string;
  title?: string;
  'data-testid'?: string;
};

/** Renders catalog ASCII mouse art in monospace. */
export default function AsciiMouse({
  variant = 'micro',
  size = 'sm',
  className,
  title,
  'data-testid': dataTestId = 'remi-ascii-mouse',
}: AsciiMouseProps) {
  const lines = getAsciiMouseLines(variant);

  return (
    <pre
      className={cn(
        'remi-ascii m-0 inline-flex flex-col items-center justify-center font-mono whitespace-pre',
        sizeClass[size],
        className,
      )}
      data-testid={dataTestId}
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
    >
      {title ? <span className="sr-only">{title}</span> : null}
      {lines.map((line, i) => (
        <span key={`${variant}-${i}`}>{line}</span>
      ))}
    </pre>
  );
}
