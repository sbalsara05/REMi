import { cn } from '~/utils';
import RemiSprite from '~/components/Icons/RemiSprite';
import { useRemiPlayfulSprite } from './useRemiPlayfulSprite';
import './remiPlayfulMouse.css';

type RemiPlayfulMouseProps = {
  profile?: 'hero' | 'companion';
  enabled?: boolean;
  className?: string;
  title?: string;
};

/** Large, randomly animated REMi for landing / hero surfaces. */
export default function RemiPlayfulMouse({
  profile = 'hero',
  enabled = true,
  className,
  title = 'REMi',
}: RemiPlayfulMouseProps) {
  const {
    clip,
    playing,
    loop,
    scale,
    pop,
    handleClick,
    handleDoubleClick,
    handlePointerEnter,
    handleAnimationEnd,
  } = useRemiPlayfulSprite(profile, enabled);

  return (
    <button
      type="button"
      className={cn('remi-playful-mouse', pop && 'remi-playful-mouse--pop', className)}
      aria-label={title}
      title={`${title} — click for a surprise`}
      onClick={handleClick}
      onDoubleClick={handleDoubleClick}
      onPointerEnter={handlePointerEnter}
      data-testid="remi-playful-mouse"
    >
      <RemiSprite
        clip={clip}
        scale={scale}
        playing={playing}
        loop={loop}
        onAnimationEnd={handleAnimationEnd}
        data-testid="remi-playful-mouse-sprite"
      />
    </button>
  );
}
