import { describe, expect, it } from 'vitest';
import {
  ACCOUNT_DELETION_BACKEND_CONFIRMATION,
  matchesLocalizedDeletionConfirmation,
} from './SettingsPage';

describe('localized account deletion confirmation', () => {
  it('accepts the localized UI phrase while retaining the canonical backend phrase', () => {
    expect(matchesLocalizedDeletionConfirmation('  حذف حسابي ', 'حذف حسابي', 'ar')).toBe(true);
    expect(matchesLocalizedDeletionConfirmation('delete my account', 'حذف حسابي', 'ar')).toBe(false);
    expect(ACCOUNT_DELETION_BACKEND_CONFIRMATION).toBe('delete my account');
  });
});
