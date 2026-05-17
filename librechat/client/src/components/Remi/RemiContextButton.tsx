import { cn } from '~/utils';

type RemiContextButtonProps = {
  count: number;
  disabled?: boolean;
  className?: string;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
};

export default function RemiContextButton({
  count,
  disabled = false,
  className,
  onClick,
}: RemiContextButtonProps) {
  const showBadge = count > 0;

  return (
    <button
      type="button"
      aria-haspopup="dialog"
      aria-label={showBadge ? `View context, ${count} snapshots` : 'View context'}
      disabled={disabled || !showBadge}
      onClick={onClick}
      className={cn(
        'relative inline-flex h-8 shrink-0 items-center gap-1.5 rounded-lg border border-white/15 bg-surface-tertiary/60 px-2.5 text-xs font-semibold text-text-primary transition hover:bg-surface-hover',
        (disabled || !showBadge) && 'cursor-not-allowed opacity-50',
        className,
      )}
    >
      Context
      {showBadge && (
        <span className="inline-flex min-w-[1.1rem] items-center justify-center rounded-full bg-brand-purple/25 px-1 text-[10px] font-bold text-brand-purple">
          {count}
        </span>
      )}
    </button>
  );
}
