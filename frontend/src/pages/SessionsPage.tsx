import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { listSessions } from '../api/client';
import type { PracticeSession } from '../domain/types';

export function SessionsPage() {
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  useEffect(() => {
    listSessions().then(setSessions).catch(() => setSessions([]));
  }, []);
  return (
    <section className="panel wide">
      <div className="section-heading">
        <h2>Practice sessions</h2>
        <Link to="/practice" className="primary-button">New session</Link>
      </div>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Instrument</th>
              <th>Date</th>
              <th>Notes</th>
              <th>Avg Abs</th>
              <th>In-Tune</th>
            </tr>
          </thead>
          <tbody>
            {sessions.map((session) => (
              <tr key={session.id}>
                <td><Link to={`/sessions/${session.id}`}>{session.name}</Link></td>
                <td>{session.instrument_id}</td>
                <td>{new Date(session.started_at).toLocaleDateString()}</td>
                <td>{session.notes_count}</td>
                <td>{session.average_abs_cents.toFixed(1)}c</td>
                <td>{Math.round(session.in_tune_percentage)}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

