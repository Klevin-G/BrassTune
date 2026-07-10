import { useEffect, useRef, useState } from 'react';
import { useReducedMotion } from './useReducedMotion';

/**
 * Spring-free animated number, zero dependencies. Counts from 0 (or `from`) to
 * `value` once on mount / when `value` changes. Respects reduced-motion by
 * snapping straight to the final value. Used sparingly as feedback (e.g. a
 * Play-Along score reveal or a streak count), not as decoration.
 */
export function CountUp({
  value,
  from = 0,
  durationMs = 900,
  decimals = 0,
  suffix = '',
  prefix = '',
}: {
  value: number;
  from?: number;
  durationMs?: number;
  decimals?: number;
  suffix?: string;
  prefix?: string;
}) {
  const reduced = useReducedMotion();
  const [display, setDisplay] = useState(reduced ? value : from);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (reduced) {
      setDisplay(value);
      return;
    }
    const start = performance.now();
    const startVal = from;
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / durationMs);
      // easeOutCubic
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(startVal + (value - startVal) * eased);
      if (t < 1) rafRef.current = requestAnimationFrame(step);
    };
    rafRef.current = requestAnimationFrame(step);
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, [value, from, durationMs, reduced]);

  return (
    <span>
      {prefix}
      {display.toFixed(decimals)}
      {suffix}
    </span>
  );
}
