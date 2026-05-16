import { AsciiMouse } from '~/components/Icons';
import { useLocalize } from '~/hooks';

export default function RemiEmptyState() {
  const localize = useLocalize();

  return (
    <div className="glass-card remi-radius-card flex flex-col items-center justify-center p-6 text-center">
      <div className="remi-mouse-icon-breathe mb-3 flex size-11 items-center justify-center rounded-full bg-surface-tertiary/80">
        <AsciiMouse variant="logoHero" size="hero" className="text-brand-purple" />
      </div>
      <p className="text-sm font-medium text-text-primary">
        {localize('com_remi_empty_title')}
      </p>
      <p className="mt-1 text-xs text-text-secondary">{localize('com_remi_empty_body')}</p>
    </div>
  );
}
