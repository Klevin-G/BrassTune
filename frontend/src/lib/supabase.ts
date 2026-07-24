import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const supabaseDisabledForE2E = import.meta.env.VITE_E2E_DISABLE_SUPABASE === 'true';

export const supabaseConfigured = !supabaseDisabledForE2E && Boolean(supabaseUrl && supabasePublishableKey);

export function resolveAuthProviders(env: Record<string, unknown>) {
  return {
    google: env.VITE_AUTH_GOOGLE_ENABLED === 'true' || env.VITE_SUPABASE_GOOGLE_ENABLED === 'true',
    apple: env.VITE_AUTH_APPLE_ENABLED === 'true' || env.VITE_SUPABASE_APPLE_ENABLED === 'true',
  };
}

export const authProviders = resolveAuthProviders(import.meta.env);

export const supabaseClientOptions = {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
} as const;

export const supabase = supabaseConfigured
  ? createClient(supabaseUrl, supabasePublishableKey, supabaseClientOptions)
  : null;
