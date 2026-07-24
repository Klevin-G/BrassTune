# Third-Party Asset Provenance

Updated: 2026-07-23.

This repository vendors only the small sign-in artwork needed by the web and iOS UI. The parent controls accessible labels; artwork is decorative.

| Asset | Source and provenance | Integrity / usage |
|---|---|---|
| Google sign-in logo | Google Identity artwork archive: [signin-assets.zip](https://developers.google.com/static/identity/images/signin-assets.zip). Source comment identifies `Android + Web/PNG @1x/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web.png`. | SHA-256: `33f5ab7c3d6b6af7c8cdd3e917e4475d9a2ffd407a7667a68747140b290bdeb8`. Used by `frontend/src/assets/googleSignInLogo.ts` and the matching native control. Follow [Google branding guidelines](https://developers.google.com/identity/branding-guidelines). |
| Apple sign-in logo | Apple-generated logo endpoint: [Apple sign-in button asset](https://appleid.cdn-apple.com/appleid/button/logo?size=30&color=black&border=false&border_radius=0&scale=2). | Vendored PNG data URI in `frontend/src/assets/appleSignInLogo.ts`; generated from the documented Apple endpoint. Follow the [Sign in with Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple). |

Do not replace these with hand-drawn logos or alter protected marks. Recheck the upstream branding rules before changing provider button composition, colors, or label treatment.
