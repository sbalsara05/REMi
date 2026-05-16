import RemiMouse from './RemiMouse';
import type { AsciiMouseVariant } from './asciiMouseCatalog';

const sizeClass = {
  micro: 'sm',
  sm: 'sm',
  md: 'md',
  hero: 'hero',
} as const;

type AsciiMouseProps = {
  variant?: AsciiMouseVariant;
  size?: keyof typeof sizeClass;
  className?: string;
  title?: string;
  'data-testid'?: string;
};

/** @deprecated Renders pixel sprite via RemiMouse (ASCII art removed). */
export default function AsciiMouse({
  variant = 'micro',
  size = 'sm',
  className,
  title,
  'data-testid': dataTestId = 'remi-sprite-mouse',
}: AsciiMouseProps) {
  return (
    <RemiMouse
      variant={variant}
      size={size}
      className={className}
      title={title}
      data-testid={dataTestId}
    />
  );
}
