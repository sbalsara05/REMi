import { useEffect, useRef, useState } from 'react';

const PREVIEW_STREAM_MS = 600;

/**
 * Returns true briefly when responseSoFar length grows (overlay push / refetch).
 */
export function useRemiPreviewStreaming(interactionId: string, responseSoFar: string | null) {
  const length = (responseSoFar ?? '').length;
  const prevLengths = useRef<Map<string, number>>(new Map());
  const [isStreaming, setIsStreaming] = useState(false);

  useEffect(() => {
    const prev = prevLengths.current.get(interactionId) ?? 0;
    if (length > prev && prev > 0) {
      setIsStreaming(true);
      const timer = window.setTimeout(() => setIsStreaming(false), PREVIEW_STREAM_MS);
      prevLengths.current.set(interactionId, length);
      return () => window.clearTimeout(timer);
    }
    prevLengths.current.set(interactionId, length);
    return undefined;
  }, [interactionId, length]);

  return isStreaming;
}
