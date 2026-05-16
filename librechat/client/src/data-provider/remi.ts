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
