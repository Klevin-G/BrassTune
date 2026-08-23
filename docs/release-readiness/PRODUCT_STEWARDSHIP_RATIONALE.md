# Product Stewardship Rationale
Project attribution: Kelvin Guo, Arya Salem.

This note records implementation rationale and release boundaries, not legal advice, proof of user impact, or a statement of current App Store configuration.

## Retention and account conversion

The product should make first-use purpose, optional account conversion, data location, export, and deletion understandable at the point of decision. Apple’s [onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding) supports explaining value without unnecessary friction, and its [button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons) supports clear, consistent actions. For BrassTune, that rationale supports keeping guest practice explicit and presenting account, export, and deletion choices plainly; it does not prove retention or completion outcomes.

Mobile-health studies and a habit-formation study are relevant only as adjacent behavioral evidence: [PubMed 37794916](https://pubmed.ncbi.nlm.nih.gov/37794916/), [PubMed 34637651](https://pubmed.ncbi.nlm.nih.gov/34637651/), and [the habit-formation study](https://doi.org/10.1002/ejsp.674). Applying their findings to brass practice is an inference, not a measured BrassTune result. Any retention, conversion, or engagement claim requires product-specific, consent-aware measurement and review.

## Accessibility and color

Accessible controls should expose a programmatic name, state, and action; color must not be the sole indicator. The implementation rationale is grounded in [WCAG 2.2 contrast minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum), [WCAG 2.2 target-size minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum), and Apple’s [VoiceOver evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria). These sources support contrast, sufficiently sized targets, and testable VoiceOver behavior. They do not make simulator automation or code inspection proof that every physical-device accessibility criterion is met.

## App Store developer name

**Source evidence.** Apple distinguishes the public App Store **developer name** from the legal membership name and from the App Store app name. When adding an account’s first app, an organization may choose a registered trade, DBA, or fictitious business name as its developer name; an individual cannot, and the developer name cannot be edited later: [Set your developer name](https://developer.apple.com/help/app-store-connect/create-an-app-record/set-your-developer-name). Apple says individual membership uses the legal personal name, while organization enrollment requires a legal entity: [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/). The App Store app name is a separate field: [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information). Apple also documents Account Holder-led individual-to-organization conversion, with founder/cofounder, D-U-N-S, supporting-document, and Apple Support steps: [Updating account information](https://developer.apple.com/help/account/membership/updating-your-account-information).

**Result and inference.** Because BrassTune is already published, ordinary App Information edits and individual-to-organization conversion do not themselves provide an edit field for the existing public developer name. Changing the individual account name or the app display name is insufficient. A likely route is direct Apple Developer Support guidance, or transfer to an eligible account whose already-fixed developer name is `BrassTune`, after Apple confirms the [transfer eligibility and impacts](https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer). This is an inference from Apple’s first-app and no-later-edit rules, not evidence that a support case, conversion, transfer, or developer-name change has occurred. It does not require the legal entity name itself to be `BrassTune`.

**2026-08-23 verified status.** Apple Developer reports the membership as **Enrolled as Individual**. The public [iTunes lookup for app 6795688588](https://itunes.apple.com/lookup?id=6795688588) returns `BrassTune` version `1.0`, `sellerName`/`artistName` `Arya Salem`, and release date `2026-08-18`. Therefore an individual account cannot choose `BrassTune` as its developer name and the existing public name cannot be edited through the ordinary UI. Apple Developer Support or an eligible organization-account transfer is required; transfer eligibility and any legal DBA/trade-name decision remain human/Apple determinations.

## Next steps and limits

1. Have the Account Holder/legal owner confirm the desired public developer name, legal-entity path, and whether Apple Support or transfer is appropriate.
2. Preserve the existing account, privacy, and accessibility evidence separately from any future organization change.
3. Run the physical-device prompt in [IPHONE_AUTOMATION_PROMPT.md](IPHONE_AUTOMATION_PROMPT.md) against the exact submission candidate; do not substitute simulator or automated evidence for physical observations.

This document does not establish native/physical completion, a deployment, or App Store submission completion.
