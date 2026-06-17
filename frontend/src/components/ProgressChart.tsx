import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { ProgressPoint } from '../domain/types';

export function AccuracyLineChart({ data }: { data: ProgressPoint[] }) {
  return (
    <div className="chart-frame">
      <ResponsiveContainer width="100%" height={240}>
        <LineChart data={data}>
          <CartesianGrid stroke="#27313c" vertical={false} />
          <XAxis dataKey="period" stroke="#8795a5" tick={{ fontSize: 12 }} />
          <YAxis stroke="#8795a5" tick={{ fontSize: 12 }} />
          <Tooltip contentStyle={{ background: '#111820', border: '1px solid #2d3946', borderRadius: 8 }} />
          <Line type="monotone" dataKey="avg_abs_cents" stroke="#d9a441" strokeWidth={3} dot={{ r: 4 }} name="Avg abs cents" />
          <Line type="monotone" dataKey="in_tune_percentage" stroke="#5ec6a8" strokeWidth={2} dot={false} name="In-tune %" />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

export function PracticeBarChart({ data }: { data: ProgressPoint[] }) {
  return (
    <div className="chart-frame">
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={data}>
          <CartesianGrid stroke="#27313c" vertical={false} />
          <XAxis dataKey="period" stroke="#8795a5" tick={{ fontSize: 12 }} />
          <YAxis stroke="#8795a5" tick={{ fontSize: 12 }} />
          <Tooltip contentStyle={{ background: '#111820', border: '1px solid #2d3946', borderRadius: 8 }} />
          <Bar dataKey="practice_minutes" fill="#d9a441" radius={[4, 4, 0, 0]} name="Practice minutes" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

