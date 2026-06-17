import type { LucideIcon } from 'lucide-react';

export function StatCard({ label, value, detail, icon: Icon }: { label: string; value: string; detail?: string; icon?: LucideIcon }) {
  return (
    <section className="stat-card">
      <div>
        <p>{label}</p>
        <strong>{value}</strong>
        {detail && <span>{detail}</span>}
      </div>
      {Icon && (
        <div className="stat-icon">
          <Icon size={19} />
        </div>
      )}
    </section>
  );
}

