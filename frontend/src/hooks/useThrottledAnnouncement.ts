import { useEffect, useRef, useState } from 'react';

/** Coalesces rapidly changing visual feedback before it reaches a live region. */
export function useThrottledAnnouncement(message: string, intervalMs = 2_000): string {
  const [announced, setAnnounced] = useState(message);
  const latestRef = useRef(message);
  const lastAnnouncedAtRef = useRef(0);

  useEffect(() => {
    latestRef.current = message;
    if (message === announced) return undefined;
    const elapsed = Date.now() - lastAnnouncedAtRef.current;
    const wait = Math.max(0, intervalMs - elapsed);
    const timer = window.setTimeout(() => {
      lastAnnouncedAtRef.current = Date.now();
      setAnnounced(latestRef.current);
    }, wait);
    return () => window.clearTimeout(timer);
  }, [announced, intervalMs, message]);

  return announced;
}
