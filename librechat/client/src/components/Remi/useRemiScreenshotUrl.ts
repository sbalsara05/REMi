import { useEffect, useState } from 'react';
import { request } from 'librechat-data-provider';

function remiScreenshotPath(interactionId: string, index = 0) {
  const base = `/api/remi/interactions/${interactionId}/screenshot`;
  if (index <= 0) {
    return base;
  }
  return `${base}?index=${index}`;
}

type ScreenshotLoadState = 'idle' | 'loading' | 'ready' | 'missing';

/** Loads a REMi capture screenshot with auth headers (img src cannot send Bearer). */
export function useRemiScreenshotUrl(interactionId: string, enabled: boolean, index = 0) {
  const [url, setUrl] = useState<string | null>(null);
  const [state, setState] = useState<ScreenshotLoadState>('idle');

  useEffect(() => {
    if (!enabled) {
      setUrl(null);
      setState('idle');
      return;
    }

    let cancelled = false;
    setState('loading');
    setUrl(null);

    request
      .getResponse(remiScreenshotPath(interactionId, index), {
        responseType: 'blob',
        headers: { Accept: 'image/png, image/*' },
      })
      .then((response) => {
        if (cancelled) {
          return;
        }
        const contentType = String(response.headers['content-type'] ?? '');
        if (response.status !== 200 || !contentType.includes('image')) {
          setState('missing');
          setUrl(null);
          return;
        }
        const objectUrl = URL.createObjectURL(response.data);
        setUrl((prev) => {
          if (prev) {
            URL.revokeObjectURL(prev);
          }
          return objectUrl;
        });
        setState('ready');
      })
      .catch(() => {
        if (!cancelled) {
          setState('missing');
          setUrl(null);
        }
      });

    return () => {
      cancelled = true;
      setUrl((prev) => {
        if (prev) {
          URL.revokeObjectURL(prev);
        }
        return null;
      });
    };
  }, [interactionId, enabled, index]);

  return { url, state };
}
