import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useEffect, useState } from 'react';
import { getHeatmap, getNoteStats } from '../api/client';
import { DateRangeFilter } from '../components/DateRangeFilter';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { NoteStatsTable } from '../components/NoteStatsTable';
import type { NoteStats } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';

export function AnalyticsPage() {
  const { instrumentId, setInstrumentId } = useAppSettings();
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  useEffect(() => {
    Promise.all([getNoteStats(instrumentId), getHeatmap(instrumentId)]).then(([noteData, heatmapData]) => {
      setStats(noteData);
      setHeatmap(heatmapData);
    });
  }, [instrumentId]);
  const worst = [...stats].sort((a, b) => b.problem_severity - a.problem_severity).slice(0, 8);
  return (
    <div className="page-grid">
      <section className="panel wide">
        <div className="section-heading">
          <h2>Note analytics</h2>
          <div className="filter-row">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} compact />
            <DateRangeFilter />
          </div>
        </div>
        <HeatMapGrid rows={heatmap} />
      </section>
      <section className="panel wide">
        <h2>Problem severity</h2>
        <div className="chart-frame">
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={worst}>
              <CartesianGrid stroke="#27313c" vertical={false} />
              <XAxis dataKey="note_label" stroke="#8795a5" />
              <YAxis stroke="#8795a5" />
              <Tooltip contentStyle={{ background: '#111820', border: '1px solid #2d3946', borderRadius: 8 }} />
              <Bar dataKey="avg_signed_cents" fill="#d9a441" name="Avg signed cents" radius={[4, 4, 0, 0]} />
              <Bar dataKey="stddev_cents" fill="#5ec6a8" name="Std dev" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </section>
      <section className="panel wide">
        <h2>Full note table</h2>
        <NoteStatsTable rows={stats} />
      </section>
    </div>
  );
}

