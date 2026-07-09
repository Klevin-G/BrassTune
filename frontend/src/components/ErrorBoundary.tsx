import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
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
    return (
      <div className="route-error" role="alert">
        <div className="route-error-card">
          <h2>Something went wrong on this screen</h2>
          <p className="muted-copy">Your saved practice is safe. Try reloading, or head back to your dashboard.</p>
          <div className="settings-actions">
            <button className="primary-button" type="button" onClick={() => window.location.reload()}>Reload</button>
            <a className="ghost-button" href="/home" onClick={this.reset}>Go to dashboard</a>
          </div>
        </div>
      </div>
    );
  }
}
