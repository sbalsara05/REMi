import RemiPlayfulMouse from '~/components/Remi/RemiPlayfulMouse';
import { useLocalize } from '~/hooks';

export default function RemiEmptyState() {
  const localize = useLocalize();

  return (
    <div className="glass-card remi-radius-card flex flex-col items-center justify-center p-6 text-center">
      <div className="remi-mouse-icon-breathe mb-4 flex min-h-[100px] min-w-[100px] items-center justify-center rounded-full bg-surface-tertiary/80 p-2">
        <RemiPlayfulMouse profile="companion" className="scale-110" />
      </div>
      <p className="text-sm font-medium text-text-primary">
        {localize('com_remi_empty_title')}
      </p>
      <p className="mt-1 text-xs text-text-secondary">{localize('com_remi_empty_body')}</p>
    </div>
  );
}
