import { FileText, Music2, Printer, Target, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { getEnsembleReport, getEnsembleSummary } from '../api/client';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { InsightCard, PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';

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
    <ScreenContainer>
      <PageHeader
        eyebrow="Ensemble"
        title="Director briefing"
        description="A local report view for seeing section-level intonation tendencies and turning them into a rehearsal focus."
        action={
          <button className="primary-button" onClick={() => window.print()} type="button">
            <Printer size={18} />
            Export report
          </button>
        }
      />
      <SectionCard title="Section trends" eyebrow="Brass sections">
        <div className="section-trend-grid">
          {summary?.sections?.map((section: any) => (
            <article key={section.instrument_id}>
              <span>{section.instrument_id}</span>
              <strong>{section.average_abs_cents.toFixed(1)}c</strong>
              <p>{section.session_count} sessions, {section.practice_minutes} minutes</p>
            </article>
          ))}
        </div>
      </SectionCard>
      <div className="insight-grid">
        <InsightCard
          title="Briefing summary"
          detail="Director handoff"
          body={report?.recommended_rehearsal_focus ?? 'Seed data will populate the rehearsal focus when the backend is running.'}
          icon={FileText}
          tone="gold"
        />
        <InsightCard
          title="Long-tone sequence"
          detail={`${report?.suggested_long_tone_sequence?.length ?? 0} steps`}
          body="Use the sequence as a section warmup before repertoire excerpts."
          icon={Music2}
          tone="green"
        />
        <InsightCard
          title="Priority lens"
          detail="Top problem notes"
          body="The table below ranks note issues by severity across the seeded ensemble sessions."
          icon={Target}
          tone="amber"
        />
      </div>
      <SectionCard title="Rehearsal focus" eyebrow="Suggested sequence">
        <div className="plan-steps">
          {report?.suggested_long_tone_sequence?.map((item: string, index: number) => (
            <article key={item}>
              <span>
                <Users size={15} /> {index + 1}
              </span>
              <p>{item}</p>
            </article>
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Top problem notes" eyebrow="Ensemble data">
        <NoteStatsTable rows={report?.top_problem_notes ?? []} />
      </SectionCard>
    </ScreenContainer>
  );
}
