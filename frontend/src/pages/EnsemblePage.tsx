import { useEffect, useState } from 'react';
import { getEnsembleReport, getEnsembleSummary } from '../api/client';
import { NoteStatsTable } from '../components/NoteStatsTable';

export function EnsemblePage() {
  const [summary, setSummary] = useState<any>(null);
  const [report, setReport] = useState<any>(null);
  useEffect(() => {
    Promise.all([getEnsembleSummary(), getEnsembleReport()]).then(([summaryData, reportData]) => {
      setSummary(summaryData);
      setReport(reportData);
    });
  }, []);
  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>Ensemble Mode</h2>
          <p>Local director view built from seeded student sessions.</p>
        </div>
        <button className="ghost-button" onClick={() => window.print()} type="button">Export rehearsal report</button>
      </section>
      <section className="panel wide">
        <h2>Section trends</h2>
        <div className="section-trend-grid">
          {summary?.sections?.map((section: any) => (
            <article key={section.instrument_id}>
              <span>{section.instrument_id}</span>
              <strong>{section.average_abs_cents.toFixed(1)}c</strong>
              <p>{section.session_count} sessions, {section.practice_minutes} minutes</p>
            </article>
          ))}
        </div>
      </section>
      <section className="panel wide">
        <h2>Top problem notes</h2>
        <NoteStatsTable rows={report?.top_problem_notes ?? []} />
      </section>
      <section className="panel wide">
        <h2>Rehearsal focus</h2>
        <p className="report-copy">{report?.recommended_rehearsal_focus}</p>
        <div className="plan-steps">
          {report?.suggested_long_tone_sequence?.map((item: string, index: number) => (
            <article key={item}>
              <span>{index + 1}</span>
              <p>{item}</p>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

