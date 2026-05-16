import { ShellIcons } from '~/components/Icons';
import { useLocalize } from '~/hooks';

export default function RemiEmptyState() {
  const localize = useLocalize();

  return (
    <div className="glass-card flex flex-col items-center justify-center rounded-2xl p-6 text-center">
      <div className="mb-3 flex size-11 items-center justify-center rounded-full bg-surface-tertiary/80">
        <ShellIcons.sparkle className="size-5 text-text-secondary" aria-hidden />
      </div>
      <p className="text-sm font-medium text-text-primary">
        {localize('com_remi_empty_title')}
      </p>
      <p className="mt-1 text-xs text-text-secondary">{localize('com_remi_empty_body')}</p>
    </div>
  );
}
