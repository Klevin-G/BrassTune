export const SUPPORT_EMAIL = 'brasstune1@gmail.com';
export const SUPPORT_SUBJECT = 'BrassTune support';

const GMAIL_COMPOSE_URL = 'https://mail.google.com/mail/';

export function supportGmailComposeUrl(): string {
  const query = new URLSearchParams({
    view: 'cm',
    fs: '1',
    to: SUPPORT_EMAIL,
    su: SUPPORT_SUBJECT,
  });

  return `${GMAIL_COMPOSE_URL}?${query.toString()}`;
}
