# Welcome 1.0.7 (19), marketing website and recovery — October 12, 2026

Project attribution: Kelvin Guo, Arya Salem.

## Current state

**iOS 1.0.7 (19) is Testing in the existing BrassTune Internal QA group, with the same three testers.** Apple completed processing; build-specific What to Test notes were saved, and the group’s Builds page was checked. No people or external groups were added. Build 18 remains an earlier internal candidate. The processing monitor is paused after its completed build-18 task; no monitor is needed for the now-verified build 19.

The public app remains **1.0.6 (17)**. Public submission of 1.0.7 remains held for the recurring Google sign-in failure on the owner’s separate downloaded-app iPhone. The owner will retry that phone later. No simulator or different-phone result proves that failure is fixed.

The marketing website and separate recovery service are **implemented in this repository and locally verified, not deployed**. The owner said to continue with repository changes after the existing Vercel team could not be accessed, and explicitly selected a separate account-recovery service. No alternate Vercel site/team was substituted. The available connector and browser session could not access the saved project.

## Native welcome

The welcome screen uses a white background, direct copy, prominent account creation/sign-in, quieter guest entry with a local-data disclosure, and a real licensed trumpet photograph. Repetitive tool labels and decorative letterspacing were removed after Claude’s review. The image is bundled in `Resources/Assets.xcassets` and ignores hit testing: clipping its visible frame alone had allowed its larger touch region to intercept nearby links. Credits now opens a sheet with an explicit, localized Done control.

### Device evidence

The actual wired phone was discovered as an iPhone 15 Pro Max, iOS 26.6.2, Developer Mode enabled. The earlier network-paired target was a different device. The production-app activation canary passed 1/1. Final welcome/account/guest/Credits tests passed 3/3 on the isolated development app, plus a dedicated corrected maximum-text-size check passed 1/1. The production app/account was not replaced or reset.

Final simulator order was iPhone 17 Pro Max, iPhone 17 Pro, then iPhone SE. Each passed the three-case welcome/account/guest/Credits matrix. A corrected existing maximum-text navigation regression also passed on 17 Pro Max.

The first maximum-text test used an invalid UIKit raw string, so its earlier Arabic screenshots did not prove Accessibility XXXL. The test now uses `UICTContentSizeCategoryAccessibilityXXXL`; `simctl ui` independently read back `accessibility-extra-extra-extra-large` before the dedicated simulator runs. Those passed on all three models, and the simulator setting was restored to `large`. A subsequent harness failure waited for an offscreen lazy Form row; screenshots showed the account sheet was already open. The test now waits for the sheet’s navigation bar and scrolls to the field. These test corrections did not change uploaded app source or require another build.

### Signed artifact

Version/build: **1.0.7 (19)**; bundle: `com.aryasalem.BrassTune`. Archive and export succeeded. The exported IPA passed strict code-signature verification with Apple Distribution, `get-task-allow=false`, no development-device list, production callback/configuration, twelve localized bundles and the welcome image in Assets.car.

IPA SHA-256: `4a8237539d10f202a9d156cb57ab0deacf6fd17f29d3587b1df562f6dfc845eb`.

Upload succeeded at 19:36 CDT on October 12. App Store Connect build ID: `264be6bb-08a9-4355-941a-e0a5ac54eeeb`. Saved notes and Testing state are recorded privately under `ReleaseEvidence/WelcomeRefresh-2026-10-12/`, together with source fingerprints, exact xcresult summaries, corrected screenshots, signing and upload receipts.

## Static public website

`frontend/scripts/build-marketing.mjs` emits ignored `frontend/marketing-dist`. Its public pages are product information, Privacy, Terms, Support and Credits, plus a photo, robots.txt and sitemap.xml. The product pages contain no React bundle, sign-in/signup, tuner, practice tools, microphone/audio controls, backend requests or Supabase client. Retained React/Android source is separate from this output.

The headline is “A tuner made for brass.” Plain tool rows replace generic feature cards. The page links to the real App Store listing and uses currently released feature claims; it does not advertise internal goals, invented metrics, professor endorsements or automatic imported-score recognition. Privacy distinguishes native local media from retained cloud data and preserves provider, class, deletion/export and contact disclosures. Support includes a neutral invitation to leave an honest review after trying the app.

The retirement worker unregisters itself and deletes only legacy precache caches. It preserves runtime caches, localStorage, IndexedDB and user media, and never forces clients to reload. The ordinary landing-page script removes bounded OAuth fields from old URLs without transmitting them. A returning browser may still show its cached old app once while its existing worker updates.

Both Vercel configs build the static output, disable camera/microphone, restrict connections and retire old app routes. Production builds and the deployment workflow run `check-recovery-service.mjs` first: the live recovery page must have the reviewed headers/configuration and a script matching the SHA-256 contract stored inside frontend/. Repository checks bind that pin to backend source. The guard currently stops on the production route’s 404; a separate mocked success fixture passed without needing backend files inside the Vercel frontend upload. Marketing checks run in frontend CI and before deployment. The production smoke now checks static/legal assets, restrictive headers, exact retirement/bridge scripts, retired routes, and absent website API/WS paths instead of the obsolete interactive web-app journeys.

## Separate account-recovery service

