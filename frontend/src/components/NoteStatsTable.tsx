import type { NoteStats } from '../domain/types';

export function NoteStatsTable({ rows }: { rows: NoteStats[] }) {
  return (
    <>
      <div className="note-card-list" role="list" aria-label="Mobile note stats">
        {rows.map((row) => (
          <article className="note-stat-card" role="listitem" key={row.note_label}>
            <div className="note-stat-heading">
              <strong>{row.note_label}</strong>
              <span className={`severity-chip ${row.severity_color ?? 'green'}`}>{row.severity}</span>
            </div>
            <div className="note-stat-grid">
              <div>
                <span>Signed</span>
                <b>
                  {row.avg_signed_cents > 0 ? '+' : ''}
                  {row.avg_signed_cents.toFixed(1)}c
                </b>
              </div>
              <div>
                <span>Avg abs</span>
                <b>{row.avg_abs_cents.toFixed(1)}c</b>
              </div>
              <div>
                <span>In tune</span>
                <b>{Math.round(row.in_tune_percentage)}%</b>
              </div>
              <div>
                <span>Duration</span>
                <b>{Math.round(row.duration_seconds)}s</b>
              </div>
            </div>
            <span className="trend-pill">{row.trend}</span>
          </article>
        ))}
      </div>
      <details className="advanced-table-toggle">
        <summary>Show advanced table</summary>
        <NoteTable rows={rows} />
      </details>
      <div className="desktop-note-table">
        <NoteTable rows={rows} />
      </div>
    </>
  );
}

function NoteTable({ rows }: { rows: NoteStats[] }) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Note</th>
            <th>Avg Error</th>
            <th>Avg Abs</th>
            <th>In-Tune</th>
            <th>Trend</th>
            <th>Samples</th>
            <th>Duration</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.note_label}>
              <td>{row.note_label}</td>
              <td>
                {row.avg_signed_cents > 0 ? '+' : ''}
                {row.avg_signed_cents.toFixed(1)}c
              </td>
              <td>{row.avg_abs_cents.toFixed(1)}c</td>
              <td>{Math.round(row.in_tune_percentage)}%</td>
              <td><span className="trend-pill">{row.trend}</span></td>
              <td>{row.sample_count}</td>
              <td>{Math.round(row.duration_seconds)}s</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
