import { render, screen } from '@testing-library/react';
import RemiSprite from './RemiSprite';

describe('RemiSprite', () => {
  it('renders with default test id and clip', () => {
    render(<RemiSprite clip="walkFront" />);
    const el = screen.getByTestId('remi-sprite-mouse');
    expect(el).toHaveAttribute('data-clip', 'walkFront');
    expect(el).toHaveClass('remi-sprite');
  });

  it('pauses animation when playing is false', () => {
    render(<RemiSprite playing={false} />);
    expect(screen.getByTestId('remi-sprite-mouse')).toHaveClass('remi-sprite--paused');
  });

  it('exposes accessible label via title', () => {
    render(<RemiSprite title="REMi" />);
    expect(screen.getByRole('img', { name: 'REMi' })).toBeInTheDocument();
  });
});
