import { clipAnimationDurationMs } from '~/components/Icons/mouseSpriteCatalog';
import { playSpriteSequence } from './spriteSequences';

describe('spriteSequences', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('plays one-shot steps in order then calls onDone', () => {
    const playClip = jest.fn();
    const onDone = jest.fn();

    playSpriteSequence(
      [{ clip: 'jump' }, { clip: 'land' }],
      playClip,
      onDone,
    );

    expect(playClip).toHaveBeenCalledWith('jump', true);
    expect(onDone).not.toHaveBeenCalled();

    jest.advanceTimersByTime(clipAnimationDurationMs('jump') + 50);
    expect(playClip).toHaveBeenCalledWith('land', true);

    jest.advanceTimersByTime(clipAnimationDurationMs('land') + 50);
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it('stops on loop step without calling onDone', () => {
    const playClip = jest.fn();
    const onDone = jest.fn();

    playSpriteSequence([{ clip: 'idle', loop: true }], playClip, onDone);

    expect(playClip).toHaveBeenCalledWith('idle', false);
    jest.advanceTimersByTime(5000);
    expect(onDone).not.toHaveBeenCalled();
  });

  it('cancel prevents further steps', () => {
    const playClip = jest.fn();
    const controller = playSpriteSequence([{ clip: 'jump' }, { clip: 'run' }], playClip);

    expect(playClip).toHaveBeenCalledTimes(1);
    controller.cancel();
    jest.advanceTimersByTime(clipAnimationDurationMs('jump') + 100);
    expect(playClip).toHaveBeenCalledTimes(1);
  });
});
