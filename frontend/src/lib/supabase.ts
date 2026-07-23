import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const supabaseDisabledForE2E = import.meta.env.VITE_E2E_DISABLE_SUPABASE === 'true';

export const supabaseConfigured = !supabaseDisabledForE2E && Boolean(supabaseUrl && supabasePublishableKey);
export const authProviders = {
  google: import.meta.env.VITE_AUTH_GOOGLE_ENABLED === 'true' || import.meta.env.VITE_SUPABASE_GOOGLE_ENABLED === 'true',
  apple: import.meta.env.VITE_AUTH_APPLE_ENABLED === 'true' || import.meta.env.VITE_SUPABASE_APPLE_ENABLED === 'true',
};

export const supabase = supabaseConfigured
  ? createClient(supabaseUrl, supabasePublishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;
