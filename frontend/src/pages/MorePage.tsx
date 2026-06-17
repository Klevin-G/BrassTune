import { Activity, Bug, FileText, Music2, Settings, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';

const moreItems = [
  { to: '/sessions', title: 'Sessions', detail: 'Review practice history and open saved takes.', icon: Music2 },
  { to: '/progress', title: 'Progress', detail: 'See weekly pulse, improvement, and consistency.', icon: Activity },
  { to: '/ensemble', title: 'Ensemble', detail: 'Director briefing cards and rehearsal focus.', icon: Users },
  { to: '/settings', title: 'Settings', detail: 'Instrument, A4 reference, and demo preferences.', icon: Settings },
  { to: '/settings/audio-lab', title: 'Audio Lab', detail: 'Developer calibration readout for real-device tuning tests.', icon: Bug },
];

export function MorePage() {
  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Secondary hub"
        title="More"
        description="The core practice loop stays close at hand. Reporting, saved work, and configuration live here when you need them."
      />
      <SectionCard title="Workspace">
        <div className="more-grid">
          {moreItems.map((item) => (
            <Link className="action-tile" key={item.to} to={item.to}>
              <span className="action-icon">
                <item.icon size={19} />
              </span>
              <span>
                <strong>{item.title}</strong>
                <em>{item.detail}</em>
              </span>
            </Link>
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Quick export" eyebrow="Local MVP">
        <div className="insight-grid">
          <article className="insight-card tone-gold">
            <div className="insight-heading">
              <span className="insight-icon">
                <FileText size={18} />
              </span>
              <div>
                <h3>Session reports</h3>
                <span>CSV and JSON exports stay available inside each session review.</span>
              </div>
            </div>
            <p>Use review screens for handoff-ready evidence: averages, heatmaps, note tables, and coach notes.</p>
          </article>
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
