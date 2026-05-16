import { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import type { TRemiInteraction } from 'librechat-data-provider';
import { Button, Skeleton, Spinner } from '@librechat/client';
import { CursorClick, WarningCircle } from '~/components/Icons';
import {
  glassCardHover,
  glassCardVariants,
  glassStaggerContainer,
} from '~/components/Glass/GlassMotion';
import {
  useRemiHandoffMutation,
  useRemiInteractionsInfiniteQuery,
} from '~/data-provider';
import { useLocalize } from '~/hooks';
import { cn } from '~/utils';
import RemiEmptyState from './RemiEmptyState';

function formatRelativeTime(createdAt: number) {
  const diffMs = Date.now() - createdAt;
  const diffMin = Math.round(diffMs / 60000);
  if (diffMin < 1) {
    return 'Just now';
  }
  if (diffMin < 60) {
    return `${diffMin}m ago`;
  }
  const diffHr = Math.round(diffMin / 60);
  if (diffHr < 24) {
    return `${diffHr}h ago`;
  }
  return new Date(createdAt).toLocaleDateString();
}

function RemiInteractionCard({
  item,
  index,
  disabled,
  onOpen,
}: {
  item: TRemiInteraction;
  index: number;
  disabled: boolean;
  onOpen: () => void;
}) {
  const preview = (item.prompt || item.responseSoFar || 'Interaction').trim();
  const screenshotUrl = item.screenshotPath
    ? `/api/remi/interactions/${item.id}/screenshot`
    : null;

  return (
    <motion.article
      variants={glassCardVariants}
      whileHover={glassCardHover}
      className="glass-card overflow-hidden rounded-2xl p-2.5"
      style={{ '--stagger-index': index } as React.CSSProperties}
    >
      <div className="mb-2 flex items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5">
          <CursorClick className="h-3.5 w-3.5 shrink-0 text-brand-purple" weight="duotone" />
          <span>{formatRelativeTime(item.createdAt)}</span>
        </div>
        <span
          className={cn(
            'rounded-full px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide',
            item.syncedToChat
              ? 'bg-surface-tertiary/80 text-text-secondary'
              : 'bg-brand-purple/15 text-brand-purple',
          )}
        >
          {item.syncedToChat ? 'In chat' : 'Ready'}
        </span>
      </div>
      {screenshotUrl && (
        <motion.div
          className="mb-2 overflow-hidden rounded-xl border border-white/10 shadow-inner"
          layoutId={`remi-shot-${item.id}`}
        >
          <img
            src={screenshotUrl}
            alt=""
            className="aspect-video w-full object-cover object-top"
          />
        </motion.div>
      )}
      <p className="mb-2.5 line-clamp-3 text-sm leading-snug text-text-primary">{preview}</p>
      <Button
        type="button"
        size="sm"
        variant={item.syncedToChat ? 'outline' : 'default'}
        className="w-full"
        disabled={disabled}
        onClick={onOpen}
      >
        {item.syncedToChat ? 'Open chat' : 'Open in chat'}
      </Button>
    </motion.article>
  );
}

export default function MouseHistoryPanel() {
  const localize = useLocalize();
  const navigate = useNavigate();
  const { data, isLoading, isError, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useRemiInteractionsInfiniteQuery();
  const handoff = useRemiHandoffMutation();

  const interactions = useMemo(
    () => data?.pages.flatMap((page) => page.interactions) ?? [],
    [data?.pages],
  );

  const onOpenInChat = async (interactionId: string, existingConvoId?: string | null) => {
    if (existingConvoId) {
      navigate(`/c/${existingConvoId}`);
      return;
    }
    const result = await handoff.mutateAsync(interactionId);
    navigate(`/c/${result.conversationId}`);
  };

  if (isLoading) {
    return (
      <motion.div
        className="flex flex-col gap-2 px-3 pb-3 pt-2"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
      >
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="glass-card h-36 w-full rounded-2xl" />
        ))}
      </motion.div>
    );
  }

  if (isError) {
    return (
      <div className="px-3 pb-3 pt-2">
        <div className="glass-card flex flex-col items-center gap-2 rounded-2xl p-4 text-center">
          <WarningCircle className="size-8 text-text-destructive" weight="regular" />
          <p className="text-sm text-text-secondary">
            {localize('com_ui_error') ?? 'Could not load capture history.'}
          </p>
        </div>
      </div>
    );
  }

  if (interactions.length === 0) {
    return (
      <div className="px-3 pb-3 pt-2">
        <RemiEmptyState />
      </div>
    );
  }

  return (
    <div className="flex max-h-[70vh] flex-col px-3 pb-3 pt-2">
      <motion.div
        className="glass-stagger flex flex-col gap-2 overflow-y-auto"
        variants={glassStaggerContainer}
        initial="hidden"
        animate="visible"
      >
        {interactions.map((item, index) => (
          <RemiInteractionCard
            key={item.id}
            item={item}
            index={index}
            disabled={handoff.isLoading}
            onOpen={() => onOpenInChat(item.id, item.conversationId)}
          />
        ))}
      </motion.div>
      {hasNextPage && (
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="glass-popover mt-2 w-full"
          disabled={isFetchingNextPage}
          onClick={() => fetchNextPage()}
        >
          {isFetchingNextPage ? <Spinner className="size-4" /> : 'Load more'}
        </Button>
      )}
    </div>
  );
}
