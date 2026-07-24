# Third-Party Asset Provenance

Updated: 2026-07-23.

This repository vendors only the small sign-in artwork needed by the web and iOS UI. The parent controls accessible labels; artwork is decorative.

| Asset | Source and provenance | Integrity / usage |
|---|---|---|
| Google sign-in logo | Google Identity artwork archive: [signin-assets.zip](https://developers.google.com/static/identity/images/signin-assets.zip). The web source uses `Android + Web/PNG @1x/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web.png`; the iOS `GoogleSignInIcon` is an exact-pixel crop of Google's pre-approved iOS `Show text=No` artwork, without recoloring or redrawing. | The web source asset SHA-256 is `33f5ab7c3d6b6af7c8cdd3e917e4475d9a2ffd407a7667a68747140b290bdeb8`. The derived iOS crop is not byte-identical to that full archive asset; its provenance is the documented crop derivation. Follow [Google branding guidelines](https://developers.google.com/identity/branding-guidelines). |
| Google Sans Medium | Google Fonts [`Google Sans` weight 500](https://fonts.googleapis.com/css2?family=Google+Sans:wght@500), vendored unchanged as `GoogleSans-Medium.ttf`. The font names itself `GoogleSans-Medium` and carries `Copyright 2025 The Google Sans Project Authors (github.com/googlefonts/googlesans)` plus the Open Font License URL. Google Fonts metadata classifies the family license as `ofl`. | Font SHA-256 is `e9156f50951740b525f8e6d110e0be344214cb6d5fce1e76cd3e828a604997e9`. The app bundles the matching `GoogleSans-OFL.txt` license and uses this face only for the localized native Google sign-in CTA at the required 14-point size and 20-point line height. |
| Apple sign-in logo | Apple-generated logo endpoint: [Apple sign-in button asset](https://appleid.cdn-apple.com/appleid/button/logo?size=30&color=black&border=false&border_radius=0&scale=2). | Vendored PNG data URI in `frontend/src/assets/appleSignInLogo.ts`; generated from the documented Apple endpoint. Follow the [Sign in with Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple). |

Do not replace these with hand-drawn logos or alter protected marks. Recheck the upstream branding rules before changing provider button composition, colors, or label treatment.
