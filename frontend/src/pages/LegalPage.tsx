import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';

export function LegalPage({ kind }: { kind: 'privacy' | 'terms' | 'support' }) {
  if (kind === 'terms') {
    return (
      <ScreenContainer>
        <PageHeader eyebrow="Legal" title="Terms of Service" description="Use BrassTune only with consent from the account holder and within the policies of the school, studio, or organization providing access." />
        <SectionCard title="Use of BrassTune">
          <p>BrassTune provides practice analytics and tuning feedback. It does not replace instruction, medical advice, or hearing-safety guidance.</p>
          <p>Users are responsible for choosing when to record, reviewing exports before sharing them, and following ensemble or school rules for student data.</p>
        </SectionCard>
        <SectionCard title="Accounts and data">
          <p>Users with accounts can export their data and initiate account deletion in Settings. Teacher-owned ensembles are deleted when the teacher account is deleted.</p>
          <Link className="primary-button" to="/settings">Open Settings</Link>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (kind === 'support') {
    return (
      <ScreenContainer>
        <PageHeader eyebrow="Support" title="Support" description="Use this page for in-app support guidance while owner-operated support channels are finalized for release metadata." />
        <SectionCard title="Getting help">
          <p>Students should contact the teacher, director, or organization that provided BrassTune access. Local demo users can use Settings to repair or reset seeded data.</p>
          <p>For account deletion, export, sign-in, microphone permission, recording, playback, and ensemble access issues, include the affected screen and approximate time of the issue.</p>
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader eyebrow="Privacy" title="Privacy Policy" description="BrassTune stores practice data only to provide tuning feedback, playback, analytics, ensemble reports, export, and account lifecycle controls." />
      <SectionCard title="Data BrassTune uses">
        <p>Account profile, instrument settings, practice sessions, pitch samples, note events, recommendations, ensemble memberships, invitations, and optional retained recordings are used to operate the app.</p>
        <p>Local media imports are analyzed in the browser. The selected source video or audio file is not uploaded or stored by BrassTune.</p>
      </SectionCard>
      <SectionCard title="Control">
        <p>Settings provides data export, session clearing, sign-out, and account deletion. Recordings require an explicit recording action and can be deleted with their sessions.</p>
        <Link className="primary-button" to="/settings">Manage data</Link>
      </SectionCard>
    </ScreenContainer>
  );
}
