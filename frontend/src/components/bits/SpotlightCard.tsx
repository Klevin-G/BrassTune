import { useRef, type ReactNode } from 'react';
import './SpotlightCard.css';

/**
 * A card with a soft gold spotlight that follows the cursor, via CSS custom
 * properties (zero dependencies). Adapted from the React Bits SpotlightCard
 * pattern and rethemed to BrassTune tokens. Falls back gracefully to a plain
 * card when the pointer never moves (touch, keyboard).
 */
export function SpotlightCard({ children, className = '' }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement | null>(null);
  const onMove = (event: React.MouseEvent<HTMLDivElement>) => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    el.style.setProperty('--spot-x', `${event.clientX - rect.left}px`);
    el.style.setProperty('--spot-y', `${event.clientY - rect.top}px`);
  };
  return (
    <div ref={ref} className={`spotlight-card ${className}`} onMouseMove={onMove}>
      {children}
    </div>
  );
}
