import { useParams } from 'react-router-dom';
import { Constants } from 'librechat-data-provider';
import { useMediaQuery } from '@librechat/client';
import { cn } from '~/utils';
import RemiSprite from '~/components/Icons/RemiSprite';
import { useGetStartupConfig } from '~/data-provider';
import { useRemiCompanion, type UseRemiCompanionOptions } from './useRemiCompanion';
import './remiCompanion.css';

type RemiCompanionProps = UseRemiCompanionOptions & {
  hideOnLanding?: boolean;
};

export function useRemiCompanionVisible(hideOnLanding: boolean): boolean {
  const { conversationId } = useParams();
  const { data: config } = useGetStartupConfig();
  const companionEnabled = config?.interface?.remi?.companion !== false;
  const isLanding =
    hideOnLanding &&
    (!conversationId || conversationId === Constants.NEW_CONVO);

  return companionEnabled && !isLanding;
}

export default function RemiCompanion({
  enabled: enabledProp,
  variant = 'default',
  hideOnLanding = true,
}: RemiCompanionProps) {
  const visible = useRemiCompanionVisible(hideOnLanding);
  const isDesktop = useMediaQuery('(min-width: 768px)');
  const enabled = (enabledProp ?? true) && visible && isDesktop;

  const {
    corner,
    flipped,
    clip,
    playing,
    loop,
    scale,
    pop,
    handleClick,
    handleDoubleClick,
    handlePointerEnter,
    handleAnimationEnd,
  } = useRemiCompanion({ enabled, variant });

  if (!enabled) {
    return null;
  }

  return (
    <div
      className={cn('remi-companion', `remi-companion--${corner}`, pop && 'remi-companion--pop')}
      data-testid="remi-companion"
    >
      <button
        type="button"
        className="remi-companion__btn"
        aria-label="REMi companion — click or double-click for surprises"
        title="REMi — click me!"
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        onPointerEnter={handlePointerEnter}
      >
        <RemiSprite
          clip={clip}
          scale={scale}
          playing={playing}
          loop={loop}
          className={cn(flipped && 'remi-companion__sprite--flip')}
          onAnimationEnd={handleAnimationEnd}
          data-testid="remi-companion-sprite"
        />
      </button>
    </div>
  );
}
