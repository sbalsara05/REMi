import { cn } from '~/utils';

type RemiAmbientProps = {
  children: React.ReactNode;
  className?: string;
};

export default function RemiAmbient({ children, className }: RemiAmbientProps) {
  return (
    <div className={cn('remi-ambient-bg relative flex h-full w-full overflow-hidden', className)}>
      <div
        className="remi-orb remi-orb--violet pointer-events-none absolute -left-24 top-1/4 h-72 w-72"
        aria-hidden
      />
      <div
        className="remi-orb remi-orb--teal pointer-events-none absolute right-0 top-0 h-56 w-56"
        aria-hidden
      />
      <div
        className="remi-orb remi-orb--blue pointer-events-none absolute bottom-0 left-1/3 h-64 w-64"
        aria-hidden
      />
      <div
        className="remi-orb remi-orb--violet pointer-events-none absolute -right-16 bottom-1/4 h-48 w-48 opacity-60"
        aria-hidden
      />
      <div className="remi-shell-layer relative z-[1] flex h-full w-full min-w-0 flex-1">
        {children}
      </div>
    </div>
  );
}
