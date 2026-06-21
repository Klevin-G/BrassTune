import { lazy, Suspense } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { AuthPage } from './pages/AuthPage';

const AnalyticsPage = lazy(() => import('./pages/AnalyticsPage').then((module) => ({ default: module.AnalyticsPage })));
const AudioLabPage = lazy(() => import('./pages/AudioLabPage').then((module) => ({ default: module.AudioLabPage })));
const CoachPage = lazy(() => import('./pages/CoachPage').then((module) => ({ default: module.CoachPage })));
const DashboardPage = lazy(() => import('./pages/DashboardPage').then((module) => ({ default: module.DashboardPage })));
const EnsemblePage = lazy(() => import('./pages/EnsemblePage').then((module) => ({ default: module.EnsemblePage })));
const LegalPage = lazy(() => import('./pages/LegalPage').then((module) => ({ default: module.LegalPage })));
const MorePage = lazy(() => import('./pages/MorePage').then((module) => ({ default: module.MorePage })));
const MetronomePage = lazy(() => import('./pages/MetronomePage').then((module) => ({ default: module.MetronomePage })));
const PracticePage = lazy(() => import('./pages/PracticePage').then((module) => ({ default: module.PracticePage })));
const ProgressPage = lazy(() => import('./pages/ProgressPage').then((module) => ({ default: module.ProgressPage })));
const ScorePracticePage = lazy(() => import('./pages/ScorePracticePage').then((module) => ({ default: module.ScorePracticePage })));
const SessionReviewPage = lazy(() => import('./pages/SessionReviewPage').then((module) => ({ default: module.SessionReviewPage })));
const SessionsPage = lazy(() => import('./pages/SessionsPage').then((module) => ({ default: module.SessionsPage })));
const SettingsPage = lazy(() => import('./pages/SettingsPage').then((module) => ({ default: module.SettingsPage })));

export default function App() {
  return (
    <AppShell>
      <Suspense fallback={<div className="route-loading" role="status">Loading</div>}>
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/practice" element={<PracticePage />} />
          <Route path="/practice/score" element={<ScorePracticePage />} />
          <Route path="/metronome" element={<MetronomePage />} />
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
      </Suspense>
    </AppShell>
  );
}
