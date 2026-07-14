import { describe, expect, it } from 'vitest';
import { SUPPORT_EMAIL, SUPPORT_SUBJECT, supportGmailComposeUrl } from './supportContact';

describe('supportGmailComposeUrl', () => {
  it('opens a secure Gmail compose form addressed to BrassTune support', () => {
    const url = new URL(supportGmailComposeUrl());

    expect(url.origin).toBe('https://mail.google.com');
    expect(url.pathname).toBe('/mail/');
    expect(url.searchParams.get('view')).toBe('cm');
    expect(url.searchParams.get('fs')).toBe('1');
    expect(url.searchParams.get('to')).toBe(SUPPORT_EMAIL);
    expect(url.searchParams.get('su')).toBe(SUPPORT_SUBJECT);
  });

  it('URL-encodes the email address and subject', () => {
    expect(supportGmailComposeUrl()).toContain('to=brasstune1%40gmail.com');
    expect(supportGmailComposeUrl()).toContain('su=BrassTune+support');
  });
});
