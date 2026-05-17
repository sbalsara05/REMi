import { cn } from '~/utils';
import RemiOrbBackground from '~/components/Orb/RemiOrbBackground';

type RemiAmbientProps = {
  children?: React.ReactNode;
  className?: string;
  /** Full-bleed backdrop (auth/login) instead of flex shell layout. */
  backdrop?: boolean;
};

export default function RemiAmbient({ children, className, backdrop = false }: RemiAmbientProps) {
  return (
    <div
      className={cn(
        'remi-ambient-bg overflow-hidden',
        backdrop
          ? 'pointer-events-none absolute inset-0 z-0'
          : 'relative flex h-full w-full',
        className,
      )}
    >
      <RemiOrbBackground ambient={backdrop} chatLayout={!backdrop} />
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
      {children != null ? (
        <div className="remi-shell-layer relative z-[1] flex h-full w-full min-w-0 flex-1">
          {children}
        </div>
      ) : null}
    </div>
  );
}
