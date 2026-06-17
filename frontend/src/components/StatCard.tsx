import type { LucideIcon } from 'lucide-react';
import { MetricTile } from './ui/AppPrimitives';

export function StatCard({ label, value, detail, icon: Icon }: { label: string; value: string; detail?: string; icon?: LucideIcon }) {
  return <MetricTile label={label} value={value} detail={detail} icon={Icon} />;
}
