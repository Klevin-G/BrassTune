import { Component, type ErrorInfo, type ReactNode } from 'react';
import { useI18n } from '../i18n/LocaleContext';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
}

function ErrorFallback({ onReset }: { onReset: () => void }) {
  const { t } = useI18n();
  return (
    <div className="route-error" role="alert">
      <div className="route-error-card">
        <h2>{t('error.screenTitle')}</h2>
        <p className="muted-copy">{t('error.screenBody')}</p>
        <div className="settings-actions">
          <button className="primary-button" type="button" onClick={() => window.location.reload()}>{t('error.reload')}</button>
          <a className="ghost-button" href="/home" onClick={onReset}>{t('error.dashboard')}</a>
        </div>
      </div>
    </div>
  );
}

/**
 * Catches render errors in a page so a single broken screen shows a friendly
 * recovery card instead of blanking the whole app.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    // Keep a console trace for diagnostics; no third-party reporter.
    console.error('BrassTune page error:', error, info.componentStack);
  }

  private reset = () => {
    this.setState({ hasError: false });
  };

  render(): ReactNode {
    if (!this.state.hasError) return this.props.children;
    return <ErrorFallback onReset={this.reset} />;
  }
}
