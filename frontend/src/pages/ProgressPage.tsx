import { AlertTriangle, ArrowRight, Clock, Flame, Gauge, LineChart, Target, TrendingUp, Waves } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { getHeatmap, getNoteStats, getPracticePlan, getProgress, getRecommendations } from '../api/client';
import { DateRangeFilter } from '../components/DateRangeFilter';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { PracticePlanCard } from '../components/PracticePlanCard';
import { AccuracyLineChart, PracticeBarChart } from '../components/ProgressChart';
import { RecommendationCard } from '../components/RecommendationCard';
import { EmptyActionState, InsightCard, LoadingSkeleton, MetricTile, PageHeader, ScreenContainer, SectionCard, SegmentedControl, StatusBadge } from '../components/ui/AppPrimitives';
import { WeeklyGoalCard } from '../components/practice/WeeklyGoalCard';
import {
  buildGuestHeatmap,
  buildGuestNoteStats,
  buildGuestPracticePlan,
  buildGuestProgress,
  buildGuestRecommendations,
} from '../domain/guestInsights';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { describeCents, describeInTunePercent } from '../domain/tuningLanguage';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { measuredRows, selectDefaultNoteLabel } from './analyticsSelection';
import './ProgressPage.css';

type Period = '7d' | '30d' | 'all' | 'custom';
type Tab = 'overview' | 'notes' | 'plan';
type ProgressRange = { date_from: string; date_to: string };
type ProgressLoadState = 'loading' | 'ready' | 'error';

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

export function validateProgressRange(range: ProgressRange) {
  if (range.date_from && range.date_to && range.date_from > range.date_to) {
    return 'The start date must be on or before the end date.';
  }
  return null;
}

export function progressDataOwnerKey(isSignedIn: boolean, profileId: number | null | undefined, identityPending = false) {
  if (identityPending) return null;
  if (isSignedIn) return profileId == null ? null : `account:${profileId}`;
  return 'guest';
}

export function progressDataBelongsToOwner(dataOwnerKey: string | null, currentOwnerKey: string | null) {
  return currentOwnerKey !== null && dataOwnerKey === currentOwnerKey;
}

export function invalidRangeOwnerTransition(dataOwnerKey: string | null, currentOwnerKey: string | null, hasRangeError: boolean) {
  if (!hasRangeError || currentOwnerKey === null) return { dataOwnerKey, clearData: false };
  return { dataOwnerKey: currentOwnerKey, clearData: true };
}

export function ProgressRangeControls({
  period,
  range,
  rangeError,
  showHeading = true,
  onPeriodChange,
  onRangeChange,
}: {
  period: Period;
  range: ProgressRange;
  rangeError: string | null;
  showHeading?: boolean;
  onPeriodChange: (period: Period) => void;
  onRangeChange: (range: ProgressRange) => void;
}) {
  return (
    <div className="pg-advanced-block">
      {showHeading && <h3>Time period</h3>}
      <SegmentedControl
        ariaLabel="Time period"
        value={period}
        options={[
          { value: '7d', label: '7 days' },
          { value: '30d', label: '30 days' },
          { value: 'all', label: 'All' },
          { value: 'custom', label: 'Custom' },
        ]}
        onChange={onPeriodChange}
      />
      {period === 'custom' && (
        <div>
          <DateRangeFilter value={range} onChange={onRangeChange} />
          {rangeError && <p className="pg-range-error" role="alert">{rangeError}</p>}
        </div>
      )}
    </div>
  );
}

