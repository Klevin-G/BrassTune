import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { AnalyticsPage } from './pages/AnalyticsPage';
import { AudioLabPage } from './pages/AudioLabPage';
import { AuthPage } from './pages/AuthPage';
import { CoachPage } from './pages/CoachPage';
import { DashboardPage } from './pages/DashboardPage';
import { EnsemblePage } from './pages/EnsemblePage';
import { LegalPage } from './pages/LegalPage';
import { MorePage } from './pages/MorePage';
import { PracticePage } from './pages/PracticePage';
import { ProgressPage } from './pages/ProgressPage';
import { SessionReviewPage } from './pages/SessionReviewPage';
import { SessionsPage } from './pages/SessionsPage';
import { SettingsPage } from './pages/SettingsPage';

export default function App() {
  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/practice" element={<PracticePage />} />
        <Route path="/sessions" element={<SessionsPage />} />
        <Route path="/sessions/:id" element={<SessionReviewPage />} />
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/progress" element={<ProgressPage />} />
        <Route path="/coach" element={<CoachPage />} />
        <Route path="/more" element={<MorePage />} />
        <Route path="/ensemble" element={<EnsemblePage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/settings/audio-lab" element={<AudioLabPage />} />
        <Route path="/privacy" element={<LegalPage kind="privacy" />} />
        <Route path="/terms" element={<LegalPage kind="terms" />} />
        <Route path="/support" element={<LegalPage kind="support" />} />
        <Route path="/auth/sign-in" element={<AuthPage mode="sign-in" />} />
        <Route path="/auth/sign-up" element={<AuthPage mode="sign-up" />} />
        <Route path="/auth/reset-password" element={<AuthPage mode="reset" />} />
        <Route path="/auth/callback" element={<AuthPage mode="callback" />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  );
}
