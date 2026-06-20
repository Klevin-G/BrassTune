# Accessibility Beta Checklist

Status: manual checklist plus automated axe smoke coverage.

## Automated

`frontend/e2e/accessibility.spec.ts` runs axe checks on core pages and fails on serious or critical issues.

Run:

```bash
cd frontend
CI=true npm run e2e:local
```

## Manual Web Checks

- Keyboard can reach onboarding, practice, session review, auth, settings, legal, and support.
- Focus is visible after route changes, dialogs, form errors, export actions, and destructive prompts.
- Screen reader labels describe icon-only actions, meters, status messages, and destructive controls.
- Reduced motion does not hide required status changes.
- Mobile Safari viewport has no clipped controls or horizontal scroll.
- Color is not the only signal for pitch status, warnings, errors, or disabled controls.

## Native Checks

- VoiceOver can reach Home, Practice, Sessions, Session Review, Analytics, Ensemble, Settings, and account-disabled copy.
- Dynamic Type does not clip critical buttons or session metrics.
- iPad layout remains usable and does not present fixture/demo data as real account data.
- Dark mode keeps text contrast readable.
