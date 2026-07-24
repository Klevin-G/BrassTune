import { AlertTriangle, ArrowRight, ChevronLeft, ChevronRight, Clock, Flame, Gauge, LineChart, Target, TrendingUp, Waves } from 'lucide-react';
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
import {
  localizeProgressMetrics,
  localizeProgressNoteStats,
  localizeProgressPlan,
  localizeProgressRecommendations,
} from '../domain/progressLocalization';
import { describeCents, describeInTunePercent } from '../domain/tuningLanguage';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { measuredRows, selectDefaultNoteLabel } from './analyticsSelection';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import './ProgressPage.css';

function bidiIsolate(value: string | number) {
  return `\u2068${value}\u2069`;
}

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

export function validateProgressRange(range: ProgressRange, message = 'The start date must be on or before the end date.') {
  if (range.date_from && range.date_to && range.date_from > range.date_to) {
    return message;
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
  const { t } = useI18n();
  return (
    <div className="pg-advanced-block">
      {showHeading && <h3>{t('progress.period')}</h3>}
      <SegmentedControl
        ariaLabel={t('progress.period')}
        value={period}
        options={[
          { value: '7d', label: t('progress.sevenDays') },
          { value: '30d', label: t('progress.thirtyDays') },
          { value: 'all', label: t('progress.allTime') },
          { value: 'custom', label: t('progress.custom') },
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
  const { dir, locale, t, formatNumber } = useI18n();
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
  const rangeError = validateProgressRange(range, t('progress.rangeError'));
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
        const localizer = {
          t,
          formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => (
            new Intl.DateTimeFormat(locale, options).format(new Date(value))
          ),
        };
        const guestStats = buildGuestNoteStats(instrumentId, range, localizer);
        setStats(guestStats);
        setHeatmap(buildGuestHeatmap(instrumentId, guestStats, localizer));
        setProgress(buildGuestProgress(instrumentId, guestStats, range, localizer));
        setPlan(buildGuestPracticePlan(guestStats, instrumentId, localizer));
        setRecommendations(buildGuestRecommendations(guestStats, localizer));
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
        const localizer = {
          t,
          formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => (
            new Intl.DateTimeFormat(locale, options).format(new Date(value))
          ),
        };
        setStats(localizeProgressNoteStats(noteData, localizer));
        setHeatmap(localizeProgressNoteStats(heatmapData, localizer));
        setProgress(localizeProgressMetrics(progressData, localizer));
        setPlan(localizeProgressPlan(planData, localizer));
        setRecommendations(localizeProgressRecommendations(recommendationData, localizer));
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
  }, [auth.isSignedIn, currentOwnerKey, instrumentId, locale, range, rangeError, retryKey, t]);

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

  const instrumentBadge = <StatusBadge tone="muted">{t(`instrument.${instrumentId}` as MessageId)}</StatusBadge>;
  const localizeCents = (value: number) => {
    const verdict = describeCents(value);
    const label = verdict.tone === 'green' ? t('tuning.inTune') : verdict.direction === 'sharp' ? t(verdict.tone === 'amber' ? 'tuning.littleSharp' : 'tuning.sharp') : t(verdict.tone === 'amber' ? 'tuning.littleFlat' : 'tuning.flat');
    const detail = verdict.direction === 'center' ? t('tuning.rightOn') : t(verdict.direction === 'sharp' ? 'tuning.centsSharp' : 'tuning.centsFlat', { cents: formatNumber(Math.abs(Math.round(value))) });
    const cue = t(verdict.direction === 'sharp' ? 'tuning.easeDown' : verdict.direction === 'flat' ? 'tuning.liftUp' : 'tuning.holdIt');
    return { ...verdict, label, detail, cue };
  };
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
        <PageHeader title={t('progress.title')} description={t('progress.description')} meta={instrumentBadge} />
        <SectionCard title={t('progress.period')} eyebrow={t('progress.filter')}>
          {rangeControls}
        </SectionCard>
        <SectionCard title={t('progress.loading')}>
          <LoadingSkeleton rows={5} label={t('progress.loading')} />
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (visibleLoadState === 'error' && !hasData) {
    return (
      <ScreenContainer>
        <PageHeader title={t('progress.title')} description={t('progress.description')} meta={instrumentBadge} />
        <SectionCard title={t('progress.period')} eyebrow={t('progress.filter')}>
          {rangeControls}
        </SectionCard>
        <SectionCard title={t('progress.loadFailed')} eyebrow={t('sessionReview.connection')}>
          <p className="pg-load-copy">{t('progress.loadFailedBody')}</p>
          <button className="primary-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>{t('auth.tryAgain')}</button>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (!hasData) {
    return (
      <ScreenContainer>
        <PageHeader title={t('progress.title')} description={t('progress.description')} meta={instrumentBadge} />
        {rangeError ? (
          <>
            <SectionCard title={t('progress.period')} eyebrow={t('progress.filter')}>
              {rangeControls}
            </SectionCard>
            <p className="pg-note" role="status">{t('progress.chooseValidPeriod')}</p>
          </>
        ) : (
          <>
            <EmptyActionState
              icon={LineChart}
              title={t('progress.empty')}
              body={t('progress.emptyBody')}
              action={
                <Link to="/practice" className="primary-button">
                  {t('progress.recordFirst')}
                  <ArrowRight size={18} style={{ transform: dir === 'rtl' ? 'scaleX(-1)' : undefined }} />
                </Link>
              }
            />
            <SectionCard title={t('progress.period')} eyebrow={t('progress.filter')}>
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
        title={t('progress.title')}
        description={t('progress.description')}
        meta={instrumentBadge}
        action={
          <Link to="/practice" className="primary-button">
            {t('progress.keepPracticing')}
            <ArrowRight size={18} style={{ transform: dir === 'rtl' ? 'scaleX(-1)' : undefined }} />
          </Link>
        }
      />

      {visibleLoadState === 'loading' && (
        <p className="pg-load-status" role="status" aria-live="polite">{t('progress.updating')}</p>
      )}
      {visibleLoadState === 'error' && (
        <div className="pg-load-warning" role="status" aria-live="polite">
          <p>{t('progress.refreshFailed')}</p>
          <button className="ghost-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>{t('auth.tryAgain')}</button>
        </div>
      )}

      <div className="stats-grid">
        <MetricTile label={t('tuning.inTune')} value={<bdi dir="ltr">{formatNumber(Math.round(inTunePct))}%</bdi>} detail={t('progress.acrossNotes')} icon={Target} tone={inTuneTone} />
        <MetricTile label={t('progress.averageOff')} value={localizeCents(summary.averageSigned).label} detail={localizeCents(summary.averageSigned).detail} icon={Gauge} tone={offBy.tone} />
        <MetricTile label={t('progress.practiceTime')} value={t('progress.minutesShort', { count: formatNumber(practiceMinutes) })} detail={t('progress.sessionCount', { count: sessionCount })} icon={Clock} />
        <MetricTile
          label={t('progress.streak')}
          value={t('progress.dayCount', { count: streakDays })}
          detail={t('progress.thisWeek', { value: progress?.consistency?.practice_days_label ?? formatNumber(0) })}
          icon={Flame}
        />
      </div>

      <p className="pg-cents-hint">
        {t('progress.centsHelp')}
      </p>

      <WeeklyGoalCard />

      <SegmentedControl
        ariaLabel={t('progress.sections')}
        value={tab}
        onChange={setTab}
        options={[
          { value: 'overview', label: t('progress.overTime') },
          { value: 'notes', label: t('playAlong.noteByNote') },
          { value: 'plan', label: t('progress.plan') },
        ]}
      />

      {tab === 'overview' && (
        <div className="pg-tabpanel">
          {timeseries.length > 0 ? (
            <div className="two-column-grid">
              <SectionCard title={t('progress.tuningOverTime')}>
                <AccuracyLineChart data={timeseries} />
                <p className="pg-chart-caption">
                  <span className="pg-swatch" style={{ background: '#5ec6a8' }} /> {t('progress.greenLine')}
                  <span className="pg-swatch" style={{ background: 'var(--gold)' }} /> {t('progress.goldLine')}
                </p>
              </SectionCard>
              <SectionCard title={t('progress.practiceMinutes')}>
                <PracticeBarChart data={timeseries} />
              </SectionCard>
            </div>
          ) : (
            <p className="pg-empty-line">{t('progress.moreForTrend')}</p>
          )}
          <div className="insight-grid">
            <InsightCard
              title={improved ? t('progress.improvedMost', { note: bidiIsolate(improved.note_label) }) : t('progress.keepGoing')}
              detail={improved ? t('progress.centsCloser', { cents: formatNumber(Math.round(improved.improvement)) }) : undefined}
              body={
                improved
                  ? t('progress.improvedBody', { cents: formatNumber(Math.round(improved.previous_avg_abs_cents)) })
                  : t('progress.keepGoingBody')
              }
              icon={TrendingUp}
              tone="green"
            />
            <InsightCard
              title={issue ? t('progress.needsMostWork', { note: bidiIsolate(issue.note_label) }) : t('progress.nothingOff')}
              detail={issue ? localizeCents(issue.avg_signed_cents).label : undefined}
              body={
                issue
                  ? t('progress.issueBody', { detail: localizeCents(issue.avg_signed_cents).detail, cue: localizeCents(issue.avg_signed_cents).cue })
                  : t('progress.issueEmpty')
              }
              icon={AlertTriangle}
              tone={issue ? (describeCents(issue.avg_signed_cents).tone === 'green' ? 'green' : describeCents(issue.avg_signed_cents).tone) : 'muted'}
            />
          </div>
        </div>
      )}

      {tab === 'notes' && (
        <div className="pg-tabpanel">
          <SectionCard title={t('progress.yourNotes')} eyebrow={t('progress.tapNote')}>
            <HeatMapGrid rows={heatmap} selectedNote={selected?.note_label} onSelect={(row) => setSelectedNote(row.note_label)} />
            <div className="pg-legend" aria-hidden="true">
              <span className="pg-legend-item"><span className="pg-dot tone-green" /> {t('tuning.inTune')}</span>
              <span className="pg-legend-item"><span className="pg-dot tone-amber" /> {t('playAlong.grade.close')}</span>
              <span className="pg-legend-item"><span className="pg-dot tone-red" /> {t('sessionReview.needsWork')}</span>
            </div>
            {selected && (
              <div className={`pg-selected tone-${selected.has_data === false ? 'muted' : describeCents(selected.avg_signed_cents).tone}`}>
                <div className="pg-selected-head">
                  <strong><bdi dir="ltr">{selected.note_label}</bdi></strong>
                  <StatusBadge tone={selected.has_data === false ? 'muted' : describeCents(selected.avg_signed_cents).tone}>
                    {selected.has_data === false ? t('progress.notTried') : localizeCents(selected.avg_signed_cents).label}
                  </StatusBadge>
                </div>
                <p>
                  {selected.has_data === false
                    ? t('progress.notTriedBody')
                    : t('progress.noteResult', { detail: localizeCents(selected.avg_signed_cents).detail, percent: formatNumber(Math.round(selected.in_tune_percentage)) })}
                </p>
              </div>
            )}
          </SectionCard>

          {measuredStats.length > 0 && (
            <SectionCard title={t('progress.allNotes')} eyebrow={t('progress.worstFirst')}>
              <ul className="pg-notes-list">
                {measuredStats.map((row) => {
                  const verdict = describeCents(row.avg_signed_cents);
                  return (
                    <li className="pg-note-row" key={row.note_label}>
                      <span className={`pg-dot tone-${verdict.tone}`} aria-hidden="true" />
                      <span className="pg-note-name"><bdi dir="ltr">{row.note_label}</bdi></span>
                      <span className="pg-note-verdict">{localizeCents(row.avg_signed_cents).detail}</span>
                      <span className="pg-note-pct">{t('practice.percentInTune', { percent: formatNumber(Math.round(row.in_tune_percentage)) })}</span>
                    </li>
                  );
                })}
              </ul>
            </SectionCard>
          )}

          <div className="insight-grid">
            {summary.centered && (
              <InsightCard
                title={t('progress.steadiest', { note: bidiIsolate(summary.centered.note_label) })}
                detail={t('tuning.inTune')}
                body={t('progress.steadiestBody')}
                icon={Target}
                tone="green"
              />
            )}
            {summary.unstable && summary.unstable.note_label !== summary.centered?.note_label && (
              <InsightCard
                title={t('progress.shakiest', { note: bidiIsolate(summary.unstable.note_label) })}
                detail={t('progress.wobbly')}
                body={t('progress.shakiestBody')}
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
            <p className="pg-empty-line">{t('progress.planEmpty')}</p>
          )}
          <div className="insight-grid">
            <InsightCard
              title={t('progress.aimGreen')}
              detail={t('progress.withinFive')}
              body={t('progress.aimGreenBody')}
              icon={Gauge}
              tone="green"
            />
          </div>
          {recommendations.length > 0 && (
            <SectionCard title={t('progress.recommended')}>
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
        <summary>
          {dir === 'rtl' ? <ChevronLeft className="pg-advanced-caret rtl" size={18} /> : <ChevronRight className="pg-advanced-caret" size={18} />}
          <span>{t('progress.advanced')}</span>
        </summary>
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
              <h3>{t('progress.sharpFlatByNote')}</h3>
              <div className="chart-frame">
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={worst}>
                    <CartesianGrid stroke="rgba(164, 183, 202, 0.16)" vertical={false} />
                    <XAxis dataKey="note_label" stroke="#9dabbb" />
                    <YAxis stroke="#9dabbb" />
                    <Tooltip contentStyle={{ background: '#111923', border: '1px solid rgba(214, 190, 133, 0.28)', borderRadius: 14 }} />
                    <Bar dataKey="avg_signed_cents" fill="#d8a53f" name={t('progress.howSharpFlat')} radius={[7, 7, 0, 0]} />
                    <Bar dataKey="stddev_cents" fill="#59c9b2" name={t('progress.howSteady')} radius={[7, 7, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {stats.length > 0 && (
            <div className="pg-advanced-block">
              <h3>{t('progress.allNotes')}</h3>
              <NoteStatsTable rows={stats} />
            </div>
          )}
        </div>
      </details>
    </ScreenContainer>
  );
}
