import { Navigate } from 'react-router-dom';

// Analytics merged into the single "Your progress" page. Old links funnel here.
export function AnalyticsPage() {
  return <Navigate replace to="/progress" />;
}
