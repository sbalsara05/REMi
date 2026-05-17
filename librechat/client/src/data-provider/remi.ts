import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  QueryKeys,
  dataService,
  type TRemiInteractionsResponse,
} from 'librechat-data-provider';
import type { UseMutationResult, UseQueryOptions, QueryObserverResult } from '@tanstack/react-query';

export const useRemiInteractionsQuery = (
  config?: UseQueryOptions<TRemiInteractionsResponse>,
): QueryObserverResult<TRemiInteractionsResponse> => {
  return useQuery<TRemiInteractionsResponse>(
    [QueryKeys.remiInteractions],
    () => dataService.listRemiInteractions({ limit: 50 }),
    {
      refetchOnWindowFocus: true,
      ...config,
    },
  );
};

const REMI_LIVE_POLL_MS = 500;
const REMI_RECENT_CAPTURE_MS = 5 * 60 * 1000;

function hasRecentUnsyncedCapture(interactions: { createdAt: number; syncedToChat: boolean }[]) {
  const cutoff = Date.now() - REMI_RECENT_CAPTURE_MS;
  return interactions.some((item) => !item.syncedToChat && item.createdAt >= cutoff);
}

export const useRemiInteractionsInfiniteQuery = () => {
  return useInfiniteQuery<TRemiInteractionsResponse>(
    [QueryKeys.remiInteractions, 'infinite'],
    ({ pageParam }) =>
      dataService.listRemiInteractions({
        cursor: (pageParam as string | undefined) ?? undefined,
        limit: 25,
      }),
    {
      getNextPageParam: (lastPage) => lastPage.nextCursor ?? undefined,
      refetchOnWindowFocus: true,
      refetchInterval: (data) => {
        const interactions = data?.pages.flatMap((page) => page.interactions) ?? [];
        return hasRecentUnsyncedCapture(interactions) ? REMI_LIVE_POLL_MS : false;
      },
    },
  );
};

export const useRemiHandoffMutation = (): UseMutationResult<
  { conversationId: string; alreadySynced?: boolean },
  unknown,
  string
> => {
  const queryClient = useQueryClient();
  return useMutation((interactionId: string) => dataService.postRemiHandoff(interactionId), {
    onSuccess: () => {
      queryClient.invalidateQueries([QueryKeys.remiInteractions]);
      queryClient.invalidateQueries([QueryKeys.remiInteractions, 'infinite']);
      queryClient.invalidateQueries([QueryKeys.allConversations]);
    },
  });
};
