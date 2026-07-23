import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { AuthProvider } from './state/AuthContext';
import { AppSettingsProvider } from './state/AppSettingsContext';
import { PracticeLibraryProvider } from './state/PracticeLibraryContext';
import { ThemeProvider } from './state/ThemeContext';
import { registerOfflineShell } from './registerOfflineShell';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider>
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AuthProvider>
          <AppSettingsProvider>
            <PracticeLibraryProvider>
              <App />
            </PracticeLibraryProvider>
          </AppSettingsProvider>
        </AuthProvider>
      </BrowserRouter>
    </ThemeProvider>
  </React.StrictMode>,
);

registerOfflineShell();
