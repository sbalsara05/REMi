import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { RecoilRoot } from 'recoil';
import { Constants } from 'librechat-data-provider';
import RemiCompanion, { useRemiCompanionVisible } from './RemiCompanion';

jest.mock('@librechat/client', () => ({
  ...jest.requireActual('@librechat/client'),
  useMediaQuery: () => true,
}));

jest.mock('~/data-provider', () => ({
  useGetStartupConfig: () => ({
    data: { interface: { remi: { companion: true } } },
  }),
}));

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
  it('hides on new conversation landing path', () => {
    expect(renderVisibleHook(`/c/${Constants.NEW_CONVO}`)).toBe(false);
  });

  it('shows on existing conversation path', () => {
    expect(renderVisibleHook('/c/abc123')).toBe(true);
  });

  it('renders companion sprite when enabled on chat route', () => {
    render(
      <RecoilRoot>
        <MemoryRouter initialEntries={['/c/abc123']}>
          <Routes>
            <Route path="/c/:conversationId" element={<RemiCompanion />} />
          </Routes>
        </MemoryRouter>
      </RecoilRoot>,
    );
    expect(screen.getByTestId('remi-companion')).toBeInTheDocument();
    expect(screen.getByTestId('remi-companion-sprite')).toBeInTheDocument();
  });
});
