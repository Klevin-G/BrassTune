import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { AuthProvider } from './state/AuthContext';
import { AppSettingsProvider } from './state/AppSettingsContext';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <AuthProvider>
        <AppSettingsProvider>
          <App />
        </AppSettingsProvider>
      </AuthProvider>
    </BrowserRouter>
  </React.StrictMode>,
);
