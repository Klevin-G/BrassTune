import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { LoadingSkeleton } from './AppPrimitives';

describe('LoadingSkeleton', () => {
  it('exposes its caller-provided localized loading message as a polite status', () => {
    const markup = renderToStaticMarkup(createElement(LoadingSkeleton, {
      rows: 2,
      label: 'Cargando progreso…',
    }));
    expect(markup).toContain('role="status"');
    expect(markup).toContain('aria-live="polite"');
    expect(markup).toContain('aria-label="Cargando progreso…"');
    expect(markup).not.toContain('aria-label="Loading"');
  });
});
