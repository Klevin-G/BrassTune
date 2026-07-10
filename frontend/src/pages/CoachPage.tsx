import { Navigate } from 'react-router-dom';

// Coach merged into the "Your progress" page (Plan section). Old links funnel here.
export function CoachPage() {
  return <Navigate replace to="/progress" />;
}
