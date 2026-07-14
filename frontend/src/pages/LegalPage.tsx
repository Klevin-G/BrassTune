import { useState } from 'react';
import { ArrowLeft, ArrowRight, Check, Copy, Download, Mail, Mic, UserX, Users } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { SUPPORT_EMAIL, supportGmailComposeUrl } from '../domain/supportContact';
import './LegalPage.css';

function BackButton() {
  const navigate = useNavigate();
  const goBack = () => {
    if (window.history.length > 1) navigate(-1);
    else navigate('/settings');
  };
  return (
    <button type="button" className="ghost-button" onClick={goBack}>
      <ArrowLeft size={16} />
      Back
    </button>
  );
}

type FaqItem = { icon: LucideIcon; question: string; answer: string; to: string; cta: string };

const FAQ: FaqItem[] = [
  {
    icon: Mic,
    question: 'Allow microphone access',
    answer: 'BrassTune needs your mic to hear you play. If the tuner stays quiet, run a quick mic check in Settings and allow access when your browser asks.',
    to: '/settings',
    cta: 'Open Settings',
  },
  {
    icon: Users,
    question: 'Join my class',
    answer: 'Ask your director to invite you, then accept the invite on the Class page. You pick your own instrument when you join.',
    to: '/ensemble',
    cta: 'Go to Class',
  },
  {
    icon: Download,
    question: 'Export a session',
    answer: 'Open any saved recording and use the export options in its review to download your practice data.',
    to: '/sessions',
    cta: 'Open your sessions',
  },
  {
    icon: UserX,
    question: 'Delete my account',
    answer: 'You can export your data and delete your account any time from Settings.',
    to: '/settings',
    cta: 'Open Settings',
  },
];

function SupportContact() {
  const [copied, setCopied] = useState(false);

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
          aria-label="Email BrassTune support in Gmail (opens in a new tab)"
        >
          <Mail size={18} />
          Email support
        </a>
        <button className="ghost-button" type="button" onClick={copyEmail} aria-live="polite">
          {copied ? <Check size={18} /> : <Copy size={18} />}
          {copied ? 'Copied' : 'Copy address'}
        </button>
      </div>
      <p className="lg-address muted-copy">{SUPPORT_EMAIL}</p>
    </div>
  );
}

export function LegalPage({ kind }: { kind: 'privacy' | 'terms' | 'support' }) {
  if (kind === 'terms') {
    return (
      <ScreenContainer>
        <PageHeader
          title="Terms of Service"
          description="Use BrassTune with permission from the account holder, and follow your school or studio's rules."
          action={<BackButton />}
        />
        <SectionCard title="Using BrassTune">
          <p>BrassTune gives you practice feedback and tuning help. It doesn't replace a teacher, medical advice, or hearing-safety guidance.</p>
          <p>You choose when to record, and it's up to you to check exports before you share them and to follow your class or school rules for student data.</p>
        </SectionCard>
        <SectionCard title="Accounts and data">
          <p>You can export your data and delete your account from Settings. When a teacher deletes their account, their classes are deleted too.</p>
          <Link className="primary-button" to="/settings">Open Settings</Link>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (kind === 'support') {
    return (
      <ScreenContainer>
        <PageHeader title="Support" description="Need help? Here's how to reach us." action={<BackButton />} />
        <SectionCard title="Common questions">
          <div className="lg-faq-list">
            {FAQ.map(({ icon: Icon, question, answer, to, cta }) => (
              <div className="lg-faq" key={question}>
                <span className="lg-faq-icon"><Icon size={18} /></span>
                <h3>{question}</h3>
                <p>{answer}</p>
                <Link className="lg-faq-link" to={to}>
                  {cta}
                  <ArrowRight size={14} />
                </Link>
              </div>
            ))}
          </div>
        </SectionCard>
        <SectionCard title="Still need help?">
          <p className="lg-lead">Students: your teacher or director can usually help fastest. For anything else, email us — tell us which screen you were on and roughly when it happened.</p>
          <SupportContact />
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader
        title="Privacy Policy"
        description="We store practice data only to run the app's features."
        action={<BackButton />}
      />
      <SectionCard title="Data BrassTune uses">
        <p>Your profile, settings, practice sessions, and any recordings you choose to keep.</p>
        <p>Media you import is analyzed in your browser. The file you pick is never uploaded or stored by BrassTune.</p>
      </SectionCard>
      <SectionCard title="Your control">
        <p>Settings lets you export your data, clear sessions, sign out, and delete your account. Recordings only happen when you tap record, and they're deleted along with their session.</p>
        <Link className="primary-button" to="/settings">Manage data</Link>
      </SectionCard>
    </ScreenContainer>
  );
}
