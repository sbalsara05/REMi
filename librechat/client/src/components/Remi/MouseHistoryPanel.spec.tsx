import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import MouseHistoryPanel from './MouseHistoryPanel';

const mockNavigate = jest.fn();
const mockMutateAsync = jest.fn();
const mockFetchNextPage = jest.fn();

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

jest.mock('framer-motion', () => ({
  motion: {
    div: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => (
      <div {...props}>{children}</div>
    ),
    article: ({ children, ...props }: React.HTMLAttributes<HTMLElement>) => (
      <article {...props}>{children}</article>
    ),
  },
}));

jest.mock('~/hooks', () => ({
  useLocalize: () => (key: string) => key,
}));

jest.mock('~/data-provider', () => ({
  useRemiInteractionsInfiniteQuery: jest.fn(),
  useRemiHandoffMutation: jest.fn(),
}));

const { useRemiInteractionsInfiniteQuery, useRemiHandoffMutation } =
  jest.requireMock('~/data-provider');

function renderPanel() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <MouseHistoryPanel />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('MouseHistoryPanel', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockMutateAsync.mockResolvedValue({ conversationId: 'convo-new', alreadySynced: false });
    mockFetchNextPage.mockResolvedValue(undefined);
    useRemiHandoffMutation.mockReturnValue({
      mutateAsync: mockMutateAsync,
      isLoading: false,
    });
  });

  it('shows skeleton placeholders while interactions load', () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    expect(screen.queryByText('com_remi_empty_title')).not.toBeInTheDocument();
    expect(screen.queryByText('com_ui_error')).not.toBeInTheDocument();
  });

  it('shows an error message when the query fails', () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: undefined,
      isLoading: false,
      isError: true,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    expect(screen.getByText('com_ui_error')).toBeInTheDocument();
  });

  it('shows the empty state when there are no interactions', () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: { pages: [{ interactions: [], nextCursor: null }] },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    expect(screen.getByText('com_remi_empty_title')).toBeInTheDocument();
  });

  it('navigates directly when the interaction already has a conversation', async () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: {
        pages: [
          {
            interactions: [
              {
                id: 'synced-1',
                createdAt: Date.now(),
                prompt: 'Synced prompt',
                responseSoFar: null,
                screenshotPath: null,
                model: null,
                cropHash: null,
                syncedToChat: true,
                conversationId: 'convo-existing',
              },
            ],
            nextCursor: null,
          },
        ],
      },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    await userEvent.click(screen.getByRole('button', { name: 'Open chat' }));

    expect(mockMutateAsync).not.toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenCalledWith('/c/convo-existing');
  });

  it('hands off then navigates for unsynced interactions', async () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: {
        pages: [
          {
            interactions: [
              {
                id: 'fresh-1',
                createdAt: Date.now(),
                prompt: 'Fresh prompt',
                responseSoFar: 'Partial',
                screenshotPath: '/tmp/shot.png',
                model: null,
                cropHash: null,
                syncedToChat: false,
                conversationId: null,
              },
            ],
            nextCursor: null,
          },
        ],
      },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    await userEvent.click(screen.getByRole('button', { name: 'Open in chat' }));

    await waitFor(() => {
      expect(mockMutateAsync).toHaveBeenCalledWith('fresh-1');
      expect(mockNavigate).toHaveBeenCalledWith('/c/convo-new');
    });
  });

  it('renders the REMi ASCII mouse on interaction cards', () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: {
        pages: [
          {
            interactions: [
              {
                id: 'glyph-1',
                createdAt: Date.now(),
                prompt: 'Prompt',
                responseSoFar: null,
                screenshotPath: null,
                model: null,
                cropHash: null,
                syncedToChat: false,
                conversationId: null,
              },
            ],
            nextCursor: null,
          },
        ],
      },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    renderPanel();
    expect(screen.getAllByTestId('remi-ascii-mouse').length).toBeGreaterThan(0);
  });

  it('applies preview streaming class when responseSoFar grows', async () => {
    let responseSoFar: string | null = 'Partial';

    useRemiInteractionsInfiniteQuery.mockImplementation(() => ({
      data: {
        pages: [
          {
            interactions: [
              {
                id: 'stream-1',
                createdAt: Date.now(),
                prompt: null,
                responseSoFar,
                screenshotPath: null,
                model: null,
                cropHash: null,
                syncedToChat: false,
                conversationId: null,
              },
            ],
            nextCursor: null,
          },
        ],
      },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    }));

    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });

    const { rerender } = render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <MouseHistoryPanel />
        </MemoryRouter>
      </QueryClientProvider>,
    );

    responseSoFar = 'Partial response growing';
    rerender(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <MouseHistoryPanel />
        </MemoryRouter>
      </QueryClientProvider>,
    );

    await waitFor(() => {
      expect(document.querySelector('.remi-preview-streaming')).toBeInTheDocument();
    });
  });

  it('shows mouse stripe divider chrome', () => {
    useRemiInteractionsInfiniteQuery.mockReturnValue({
      data: { pages: [{ interactions: [], nextCursor: null }] },
      isLoading: false,
      isError: false,
      fetchNextPage: mockFetchNextPage,
      hasNextPage: false,
      isFetchingNextPage: false,
    });

    const { container } = renderPanel();
    expect(container.querySelector('.mouse-stripe-divider')).toBeInTheDocument();
  });
});
