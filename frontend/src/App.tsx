import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { AnalyticsPage } from './pages/AnalyticsPage';
import { CoachPage } from './pages/CoachPage';
import { DashboardPage } from './pages/DashboardPage';
import { EnsemblePage } from './pages/EnsemblePage';
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
        <Route path="/ensemble" element={<EnsemblePage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AppShell>
  );
}

