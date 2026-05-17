import RemiSprite from '~/components/Icons/RemiSprite';
import { cn } from '~/utils';
import { STREAM_CARET_CLIP, STREAM_CARET_SCALE } from './remiStreamCaretCss';

type RemiStreamCaretProps = {
  className?: string;
  'data-testid'?: string;
};

/** Inline running mouse shown while waiting for or receiving streamed tokens. */
export default function RemiStreamCaret({
  className,
  'data-testid': dataTestId = 'remi-stream-caret',
}: RemiStreamCaretProps) {
  return (
    <RemiSprite
      clip={STREAM_CARET_CLIP}
      scale={STREAM_CARET_SCALE}
      playing
      loop
      className={cn('remi-stream-caret', className)}
      aria-hidden
      data-testid={dataTestId}
    />
  );
}
