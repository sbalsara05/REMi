import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import type { TRemiInteraction } from 'librechat-data-provider';
import { Skeleton, Spinner, useToastContext } from '@librechat/client';
import { WarningCircle } from '@phosphor-icons/react';
import { RemiMouse } from '~/components/Icons';
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
import { RemiBorderGlow } from '~/components/BorderGlow';
import RemiEmptyState from './RemiEmptyState';
import RemiContextButton from './RemiContextButton';
import RemiContextInspector from './RemiContextInspector';
import { useRemiPreviewStreaming } from './useRemiPreviewStreaming';
import { useRemiScreenshotUrl } from './useRemiScreenshotUrl';

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
  onViewContext,
}: {
  item: TRemiInteraction;
  index: number;
  disabled: boolean;
  onOpen: () => void;
  onViewContext: () => void;
}) {
  const preview = (item.responseSoFar || item.prompt || 'Interaction').trim();
  const isPreviewStreaming = useRemiPreviewStreaming(item.id, item.responseSoFar);
  const hasScreenshot = item.hasScreenshot ?? Boolean(item.screenshotPath);
  const screenshotSlots = Math.max(item.screenshotCount ?? 0, hasScreenshot ? 1 : 0);
  const hasContextBody = Boolean(
    screenshotSlots > 0 ||
      item.mergedContextText?.trim() ||
      item.hoveredText?.trim() ||
      item.prompt?.trim() ||
      item.responseSoFar?.trim(),
  );
  const contextCount = screenshotSlots > 0 ? screenshotSlots : hasContextBody ? 1 : 0;
  const { url: screenshotUrl, state: screenshotState } = useRemiScreenshotUrl(
    item.id,
    hasScreenshot,
  );

  const handleActivate = () => {
    if (disabled) {
      return;
    }
    onOpen();
  };

  return (
    <motion.article
      variants={glassCardVariants}
      whileHover={disabled ? undefined : glassCardHover}
      role="button"
      tabIndex={disabled ? -1 : 0}
      aria-disabled={disabled}
      aria-busy={disabled}
      onClick={handleActivate}
      onKeyDown={(event) => {
        if (disabled) {
          return;
        }
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onOpen();
        }
      }}
      className={cn(
        'relative z-[1] w-full',
        disabled ? 'cursor-wait opacity-80' : 'cursor-pointer',
      )}
      style={{ '--stagger-index': index } as React.CSSProperties}
    >
      <RemiBorderGlow
        variant="card"
        active={isPreviewStreaming}
        glowMode={isPreviewStreaming ? 'stream' : 'hover'}
        className="remi-radius-card w-full"
        innerClassName="overflow-hidden p-2.5 text-left"
      >
      <div className="mb-2 flex items-center justify-between gap-2 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5">
          <RemiMouse clip="idle" size="sm" className="pointer-events-none shrink-0" />
          <span>{formatRelativeTime(item.createdAt)}</span>
        </div>
        <div className="flex items-center gap-1.5">
          <RemiContextButton
            count={contextCount}
            disabled={disabled || !hasContextBody}
            className="pointer-events-auto"
            onClick={(event) => {
              event.stopPropagation();
              onViewContext();
            }}
          />
          <span
            className={cn(
              'rounded-full px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide',
              item.syncedToChat
                ? 'bg-surface-tertiary/80 text-text-secondary'
                : isPreviewStreaming
                  ? 'bg-brand-purple/20 text-brand-purple'
                  : 'bg-brand-purple/15 text-brand-purple',
            )}
          >
            {item.syncedToChat ? 'In chat' : isPreviewStreaming ? 'Streaming' : 'Ready'}
          </span>
        </div>
      </div>
      {hasScreenshot && screenshotState !== 'missing' && (
        <div className="remi-radius-control pointer-events-none mb-2 overflow-hidden border border-white/10 shadow-inner">
          {screenshotUrl ? (
            <img
              src={screenshotUrl}
              alt=""
              className="aspect-video w-full object-cover object-top"
            />
          ) : (
            <Skeleton className="aspect-video w-full" />
          )}
        </div>
      )}
      <p
        className={cn(
          'pointer-events-none mb-2.5 line-clamp-3 text-sm leading-snug text-text-primary',
          isPreviewStreaming && 'remi-preview-streaming',
        )}
      >
        {preview}
      </p>
      <span
        className={cn(
          'pointer-events-none inline-flex h-9 w-full items-center justify-center rounded-lg px-3 text-sm font-medium',
          item.syncedToChat
            ? 'border border-border-medium bg-transparent text-text-primary'
            : 'bg-primary text-primary-foreground',
        )}
      >
        {disabled ? <Spinner className="size-4" /> : item.syncedToChat ? 'Open chat' : 'Open in chat'}
      </span>
      </RemiBorderGlow>
    </motion.article>
  );
}

