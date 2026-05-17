import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { RecoilRoot } from 'recoil';
import { Constants } from 'librechat-data-provider';
import EmptyText from '~/components/Chat/Messages/Content/Parts/EmptyText';
import RemiCompanion, { useRemiCompanionVisible } from './RemiCompanion';

function renderVisibleHook(path: string) {
  let visible = false;
  function Probe() {
    visible = useRemiCompanionVisible(true);
    return null;
  }
  render(
    <RecoilRoot>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/c/:conversationId?" element={<Probe />} />
        </Routes>
      </MemoryRouter>
    </RecoilRoot>,
  );
  return visible;
}

describe('RemiCompanion', () => {
  it('is disabled (no corner overlay)', () => {
    expect(renderVisibleHook('/c/abc123')).toBe(false);
    expect(renderVisibleHook(`/c/${Constants.NEW_CONVO}`)).toBe(false);
  });

  it('never renders the fixed corner element', () => {
    render(
      <RecoilRoot>
        <RemiCompanion />
      </RecoilRoot>,
    );
    expect(screen.queryByTestId('remi-companion')).not.toBeInTheDocument();
  });
});

describe('stream caret placement', () => {
  it('renders running sprite in the empty streaming placeholder', () => {
    render(<EmptyText />);
    expect(screen.getByTestId('remi-stream-caret')).toHaveAttribute('data-clip', 'run');
  });
});
