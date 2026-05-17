import { render, screen } from '@testing-library/react';
import RemiStreamCaret from './RemiStreamCaret';

describe('RemiStreamCaret', () => {
  it('renders a looping run sprite', () => {
    render(<RemiStreamCaret />);
    const sprite = screen.getByTestId('remi-stream-caret');
    expect(sprite).toHaveAttribute('data-clip', 'run');
    expect(sprite).toHaveClass('remi-stream-caret');
  });
});
