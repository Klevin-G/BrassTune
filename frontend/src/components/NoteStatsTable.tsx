import type { NoteStats } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';

export function NoteStatsTable({ rows }: { rows: NoteStats[] }) {
  const { t } = useI18n();
  return (
    <>
      <div className="note-card-list" role="list" aria-label={t('noteStats.mobile')}>
        {rows.map((row) => (
          <article className="note-stat-card" role="listitem" key={row.note_label}>
            <div className="note-stat-heading">
              <strong><bdi dir="ltr">{row.note_label}</bdi></strong>
              <span className={`severity-chip ${row.severity_color ?? 'green'}`}>{row.severity}</span>
            </div>
            <div className="note-stat-grid">
              <div>
                <span>{t('noteStats.signed')}</span>
                <b><bdi dir="ltr">
                  {row.avg_signed_cents > 0 ? '+' : ''}
                  {row.avg_signed_cents.toFixed(1)}c
                </bdi></b>
              </div>
              <div>
                <span>{t('noteStats.avgAbs')}</span>
                <b><bdi dir="ltr">{row.avg_abs_cents.toFixed(1)}c</bdi></b>
              </div>
              <div>
                <span>{t('tuning.inTune')}</span>
                <b><bdi dir="ltr">{Math.round(row.in_tune_percentage)}%</bdi></b>
              </div>
              <div>
                <span>{t('noteStats.duration')}</span>
                <b><bdi dir="ltr">{Math.round(row.duration_seconds)}s</bdi></b>
              </div>
            </div>
            <span className="trend-pill">{row.trend}</span>
          </article>
        ))}
      </div>
      <details className="advanced-table-toggle">
        <summary>{t('noteStats.showAdvanced')}</summary>
        <NoteTable rows={rows} />
      </details>
      <div className="desktop-note-table">
        <NoteTable rows={rows} />
      </div>
    </>
  );
}

function NoteTable({ rows }: { rows: NoteStats[] }) {
  const { t } = useI18n();
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>{t('noteStats.note')}</th>
            <th>{t('noteStats.avgError')}</th>
            <th>{t('noteStats.avgAbs')}</th>
            <th>{t('tuning.inTune')}</th>
            <th>{t('noteStats.trend')}</th>
            <th>{t('noteStats.samples')}</th>
            <th>{t('noteStats.duration')}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.note_label}>
              <td><bdi dir="ltr">{row.note_label}</bdi></td>
              <td>
                <bdi dir="ltr">{row.avg_signed_cents > 0 ? '+' : ''}{row.avg_signed_cents.toFixed(1)}c</bdi>
              </td>
              <td><bdi dir="ltr">{row.avg_abs_cents.toFixed(1)}c</bdi></td>
              <td><bdi dir="ltr">{Math.round(row.in_tune_percentage)}%</bdi></td>
              <td><span className="trend-pill">{row.trend}</span></td>
              <td><bdi dir="ltr">{row.sample_count}</bdi></td>
              <td><bdi dir="ltr">{Math.round(row.duration_seconds)}s</bdi></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