Implemented route: `https://brasstune-u8qj.onrender.com/auth/reset-password`, with local HTML/CSS/JS served by `backend/app/api/password_recovery.py`. It emits only a validated Supabase HTTPS origin and `sb_publishable_` key. It never reads a service/secret key, receives password/token values through a backend proxy, persists a recovery session, includes third-party assets, or logs callback values. Headers include no-store, no-referrer, noindex, restrictive CSP, frame denial, COOP and disabled permissions.

The standalone Vercel `/auth/reset-password/` bridge has no password form and does not load the marketing cleanup script. It scrubs its URL and forwards only an accepted recovery shape to one fixed Render destination:

- Native implicit email links: the bridge validates expected fields and forwards only `type=recovery` plus the access token, never the refresh token.
- Legacy web PKCE: it reads only `sb-yznziwewxrlwnwiynlvl-auth-token-code-verifier`, requires the actual auth-js JSON string ending in lowercase `/recovery`, validates the RFC 7636 verifier, removes that one-use key, and forwards code/verifier only in the fragment. Duplicates, mixed shapes, malformed storage, provider errors and alternate destinations fail closed.

Render scrubs its fragment before asynchronous work. PKCE exchanges immediately, before the password form appears, directly with Supabase; it retains only the access token. Password updates also go directly to Supabase. Inputs/session state are cleared after attempts; errors use fixed safe copy. Legacy query-based PKCE codes may already appear in the initial Vercel request; the bridge does not add any token, verifier or password to a query or send them through Render HTTP requests.

The native reset URL deliberately remains the stable Vercel URL until deployment is verified, so no shipped build is prematurely pointed at a missing route. The exact Render URL is staged in `supabase/config.toml`; live settings were not changed. Preserve the legacy Vercel allowlist entry for installed apps and issued emails.

**Deployment order remains a gate:** deploy Render first, confirm its public-key configuration and real disposable-account implicit/PKCE reset flows, reconcile the exact live Supabase redirect when enabling direct requests, then publish the Vercel bridge/site and check legacy links. The production Render recovery route was 404 at discovery. Local implementation is not hosted recovery proof.

## Google Search Console

GSC Wizard verified the Search Console connection and scope. The exact URL-prefix property `https://brasstune.vercel.app/` was created in Google’s UI under that account. The generated HTML contains its public verification meta.

Ownership is **not yet verified** because the site is not published. The sitemap is generated but **not submitted**. Connection, ownership, indexing and ranking remain separate states.

## Checks

- Backend full suite: **364 passed, 13 skipped**. Existing environment-dependent integration skips remain.
- Recovery browser-flow Node tests: passed, including immediate PKCE exchange, exact public headers/destinations, failure behavior, input/session clearing and implicit recovery.
- `npm run test:marketing`: passed, including static pages/image, metadata, type-specific JSON-LD, contrast, executable cache retirement/OAuth cleanup and native/PKCE bridge regressions.
- Browser local recovery page: rendered with a synthetic test fragment, scrubbed the URL, and displayed the password form. No real password/token exchange was attempted.
- Live unauthenticated Supabase OPTIONS checks: 200 for the Render-origin POST token exchange and PUT user update, with the required headers permitted. This is CORS preflight evidence only.
- Browser marketing layouts: desktop, 440×956, then 375×667; landing/legal pages checked. Hosted marketing smoke remains unrun because deployment is unavailable.
- Native UI/device results: as above, with exact summaries independently read by the parent. Localization coverage and design-token checks passed.
- Earlier retained React checks: 295 unit tests, Vite build and 46 selected browser journeys passed; these are not marketing deployment proof.
- Node syntax checks, workflow YAML parsing, and `git diff --check`: passed.

Private evidence directories: `ReleaseEvidence/WelcomeRefresh-2026-10-12/`, `ReleaseEvidence/Marketing-2026-10-12/`. Raw Xcode artifacts remain outside Git under `/tmp`. No public app submission, website/backend deployment, main-branch commit, push or merge occurred. The isolated recovery worktree was integrated by explicit paths and then archived with a recoverable snapshot.

## Ownership and review

| Lane | Requested route | Purpose |
|---|---|---|
| Legal/repository scout | Luna Medium | Shared source map and public facts |
| Marketing implementation | Terra Medium | Static product/legal site and focused checks |
| Native tester | Terra Medium | Newer-first simulator and correct wired-device evidence |
| Recovery implementation | Terra High | Credential-handling migration in an isolated worktree |
| Independent reviewer | Sol High | Security, migration and release-boundary review |
| Correspondence scout | Terra Medium | Official contacts, fresh Gmail dedup and verified receipts |
| Claude Desktop | Visible Opus 5.5 High; Medium for final copy | Independent design/auth-dependency and wording review |

Effective Codex child routing was not independently observable. Claude’s displayed controls were verified; the cached Opus session was retained because switching models explicitly required rereading its entire history. No grandchildren were used.

Source areas: native welcome/legal views, localized copy, welcome asset and UI tests; static marketing source/build/checks and Vercel/CI configuration; recovery router/assets/tests and minimal backend registration; staged Supabase redirect; release docs and AGENTS guidance. Unrelated pre-existing dirty work remains intact.