export function ProgressPage() {
  const { instrumentId } = useAppSettings();
  const auth = useAuth();
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [progress, setProgress] = useState<ProgressMetrics | null>(null);
  const [plan, setPlan] = useState<PracticePlan | null>(null);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [period, setPeriod] = useState<Period>('30d');
  const [range, setRange] = useState(rangeForPeriod('30d'));
  const [selectedNote, setSelectedNote] = useState<string | undefined>();
  const [tab, setTab] = useState<Tab>('overview');
  const [loadState, setLoadState] = useState<ProgressLoadState>('loading');
  const [dataOwnerKey, setDataOwnerKey] = useState<string | null>(null);
  const [retryKey, setRetryKey] = useState(0);
  const rangeError = validateProgressRange(range);
  const identityPending = auth.loading || (auth.hasAuthSession && !auth.isSignedIn);
  const currentOwnerKey = progressDataOwnerKey(auth.isSignedIn, auth.profile?.id, identityPending);

  useEffect(() => {
    let active = true;
    if (currentOwnerKey === null) {
      setLoadState('loading');
      return () => {
        active = false;
      };
    }
    if (rangeError) {
      setStats([]);
      setHeatmap([]);
      setProgress(null);
      setPlan(null);
      setRecommendations([]);
      setDataOwnerKey((previous) => invalidRangeOwnerTransition(previous, currentOwnerKey, true).dataOwnerKey);
      setLoadState('ready');
      return () => {
        active = false;
      };
    }
    setLoadState('loading');
    if (!auth.isSignedIn) {
      try {
        const guestStats = buildGuestNoteStats(instrumentId, range);
        setStats(guestStats);
        setHeatmap(buildGuestHeatmap(instrumentId, guestStats));
        setProgress(buildGuestProgress(instrumentId, guestStats, range));
        setPlan(buildGuestPracticePlan(guestStats, instrumentId));
        setRecommendations(buildGuestRecommendations(guestStats));
        setDataOwnerKey(currentOwnerKey);
        setLoadState('ready');
      } catch {
        setLoadState('error');
      }
      return () => {
        active = false;
      };
    }
    Promise.all([
      getNoteStats(instrumentId, range),
      getHeatmap(instrumentId, range),
      getProgress(instrumentId, range),
      getPracticePlan(instrumentId),
      getRecommendations(instrumentId),
    ])
      .then(([noteData, heatmapData, progressData, planData, recommendationData]) => {
        if (!active) return;
        setStats(noteData);
        setHeatmap(heatmapData);
        setProgress(progressData);
        setPlan(planData);
        setRecommendations(recommendationData);
        setDataOwnerKey(currentOwnerKey);
        setLoadState('ready');
      })
      .catch(() => {
        if (!active) return;
        setLoadState('error');
      });
    return () => {
      active = false;
    };
  }, [auth.isSignedIn, currentOwnerKey, instrumentId, range, rangeError, retryKey]);

  useEffect(() => {
    const nextSelection = selectDefaultNoteLabel(heatmap, selectedNote);
    if (nextSelection !== selectedNote) {
      setSelectedNote(nextSelection);
    }
  }, [heatmap, selectedNote]);

  const measuredStats = useMemo(() => measuredRows(stats), [stats]);
  const measuredHeatmap = useMemo(() => measuredRows(heatmap), [heatmap]);
  const worst = useMemo(
    () => [...measuredStats].sort((a, b) => b.problem_severity - a.problem_severity).slice(0, 8),
    [measuredStats],
  );
  const summary = useMemo(() => {
    if (!measuredStats.length) {
      return { averageAbs: 0, averageSigned: 0, averageInTune: 0, centered: undefined as NoteStats | undefined, unstable: undefined as NoteStats | undefined };
    }
    const averageAbs = measuredStats.reduce((sum, row) => sum + row.avg_abs_cents, 0) / measuredStats.length;
    const averageSigned = measuredStats.reduce((sum, row) => sum + row.avg_signed_cents, 0) / measuredStats.length;
    const averageInTune = measuredStats.reduce((sum, row) => sum + row.in_tune_percentage, 0) / measuredStats.length;
    const centered = [...measuredStats].sort((a, b) => a.avg_abs_cents - b.avg_abs_cents)[0];
    const unstable = [...measuredStats].sort((a, b) => b.stddev_cents - a.stddev_cents)[0];
    return { averageAbs, averageSigned, averageInTune, centered, unstable };
  }, [measuredStats]);

  const selected = heatmap.find((row) => row.note_label === selectedNote) ?? measuredHeatmap[0] ?? heatmap[0];
  const timeseries = progress?.timeseries ?? [];
  const latestPoint = timeseries[timeseries.length - 1];
  const sessionCount = progress?.session_count ?? 0;
  const improved = progress?.most_improved_notes?.[0];
  const issue = progress?.worst_notes?.[0] ?? worst[0];

  const inTunePct = measuredStats.length ? summary.averageInTune : latestPoint?.in_tune_percentage ?? 0;
  const inTuneTone = describeInTunePercent(inTunePct).tone;
  const offBy = describeCents(summary.averageSigned);
  const practiceMinutes = Math.round((progress?.total_practice_time_seconds ?? 0) / 60);
  const streakDays = progress?.consistency?.practice_streak_days ?? 0;

  const dataBelongsToCurrentOwner = progressDataBelongsToOwner(dataOwnerKey, currentOwnerKey);
  const hasData = dataBelongsToCurrentOwner && (measuredStats.length > 0 || sessionCount > 0);
  const visibleLoadState = currentOwnerKey === null || (!dataBelongsToCurrentOwner && loadState === 'ready') ? 'loading' : loadState;

  const instrumentBadge = <StatusBadge tone="muted">{instrumentDisplayName(instrumentId)}</StatusBadge>;
  const rangeControls = (
    <ProgressRangeControls
      period={period}
      range={range}
      rangeError={rangeError}
      showHeading={false}
      onPeriodChange={(next) => {
        setPeriod(next);
        if (next !== 'custom') setRange(rangeForPeriod(next));
      }}
      onRangeChange={(next) => {
        setRange(next);
        setPeriod('custom');
      }}
    />
  );

  if (visibleLoadState === 'loading' && !hasData) {
    return (
      <ScreenContainer>
        <PageHeader title="Your progress" description="See how your tuning is getting better over time." meta={instrumentBadge} />
        <SectionCard title="Time period" eyebrow="Filter results">
          {rangeControls}
        </SectionCard>
        <SectionCard title="Loading your progress">
          <LoadingSkeleton rows={5} />
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (visibleLoadState === 'error' && !hasData) {
    return (
      <ScreenContainer>
        <PageHeader title="Your progress" description="See how your tuning is getting better over time." meta={instrumentBadge} />
        <SectionCard title="Time period" eyebrow="Filter results">
          {rangeControls}
        </SectionCard>
        <SectionCard title="Couldn’t load your progress" eyebrow="Connection problem">
          <p className="pg-load-copy">Check your connection, then try again. Your practice history has not been removed.</p>
          <button className="primary-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>Try again</button>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (!hasData) {
    return (
      <ScreenContainer>
        <PageHeader title="Your progress" description="See how your tuning is getting better over time." meta={instrumentBadge} />
        {rangeError ? (
          <>
            <SectionCard title="Time period" eyebrow="Filter results">
              {rangeControls}
            </SectionCard>
            <p className="pg-note" role="status">Choose a valid time period to load progress for this account.</p>
          </>
        ) : (
          <>
            <EmptyActionState
              icon={LineChart}
              title="No practice yet"
              body="Play a few notes on the Tuner and your results show up here — how in-tune you are, and which notes to work on."
              action={
                <Link to="/practice" className="primary-button">
                  Record your first note
                  <ArrowRight size={18} />
                </Link>
              }
            />
            <SectionCard title="Time period" eyebrow="Filter results">
              {rangeControls}
            </SectionCard>
          </>
        )}
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader
        title="Your progress"
        description="See how your tuning is getting better over time."
        meta={instrumentBadge}
        action={
          <Link to="/practice" className="primary-button">
            Keep practicing
            <ArrowRight size={18} />
          </Link>
        }
      />

      {visibleLoadState === 'loading' && (
        <p className="pg-load-status" role="status" aria-live="polite">Updating your progress…</p>
      )}
      {visibleLoadState === 'error' && (
        <div className="pg-load-warning" role="status" aria-live="polite">
          <p>We couldn’t refresh your progress. The most recent results already loaded are still shown.</p>
          <button className="ghost-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>Try again</button>
        </div>
      )}

      <div className="stats-grid">
        <MetricTile label="In tune" value={`${Math.round(inTunePct)}%`} detail="across notes you played" icon={Target} tone={inTuneTone} />
        <MetricTile label="Average off by" value={offBy.label} detail={offBy.detail || 'right on'} icon={Gauge} tone={offBy.tone} />
        <MetricTile label="Practice time" value={`${practiceMinutes} min`} detail={`${sessionCount} session${sessionCount === 1 ? '' : 's'}`} icon={Clock} />
        <MetricTile
          label="Streak"
          value={`${streakDays} day${streakDays === 1 ? '' : 's'}`}
          detail={`${progress?.consistency?.practice_days_label ?? '0 of 7'} this week`}
          icon={Flame}
        />
      </div>

      <p className="pg-cents-hint">
        “Cents” measure how sharp or flat a note is — about 100 cents is one key on a piano. Under about 5 cents counts as in tune.
      </p>

      <WeeklyGoalCard />

      <SegmentedControl
        ariaLabel="Progress sections"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'overview', label: 'Over time' },
          { value: 'notes', label: 'Note by note' },
          { value: 'plan', label: 'Plan' },
        ]}
      />

      {tab === 'overview' && (
        <div className="pg-tabpanel">
          {timeseries.length > 0 ? (
            <div className="two-column-grid">
              <SectionCard title="How in-tune, over time">
                <AccuracyLineChart data={timeseries} />
                <p className="pg-chart-caption">
                  <span className="pg-swatch" style={{ background: '#5ec6a8' }} /> Green line: how in tune (higher is better).
                  <span className="pg-swatch" style={{ background: 'var(--gold)' }} /> Gold line: how far off (lower is better).
                </p>
              </SectionCard>
              <SectionCard title="Practice minutes">
                <PracticeBarChart data={timeseries} />
              </SectionCard>
            </div>
          ) : (
            <p className="pg-empty-line">Record a couple more sessions and your trend will appear here.</p>
          )}
          <div className="insight-grid">
            <InsightCard
              title={improved ? `${improved.note_label} improved most` : 'Keep going'}
              detail={improved ? `${Math.round(improved.improvement)}¢ closer to in tune` : undefined}
              body={
                improved
                  ? `It used to be about ${Math.round(improved.previous_avg_abs_cents)}¢ off — now it's steadier.`
                  : "Keep practicing and we'll show which notes improved most."
              }
              icon={TrendingUp}
              tone="green"
            />
            <InsightCard
              title={issue ? `${issue.note_label} needs the most work` : 'Nothing off yet'}
              detail={issue ? describeCents(issue.avg_signed_cents).label : undefined}
              body={
                issue
                  ? `You're playing it ${describeCents(issue.avg_signed_cents).detail || 'about right'} — ${describeCents(issue.avg_signed_cents).cue || 'keep it steady'}.`
                  : 'Play some notes to see which one needs the most work.'
              }
              icon={AlertTriangle}
              tone={issue ? (describeCents(issue.avg_signed_cents).tone === 'green' ? 'green' : describeCents(issue.avg_signed_cents).tone) : 'muted'}
            />
          </div>
        </div>
      )}

      {tab === 'notes' && (
        <div className="pg-tabpanel">
          <SectionCard title="Your notes" eyebrow="Tap a note">
            <HeatMapGrid rows={heatmap} selectedNote={selected?.note_label} onSelect={(row) => setSelectedNote(row.note_label)} />
            <div className="pg-legend" aria-hidden="true">
              <span className="pg-legend-item"><span className="pg-dot tone-green" /> In tune</span>
              <span className="pg-legend-item"><span className="pg-dot tone-amber" /> A little off</span>
              <span className="pg-legend-item"><span className="pg-dot tone-red" /> Needs work</span>
            </div>
            {selected && (
              <div className={`pg-selected tone-${selected.has_data === false ? 'muted' : describeCents(selected.avg_signed_cents).tone}`}>
                <div className="pg-selected-head">
                  <strong>{selected.note_label}</strong>
                  <StatusBadge tone={selected.has_data === false ? 'muted' : describeCents(selected.avg_signed_cents).tone}>
                    {selected.has_data === false ? 'Not tried yet' : describeCents(selected.avg_signed_cents).label}
                  </StatusBadge>
                </div>
                <p>
                  {selected.has_data === false
                    ? "You haven't played this note yet — give it a try on the Tuner."
                    : `${describeCents(selected.avg_signed_cents).detail || 'Right on the money'} · ${Math.round(selected.in_tune_percentage)}% in tune`}
                </p>
              </div>
            )}
          </SectionCard>

          {measuredStats.length > 0 && (
            <SectionCard title="All notes" eyebrow="Worst first">
              <ul className="pg-notes-list">
                {measuredStats.map((row) => {
                  const verdict = describeCents(row.avg_signed_cents);
                  return (
                    <li className="pg-note-row" key={row.note_label}>
                      <span className={`pg-dot tone-${verdict.tone}`} aria-hidden="true" />
                      <span className="pg-note-name">{row.note_label}</span>
                      <span className="pg-note-verdict">{verdict.detail || verdict.label}</span>
                      <span className="pg-note-pct">{Math.round(row.in_tune_percentage)}% in tune</span>
                    </li>
                  );
                })}
              </ul>
            </SectionCard>
          )}

          <div className="insight-grid">
            {summary.centered && (
              <InsightCard
                title={`${summary.centered.note_label} is your steadiest`}
                detail={describeInTunePercent(summary.centered.in_tune_percentage).label}
                body="This is your most in-tune note — a great one to warm up on."
                icon={Target}
                tone="green"
              />
            )}
            {summary.unstable && summary.unstable.note_label !== summary.centered?.note_label && (
              <InsightCard
                title={`${summary.unstable.note_label} is the shakiest`}
                detail="Wobbly pitch"
                body="A shaky note usually means your air or attack isn't steady yet — hold it long and even."
                icon={Waves}
                tone="amber"
              />
            )}
          </div>
        </div>
      )}

      {tab === 'plan' && (
        <div className="pg-tabpanel">
          {plan ? (
            <PracticePlanCard plan={plan} />
          ) : (
            <p className="pg-empty-line">Play a few notes and we'll build a short practice plan for you.</p>
          )}
          <div className="insight-grid">
            <InsightCard
              title="Aim for green"
              detail="Within about 5¢"
              body="Focus on steady starts and even holds first — the small numbers come once the note stops wobbling."
              icon={Gauge}
              tone="green"
            />
          </div>
          {recommendations.length > 0 && (
            <SectionCard title="Recommended drills">
              <div className="recommendation-grid">
                {recommendations.map((recommendation) => (
                  <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
                ))}
              </div>
            </SectionCard>
          )}
        </div>
      )}

      <details className="pg-advanced">
        <summary>Advanced (for teachers)</summary>
        <div className="pg-advanced-body">
          <ProgressRangeControls
            period={period}
            range={range}
            rangeError={rangeError}
            onPeriodChange={(next) => {
              setPeriod(next);
              if (next !== 'custom') setRange(rangeForPeriod(next));
            }}
            onRangeChange={(next) => {
              setRange(next);
              setPeriod('custom');
            }}
          />

          {worst.length > 0 && (
            <div className="pg-advanced-block">
              <h3>Sharp or flat, note by note</h3>
              <div className="chart-frame">
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={worst}>
                    <CartesianGrid stroke="rgba(164, 183, 202, 0.16)" vertical={false} />
                    <XAxis dataKey="note_label" stroke="#9dabbb" />
                    <YAxis stroke="#9dabbb" />
                    <Tooltip contentStyle={{ background: '#111923', border: '1px solid rgba(214, 190, 133, 0.28)', borderRadius: 14 }} />
                    <Bar dataKey="avg_signed_cents" fill="#d8a53f" name="How sharp/flat" radius={[7, 7, 0, 0]} />
                    <Bar dataKey="stddev_cents" fill="#59c9b2" name="How steady" radius={[7, 7, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {stats.length > 0 && (
            <div className="pg-advanced-block">
              <h3>All notes</h3>
              <NoteStatsTable rows={stats} />
            </div>
          )}
        </div>
      </details>
    </ScreenContainer>
  );
}
