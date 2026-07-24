import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';

type Tone = 'default' | 'gold' | 'green' | 'amber' | 'orange' | 'red' | 'muted';

function cx(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(' ');
}

export function ScreenContainer({
  children,
  className,
  density = 'standard',
}: {
  children: ReactNode;
  className?: string;
  density?: 'standard' | 'compact';
}) {
  return <div className={cx('screen-container', density === 'compact' && 'screen-container-compact', className)}>{children}</div>;
}

export function PageHeader({
  eyebrow,
  title,
  description,
  action,
  meta,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  action?: ReactNode;
  meta?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h1>{title}</h1>
        {description && <p>{description}</p>}
        {meta && <div className="page-header-meta">{meta}</div>}
      </div>
      {action && <div className="page-header-action">{action}</div>}
    </header>
  );
}

export function SectionCard({
  children,
  className,
  title,
  eyebrow,
  action,
}: {
  children: ReactNode;
  className?: string;
  title?: string;
  eyebrow?: string;
  action?: ReactNode;
}) {
  return (
    <section className={cx('section-card', className)}>
      {(title || eyebrow || action) && (
        <div className="section-card-heading">
          <div>
            {eyebrow && <p className="eyebrow">{eyebrow}</p>}
            {title && <h2>{title}</h2>}
          </div>
          {action && <div className="section-card-action">{action}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

export function GlassPanel({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cx('glass-panel', className)}>{children}</div>;
}

export function MetricTile({
  label,
  value,
  detail,
  icon: Icon,
  tone = 'default',
}: {
  label: string;
  value: ReactNode;
  detail?: ReactNode;
  icon?: LucideIcon;
  tone?: Tone;
}) {
  return (
    <section className={cx('metric-tile', `tone-${tone}`)}>
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
        {detail && <span>{detail}</span>}
      </div>
      {Icon && (
        <div className="tile-icon">
          <Icon size={19} />
        </div>
      )}
    </section>
  );
}

export function ActionTile({
  title,
  detail,
  icon: Icon,
  to,
  onClick,
}: {
  title: string;
  detail: string;
  icon?: LucideIcon;
  to?: string;
  onClick?: () => void;
}) {
  const content = (
    <>
      {Icon && (
        <span className="action-icon">
          <Icon size={19} />
        </span>
      )}
      <span>
        <strong>{title}</strong>
        <em>{detail}</em>
      </span>
    </>
  );

  if (to) {
    return (
      <a className="action-tile" href={to}>
        {content}
      </a>
    );
  }

  return (
    <button className="action-tile" onClick={onClick} type="button">
      {content}
    </button>
  );
}

export function InsightCard({
  title,
  body,
  detail,
  icon: Icon,
  tone = 'default',
  children,
}: {
  title: string;
  body?: string;
  detail?: string;
  icon?: LucideIcon;
  tone?: Tone;
  children?: ReactNode;
}) {
  return (
    <article className={cx('insight-card', `tone-${tone}`)}>
      <div className="insight-heading">
        {Icon && (
          <span className="insight-icon">
            <Icon size={18} />
          </span>
        )}
        <div>
          <h3>{title}</h3>
          {detail && <span>{detail}</span>}
        </div>
      </div>
      {body && <p>{body}</p>}
      {children}
    </article>
  );
}

export function StatusBadge({ children, tone = 'default' }: { children: ReactNode; tone?: Tone }) {
  return <span className={cx('status-badge', `tone-${tone}`)}>{children}</span>;
}

export function SelectionChip({
  children,
  active,
  onClick,
  tone = 'default',
}: {
  children: ReactNode;
  active?: boolean;
  onClick?: () => void;
  tone?: Tone;
}) {
  return (
    <button aria-pressed={active} className={cx('selection-chip', active && 'active', `tone-${tone}`)} onClick={onClick} type="button">
      {children}
    </button>
  );
}

export function SegmentedControl<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
}: {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  ariaLabel: string;
}) {
  function moveSelection(index: number, event: React.KeyboardEvent<HTMLButtonElement>) {
    const keyOffsets: Partial<Record<React.KeyboardEvent['key'], number>> = {
      ArrowLeft: -1,
      ArrowUp: -1,
      ArrowRight: 1,
      ArrowDown: 1,
    };
    let nextIndex: number | undefined;
    if (event.key === 'Home') nextIndex = 0;
    else if (event.key === 'End') nextIndex = options.length - 1;
    else if (keyOffsets[event.key]) {
      nextIndex = (index + keyOffsets[event.key]! + options.length) % options.length;
    }
    if (nextIndex === undefined) return;

    event.preventDefault();
    onChange(options[nextIndex].value);
    const buttons = event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>('[role="radio"]');
    buttons?.[nextIndex]?.focus();
  }

  return (
    <div className="segmented-control" role="radiogroup" aria-label={ariaLabel}>
      {options.map((option, index) => (
        <button
          aria-checked={value === option.value}
          className={value === option.value ? 'active' : ''}
          key={option.value}
          onClick={() => onChange(option.value)}
          onKeyDown={(event) => moveSelection(index, event)}
          role="radio"
          tabIndex={value === option.value ? 0 : -1}
          type="button"
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function FloatingTabBar({ children, ariaLabel }: { children: ReactNode; ariaLabel: string }) {
  return <nav className="floating-tabbar" aria-label={ariaLabel}>{children}</nav>;
}

export function BottomActionBar({ children }: { children: ReactNode }) {
  return <div className="bottom-action-bar">{children}</div>;
}

export function EmptyActionState({
  title,
  body,
  action,
  icon: Icon,
}: {
  title: string;
  body: string;
  action?: ReactNode;
  icon?: LucideIcon;
}) {
  return (
    <div className="empty-action-state">
      {Icon && (
        <span>
          <Icon size={24} />
        </span>
      )}
      <h3>{title}</h3>
      <p>{body}</p>
      {action}
    </div>
  );
}

export function LoadingSkeleton({ rows = 3, label }: { rows?: number; label: string }) {
  return (
    <div className="loading-skeleton" role="status" aria-live="polite" aria-label={label}>
      {Array.from({ length: rows }).map((_, index) => (
        <span key={index} />
      ))}
    </div>
  );
}
