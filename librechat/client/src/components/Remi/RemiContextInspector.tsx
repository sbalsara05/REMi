import type { TRemiInteraction } from 'librechat-data-provider';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  Skeleton,
} from '@librechat/client';
import { RemiBorderGlow } from '~/components/BorderGlow';
import { useRemiScreenshotUrl } from './useRemiScreenshotUrl';

function RemiInspectorScreenshot({
  interactionId,
  index,
  label,
}: {
  interactionId: string;
  index: number;
  label: string;
}) {
  const { url, state } = useRemiScreenshotUrl(interactionId, true, index);

  if (state === 'missing') {
    return null;
  }

  return (
    <figure className="space-y-1.5">
      <figcaption className="text-[11px] font-semibold uppercase tracking-wide text-text-secondary">
        {label}
      </figcaption>
      <div className="remi-radius-control overflow-hidden border border-white/10 shadow-inner">
        {url ? (
          <img src={url} alt="" className="max-h-56 w-full object-contain object-top bg-black/20" />
        ) : (
          <Skeleton className="aspect-video w-full" />
        )}
      </div>
    </figure>
  );
}

function ContextTextBlock({ title, body }: { title: string; body: string }) {
  return (
    <section className="space-y-1">
      <h3 className="text-[11px] font-semibold uppercase tracking-wide text-text-secondary">
        {title}
      </h3>
      <pre className="max-h-40 overflow-auto whitespace-pre-wrap rounded-lg border border-white/10 bg-surface-tertiary/40 p-2.5 text-xs leading-relaxed text-text-primary">
        {body}
      </pre>
    </section>
  );
}

type RemiContextInspectorProps = {
  item: TRemiInteraction | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

export default function RemiContextInspector({
  item,
  open,
  onOpenChange,
}: RemiContextInspectorProps) {
  const screenshotCount = Math.max(
    item?.screenshotCount ?? 0,
    item?.hasScreenshot ? 1 : 0,
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton
        className="max-h-[85vh] max-w-lg overflow-hidden p-0"
        disableScroll={false}
      >
        <RemiBorderGlow
          variant="popover"
          className="remi-radius-card w-full"
          innerClassName="flex max-h-[85vh] flex-col overflow-hidden"
        >
          <div className="flex items-center gap-2 border-b border-white/10 bg-surface-tertiary/30 px-3 py-2.5">
            <div className="flex items-center gap-1.5" aria-hidden>
              <span className="size-3 rounded-full bg-[#ff5f57]" />
              <span className="size-3 rounded-full bg-[#febc2e]" />
              <span className="size-3 rounded-full bg-[#28c840]/80" />
            </div>
            <DialogHeader className="min-w-0 flex-1 space-y-0 text-left">
              <DialogTitle className="truncate text-sm font-semibold">Context</DialogTitle>
            </DialogHeader>
          </div>

          <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-3">
            {!item ? null : (
              <>
                {item.appName && (
                  <p className="text-xs text-text-secondary">
                    <span className="font-medium text-text-primary">App:</span> {item.appName}
                  </p>
                )}

                {screenshotCount > 0 && (
                  <div className="space-y-3">
                    {Array.from({ length: screenshotCount }, (_, index) => (
                      <RemiInspectorScreenshot
                        key={`${item.id}-${index}`}
                        interactionId={item.id}
                        index={index}
                        label={screenshotCount === 1 ? 'Screenshot' : `Screenshot ${index + 1}`}
                      />
                    ))}
                  </div>
                )}

                {item.mergedContextText?.trim() && (
                  <ContextTextBlock title="Merged context" body={item.mergedContextText.trim()} />
                )}
                {item.hoveredText?.trim() &&
                  item.hoveredText.trim() !== item.mergedContextText?.trim() && (
                    <ContextTextBlock title="Captured text" body={item.hoveredText.trim()} />
                  )}
                {item.prompt?.trim() && (
                  <ContextTextBlock title="Prompt" body={item.prompt.trim()} />
                )}
                {item.responseSoFar?.trim() && (
                  <ContextTextBlock title="Response" body={item.responseSoFar.trim()} />
                )}

                {screenshotCount === 0 &&
                  !item.mergedContextText?.trim() &&
                  !item.hoveredText?.trim() &&
                  !item.prompt?.trim() && (
                    <p className="text-sm text-text-secondary">No context stored for this capture.</p>
                  )}
              </>
            )}
          </div>
        </RemiBorderGlow>
      </DialogContent>
    </Dialog>
  );
}
