import type { NoteStats } from '../domain/types';

export function NoteStatsTable({ rows }: { rows: NoteStats[] }) {
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
              <td>{row.avg_signed_cents > 0 ? '+' : ''}{row.avg_signed_cents.toFixed(1)}c</td>
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

