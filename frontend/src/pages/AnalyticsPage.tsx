import { AlertTriangle, ArrowRight, Gauge, SlidersHorizontal, Target, Waves } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { getHeatmap, getNoteStats } from '../api/client';
import { DateRangeFilter } from '../components/DateRangeFilter';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { InsightCard, MetricTile, PageHeader, ScreenContainer, SectionCard, SegmentedControl, StatusBadge } from '../components/ui/AppPrimitives';
import type { NoteStats } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';
import { measuredRows, selectDefaultNoteLabel } from './analyticsSelection';

type Period = '7d' | '30d' | 'all' | 'custom';

function dateOffset(days: number) {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return date.toISOString().slice(0, 10);
}

function rangeForPeriod(period: Period) {
  if (period === '7d') return { date_from: dateOffset(7), date_to: '' };
  if (period === '30d') return { date_from: dateOffset(30), date_to: '' };
  return { date_from: '', date_to: '' };
}

export function AnalyticsPage() {
  const { instrumentId, setInstrumentId } = useAppSettings();
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [period, setPeriod] = useState<Period>('30d');
  const [range, setRange] = useState(rangeForPeriod('30d'));
  const [selectedNote, setSelectedNote] = useState<string | undefined>();

  useEffect(() => {
    Promise.all([getNoteStats(instrumentId, range), getHeatmap(instrumentId, range)]).then(([noteData, heatmapData]) => {
      setStats(noteData);
      setHeatmap(heatmapData);
    });
  }, [instrumentId, range]);

  useEffect(() => {
    const nextSelection = selectDefaultNoteLabel(heatmap, selectedNote);
    if (nextSelection !== selectedNote) {
      setSelectedNote(nextSelection);
    }
  }, [heatmap, selectedNote]);

  const measuredStats = useMemo(() => measuredRows(stats), [stats]);
  const measuredHeatmap = useMemo(() => measuredRows(heatmap), [heatmap]);
  const worst = useMemo(() => [...measuredStats].sort((a, b) => b.problem_severity - a.problem_severity).slice(0, 8), [measuredStats]);
  const selected = heatmap.find((row) => row.note_label === selectedNote) ?? measuredHeatmap[0] ?? heatmap[0];
  const diagnosis = useMemo(() => {
    const sharp = [...measuredStats].sort((a, b) => b.avg_signed_cents - a.avg_signed_cents)[0];
    const flat = [...measuredStats].sort((a, b) => a.avg_signed_cents - b.avg_signed_cents)[0];
    const unstable = [...measuredStats].sort((a, b) => b.stddev_cents - a.stddev_cents)[0];
    const centered = [...measuredStats].sort((a, b) => a.avg_abs_cents - b.avg_abs_cents)[0];
    const averageAbs = measuredStats.length ? measuredStats.reduce((sum, row) => sum + row.avg_abs_cents, 0) / measuredStats.length : 0;
    const averageInTune = measuredStats.length ? measuredStats.reduce((sum, row) => sum + row.in_tune_percentage, 0) / measuredStats.length : 0;
    return { sharp, flat, unstable, centered, averageAbs, averageInTune };
  }, [measuredStats]);
  const unmeasuredCount = useMemo(() => heatmap.filter((row) => row.has_data === false).length, [heatmap]);

  const setPeriodAndRange = (next: Period) => {
    setPeriod(next);
    if (next !== 'custom') {
      setRange(rangeForPeriod(next));
    }
  };

  return (
    <ScreenContainer className="analytics-dashboard">
      <PageHeader
        eyebrow="Analytics"
        title="Diagnosis before drill"
        description="Start with the pattern: which notes are sharp, flat, unstable, unmeasured, or improving enough to move on."
        action={
          <div className="filter-row">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} compact />
            <StatusBadge tone="gold">{measuredStats.length} measured notes</StatusBadge>
          </div>
        }
      />
      <SectionCard
        className="analytics-controls"
        title="Period and instrument"
        eyebrow="Filters"
        action={<DateRangeFilter value={range} onChange={(next) => { setRange(next); setPeriod('custom'); }} />}
      >
        <div className="analytics-control-row">
          <SegmentedControl
            ariaLabel="Analytics period"
            value={period}
            options={[
              { value: '7d', label: '7D' },
              { value: '30d', label: '30D' },
              { value: 'all', label: 'All' },
              { value: 'custom', label: 'Custom' },
            ]}
            onChange={setPeriodAndRange}
          />
          <div className="analytics-summary-strip">
            <MetricTile label="Measured" value={`${measuredStats.length}`} detail={`${unmeasuredCount} unmeasured`} tone="gold" />
            <MetricTile label="Avg abs" value={`${diagnosis.averageAbs.toFixed(1)}c`} detail="measured notes" />
            <MetricTile label="In tune" value={`${Math.round(diagnosis.averageInTune)}%`} detail="weighted by note rows" tone="green" />
          </div>
        </div>
      </SectionCard>
      <div className="analytics-main-grid">
        <SectionCard className="analytics-heatmap-card" title="Written-range heat map" eyebrow="Tap a note">
          <HeatMapGrid rows={heatmap} selectedNote={selected?.note_label} onSelect={(row) => setSelectedNote(row.note_label)} />
        </SectionCard>
        <SectionCard className="analytics-inspector-card" title="Selected note" eyebrow="Persistent inspector">
          {selected && (
            <article className="note-detail-card">
              <StatusBadge tone={selected.has_data === false ? 'muted' : selected.severity_color === 'green' ? 'green' : selected.severity_color === 'red' ? 'red' : 'amber'}>
                {selected.has_data === false ? 'Insufficient' : selected.severity}
              </StatusBadge>
              <strong>{selected.note_label}</strong>
              <p>{selected.recommendation_summary ?? 'No recommendation summary yet.'}</p>
              <div className="note-detail-metrics">
                <div>
                  <span>Signed</span>
                  <b>{selected.has_data === false ? '--' : `${selected.avg_signed_cents.toFixed(1)}c`}</b>
                </div>
                <div>
                  <span>Avg abs</span>
                  <b>{selected.has_data === false ? '--' : `${selected.avg_abs_cents.toFixed(1)}c`}</b>
                </div>
                <div>
                  <span>In tune</span>
                  <b>{selected.has_data === false ? '--' : `${Math.round(selected.in_tune_percentage)}%`}</b>
                </div>
                <div>
                  <span>Duration</span>
                  <b>{selected.has_data === false ? '--' : `${Math.round(selected.duration_seconds)}s`}</b>
                </div>
              </div>
              <Link to="/practice" className="primary-button inspector-action">
                Practice this note
                <ArrowRight size={18} />
              </Link>
            </article>
          )}
        </SectionCard>
      </div>
      <div className="insight-grid analytics-diagnosis-grid">
        <InsightCard
          title={diagnosis.sharp ? `${diagnosis.sharp.note_label} trends sharp` : 'Sharp trend'}
          detail={diagnosis.sharp ? `+${diagnosis.sharp.avg_signed_cents.toFixed(1)} cents signed` : 'More data needed'}
          body={diagnosis.sharp?.recommendation_summary ?? 'Record a few centered long tones to reveal sharp tendencies.'}
          icon={Gauge}
          tone="orange"
        />
        <InsightCard
          title={diagnosis.flat ? `${diagnosis.flat.note_label} trends flat` : 'Flat trend'}
          detail={diagnosis.flat ? `${diagnosis.flat.avg_signed_cents.toFixed(1)} cents signed` : 'More data needed'}
          body={diagnosis.flat?.recommendation_summary ?? 'Record a few centered long tones to reveal flat tendencies.'}
          icon={SlidersHorizontal}
          tone="amber"
        />
        <InsightCard
          title={diagnosis.unstable ? `${diagnosis.unstable.note_label} is unstable` : 'Stability'}
          detail={diagnosis.unstable ? `${diagnosis.unstable.stddev_cents.toFixed(1)} cents std dev` : 'More data needed'}
          body="Use this to separate pitch center problems from tone-start or air-support problems."
          icon={Waves}
          tone="red"
        />
        <InsightCard
          title={diagnosis.centered ? `${diagnosis.centered.note_label} is centered` : 'Best centered'}
          detail={diagnosis.centered ? `${diagnosis.centered.avg_abs_cents.toFixed(1)} cents avg abs` : 'More data needed'}
          body="Keep this note in the warmup as a calibration anchor."
          icon={Target}
          tone="green"
        />
      </div>
      <SectionCard title="Worst current problems" eyebrow="Prioritized">
        <div className="insight-grid">
          {worst.slice(0, 4).map((row) => (
            <InsightCard
              key={row.note_label}
              title={row.note_label}
              detail={`${row.avg_abs_cents.toFixed(1)} cents avg abs`}
              body={row.recommendation_summary ?? `${row.in_tune_percentage.toFixed(0)}% in tune across ${row.event_count} events.`}
              icon={AlertTriangle}
              tone={row.severity_color === 'red' ? 'red' : row.severity_color === 'orange' ? 'orange' : 'amber'}
            />
          ))}
        </div>
      </SectionCard>
      <div className="analytics-chart-grid">
        <SectionCard title="Signed error and spread" eyebrow="Pitch center">
          <div className="chart-frame">
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={worst}>
                <CartesianGrid stroke="rgba(164, 183, 202, 0.16)" vertical={false} />
                <XAxis dataKey="note_label" stroke="#9dabbb" />
                <YAxis stroke="#9dabbb" />
                <Tooltip contentStyle={{ background: '#111923', border: '1px solid rgba(214, 190, 133, 0.28)', borderRadius: 14 }} />
                <Bar dataKey="avg_signed_cents" fill="#d8a53f" name="Avg signed cents" radius={[7, 7, 0, 0]} />
                <Bar dataKey="stddev_cents" fill="#59c9b2" name="Std dev" radius={[7, 7, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </SectionCard>
        <SectionCard title="Severity ranking" eyebrow="Priority">
          <div className="chart-frame">
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={worst}>
                <CartesianGrid stroke="rgba(164, 183, 202, 0.16)" vertical={false} />
                <XAxis dataKey="note_label" stroke="#9dabbb" />
                <YAxis stroke="#9dabbb" />
                <Tooltip contentStyle={{ background: '#111923', border: '1px solid rgba(214, 190, 133, 0.28)', borderRadius: 14 }} />
                <Bar dataKey="problem_severity" fill="#e58b43" name="Problem severity" radius={[7, 7, 0, 0]} />
                <Bar dataKey="in_tune_percentage" fill="#6bd287" name="In-tune %" radius={[7, 7, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </SectionCard>
      </div>
      <SectionCard title="Full note table" eyebrow="Audit trail">
        <NoteStatsTable rows={stats} />
      </SectionCard>
    </ScreenContainer>
  );
}
