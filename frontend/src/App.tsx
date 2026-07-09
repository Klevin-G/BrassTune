import { lazy, Suspense } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';
import { useAuth } from './state/AuthContext';
import { AuthGatewayPage } from './pages/AuthGatewayPage';
import { AuthPage } from './pages/AuthPage';

const AdminMetricsPage = lazy(() => import('./pages/AdminMetricsPage').then((module) => ({ default: module.AdminMetricsPage })));
const AnalyticsPage = lazy(() => import('./pages/AnalyticsPage').then((module) => ({ default: module.AnalyticsPage })));
const AudioLabPage = lazy(() => import('./pages/AudioLabPage').then((module) => ({ default: module.AudioLabPage })));
const CoachPage = lazy(() => import('./pages/CoachPage').then((module) => ({ default: module.CoachPage })));
const DashboardPage = lazy(() => import('./pages/DashboardPage').then((module) => ({ default: module.DashboardPage })));
const EnsemblePage = lazy(() => import('./pages/EnsemblePage').then((module) => ({ default: module.EnsemblePage })));
const LegalPage = lazy(() => import('./pages/LegalPage').then((module) => ({ default: module.LegalPage })));
const MorePage = lazy(() => import('./pages/MorePage').then((module) => ({ default: module.MorePage })));
const MetronomePage = lazy(() => import('./pages/MetronomePage').then((module) => ({ default: module.MetronomePage })));
const PlayAlongPage = lazy(() => import('./pages/PlayAlongPage').then((module) => ({ default: module.PlayAlongPage })));
const PracticePage = lazy(() => import('./pages/PracticePage').then((module) => ({ default: module.PracticePage })));
const ProgressPage = lazy(() => import('./pages/ProgressPage').then((module) => ({ default: module.ProgressPage })));
const ScorePracticePage = lazy(() => import('./pages/ScorePracticePage').then((module) => ({ default: module.ScorePracticePage })));
const SessionReviewPage = lazy(() => import('./pages/SessionReviewPage').then((module) => ({ default: module.SessionReviewPage })));
const SessionsPage = lazy(() => import('./pages/SessionsPage').then((module) => ({ default: module.SessionsPage })));
const SettingsPage = lazy(() => import('./pages/SettingsPage').then((module) => ({ default: module.SettingsPage })));

function RequireAppAccess({ children }: { children: JSX.Element }) {
  const auth = useAuth();
  const location = useLocation();
  if (auth.loading) {
    return <div className="route-loading" role="status">Restoring session</div>;
  }
  if (auth.isSignedIn || auth.guestMode) {
    return children;
  }
  const next = encodeURIComponent(`${location.pathname}${location.search}`);
  return <Navigate to={`/?next=${next}`} replace />;
}

function appRoute(element: JSX.Element) {
  return <RequireAppAccess>{element}</RequireAppAccess>;
}

export default function App() {
  return (
    <AppShell>
      <ErrorBoundary>
      <Suspense fallback={<div className="route-loading" role="status">Loading</div>}>
        <Routes>
          <Route path="/" element={<AuthGatewayPage />} />
          <Route path="/home" element={appRoute(<DashboardPage />)} />
          <Route path="/practice" element={appRoute(<PracticePage />)} />
          <Route path="/practice/score" element={appRoute(<ScorePracticePage />)} />
          <Route path="/practice/play-along" element={appRoute(<PlayAlongPage />)} />
          <Route path="/metronome" element={appRoute(<MetronomePage />)} />
          <Route path="/sessions" element={appRoute(<SessionsPage />)} />
          <Route path="/sessions/:id" element={appRoute(<SessionReviewPage />)} />
          <Route path="/analytics" element={appRoute(<AnalyticsPage />)} />
          <Route path="/progress" element={appRoute(<ProgressPage />)} />
          <Route path="/coach" element={appRoute(<CoachPage />)} />
          <Route path="/more" element={appRoute(<MorePage />)} />
          <Route path="/ensemble" element={appRoute(<EnsemblePage />)} />
          <Route path="/settings" element={appRoute(<SettingsPage />)} />
          <Route path="/settings/audio-lab" element={appRoute(<AudioLabPage />)} />
          <Route path="/admin" element={appRoute(<AdminMetricsPage />)} />
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
      </ErrorBoundary>
    </AppShell>
  );
}