function MouseHistoryChrome({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative z-[1] flex flex-col">
      <div className="mb-3 flex items-center gap-2 px-3 pt-2">
        <RemiMouse clip="attackSide" size="md" className="pointer-events-none" />
        <div className="mouse-stripe-divider min-w-0 flex-1 shrink-0" aria-hidden />
      </div>
      {children}
    </div>
  );
}

export default function MouseHistoryPanel() {
  const localize = useLocalize();
  const navigate = useNavigate();
  const { showToast } = useToastContext();
  const [openingId, setOpeningId] = useState<string | null>(null);
  const [contextInspectorItem, setContextInspectorItem] = useState<TRemiInteraction | null>(null);
  const { data, isLoading, isError, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useRemiInteractionsInfiniteQuery();
  const handoff = useRemiHandoffMutation();

  const interactions = useMemo(
    () => data?.pages.flatMap((page) => page.interactions) ?? [],
    [data?.pages],
  );

  const onOpenInChat = async (interactionId: string, existingConvoId?: string | null) => {
    setOpeningId(interactionId);
    try {
      if (existingConvoId) {
        navigate(`/c/${existingConvoId}`);
        return;
      }
      const result = await handoff.mutateAsync(interactionId);
      navigate(`/c/${result.conversationId}`);
    } catch {
      showToast({
        message: localize('com_ui_error') ?? 'Could not open capture in chat.',
        status: 'error',
      });
    } finally {
      setOpeningId(null);
    }
  };

  if (isLoading) {
    return (
      <MouseHistoryChrome>
        <div className="flex flex-col gap-2 px-3 pb-3 pt-0">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="glass-card remi-radius-card h-36 w-full" />
          ))}
        </div>
      </MouseHistoryChrome>
    );
  }

  if (isError) {
    return (
      <MouseHistoryChrome>
        <div className="px-3 pb-3 pt-0">
          <RemiBorderGlow
            variant="card"
            className="remi-radius-card w-full"
            innerClassName="flex flex-col items-center gap-2 p-4 text-center"
          >
            <WarningCircle className="size-8 text-text-destructive" weight="regular" />
            <p className="text-sm text-text-secondary">
              {localize('com_ui_error') ?? 'Could not load capture history.'}
            </p>
          </RemiBorderGlow>
        </div>
      </MouseHistoryChrome>
    );
  }

  if (interactions.length === 0) {
    return (
      <MouseHistoryChrome>
        <div className="px-3 pb-3 pt-0">
          <RemiEmptyState />
        </div>
      </MouseHistoryChrome>
    );
  }

  return (
    <MouseHistoryChrome>
      <RemiContextInspector
        item={contextInspectorItem}
        open={contextInspectorItem != null}
        onOpenChange={(open) => {
          if (!open) {
            setContextInspectorItem(null);
          }
        }}
      />
      <div className="relative z-[1] flex max-h-[70vh] flex-col px-3 pb-3 pt-0">
        <motion.div
          className="glass-stagger pointer-events-auto flex flex-col gap-2 overflow-y-auto"
          variants={glassStaggerContainer}
          initial="hidden"
          animate="visible"
        >
          {interactions.map((item, index) => (
            <RemiInteractionCard
              key={item.id}
              item={item}
              index={index}
              disabled={openingId === item.id}
              onOpen={() => onOpenInChat(item.id, item.conversationId)}
              onViewContext={() => setContextInspectorItem(item)}
            />
          ))}
        </motion.div>
        {hasNextPage && (
          <RemiBorderGlow
            variant="popover"
            className="remi-radius-control mt-2 w-full"
            innerClassName="overflow-hidden"
          >
            <button
              type="button"
              className="inline-flex h-9 w-full items-center justify-center px-3 text-sm font-medium text-text-primary hover:bg-surface-hover"
              disabled={isFetchingNextPage}
              onClick={() => fetchNextPage()}
            >
              {isFetchingNextPage ? <Spinner className="size-4" /> : 'Load more'}
            </button>
          </RemiBorderGlow>
        )}
      </div>
    </MouseHistoryChrome>
  );
}
