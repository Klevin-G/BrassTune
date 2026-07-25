import { useState } from 'react';
import { ArrowLeft, ArrowRight, Check, Copy, Download, Mail, Mic, UserX, Users } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { SUPPORT_EMAIL, supportGmailComposeUrl } from '../domain/supportContact';
import './LegalPage.css';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

function BackButton() {
  const navigate = useNavigate();
  const { t } = useI18n();
  const goBack = () => {
    if (window.history.length > 1) navigate(-1);
    else navigate('/settings');
  };
  return (
    <button type="button" className="ghost-button" onClick={goBack}>
      <ArrowLeft size={16} />
      {t('legal.back')}
    </button>
  );
}

type FaqItem = { icon: LucideIcon; question: MessageId; answer: MessageId; to: string; cta: MessageId };

const FAQ: FaqItem[] = [
  {
    icon: Mic,
    question: 'legal.faq.mic.question',
    answer: 'legal.faq.mic.answer',
    to: '/settings',
    cta: 'legal.faq.mic.cta',
  },
  {
    icon: Users,
    question: 'legal.faq.class.question',
    answer: 'legal.faq.class.answer',
    to: '/ensemble',
    cta: 'legal.faq.class.cta',
  },
  {
    icon: Download,
    question: 'legal.faq.export.question',
    answer: 'legal.faq.export.answer',
    to: '/sessions',
    cta: 'legal.faq.export.cta',
  },
  {
    icon: UserX,
    question: 'legal.faq.delete.question',
    answer: 'legal.faq.delete.answer',
    to: '/settings',
    cta: 'legal.faq.delete.cta',
  },
];

function SupportContact() {
  const [copied, setCopied] = useState(false);
  const { t } = useI18n();

  const copyEmail = async () => {
    try {
      await navigator.clipboard.writeText(SUPPORT_EMAIL);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };

  return (
    <div className="lg-contact">
      <div className="settings-actions">
        <a
          className="primary-button"
          href={supportGmailComposeUrl()}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={t('legal.email')}
        >
          <Mail size={18} />
          {t('legal.email')}
        </a>
        <button className="ghost-button" type="button" onClick={copyEmail} aria-live="polite">
          {copied ? <Check size={18} /> : <Copy size={18} />}
          {copied ? t('legal.copied') : t('legal.copy')}
        </button>
      </div>
      <p className="lg-address muted-copy">{SUPPORT_EMAIL}</p>
    </div>
  );
}

export function LegalPage({ kind }: { kind: 'privacy' | 'terms' | 'support' }) {
  const { t } = useI18n();
  if (kind === 'terms') {
    return (
      <ScreenContainer>
        <PageHeader
          title={t('legal.termsTitle')}
          description={t('legal.termsDescription')}
          action={<BackButton />}
        />
        <SectionCard title={t('legal.usingTitle')}>
          <p>{t('legal.usingBody1')}</p>
          <p>{t('legal.usingBody2')}</p>
        </SectionCard>
        <SectionCard title={t('legal.accountsTitle')}>
          <p>{t('legal.accountsBody')}</p>
          <Link className="primary-button" to="/settings">{t('legal.openSettings')}</Link>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (kind === 'support') {
    return (
      <ScreenContainer>
        <PageHeader title={t('legal.supportTitle')} description={t('legal.supportDescription')} action={<BackButton />} />
        <SectionCard title={t('legal.common')}>
          <div className="lg-faq-list">
            {FAQ.map(({ icon: Icon, question, answer, to, cta }) => (
              <div className="lg-faq" key={question}>
                <span className="lg-faq-icon"><Icon size={18} /></span>
                <h3>{t(question)}</h3>
                <p>{t(answer)}</p>
                <Link className="lg-faq-link" to={to}>
                  {t(cta)}
                  <ArrowRight size={14} />
                </Link>
              </div>
            ))}
          </div>
        </SectionCard>
        <SectionCard title={t('legal.moreHelp')}>
          <p className="lg-lead">{t('legal.moreHelpBody')}</p>
          <SupportContact />
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader
        title={t('legal.privacyTitle')}
        description={t('legal.privacyDescription')}
        action={<BackButton />}
      />
      <SectionCard title={t('legal.dataTitle')}>
        <p>{t('legal.dataBody1')}</p>
        <p>{t('legal.dataBody2')}</p>
      </SectionCard>
      <SectionCard title={t('legal.classTitle')}>
        <p>{t('legal.classBody')}</p>
      </SectionCard>
      <SectionCard title={t('legal.controlTitle')}>
        <p>{t('legal.controlBody')}</p>
        <Link className="primary-button" to="/settings">{t('legal.manage')}</Link>
      </SectionCard>
    </ScreenContainer>
  );
}
