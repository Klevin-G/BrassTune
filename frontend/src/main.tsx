import React from 'react';
import ReactDOM from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import App from './App';
import { exposeBuildRevision } from './buildRevision';
import { AuthProvider } from './state/AuthContext';
import { AppSettingsProvider } from './state/AppSettingsContext';
import { PracticeLibraryProvider } from './state/PracticeLibraryContext';
import { ThemeProvider } from './state/ThemeContext';
import { registerOfflineShell } from './registerOfflineShell';
import './styles.css';
import { LocaleProvider } from './i18n/LocaleContext';

exposeBuildRevision(document);

const router = createBrowserRouter([
  {
    path: '*',
    element: (
      <LocaleProvider>
        <ThemeProvider>
          <AuthProvider>
            <AppSettingsProvider>
              <PracticeLibraryProvider>
                <App />
              </PracticeLibraryProvider>
            </AppSettingsProvider>
          </AuthProvider>
        </ThemeProvider>
      </LocaleProvider>
    ),
  },
], {
  future: { v7_relativeSplatPath: true },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} future={{ v7_startTransition: true }} />
  </React.StrictMode>,
);

registerOfflineShell();
