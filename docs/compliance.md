# Compliance review

A check of Field Copilot against licenses, Apple's rules, and laws that apply to what it does, as of
October 27, 2026. **This is an engineering review, not legal advice.** Items marked *Legal* need
legal or compliance to confirm. Items marked *App* are changes to make in the app.

## Summary

| # | Item | Status | Owner |
|---|---|---|---|
| 1 | Third-party license notices aren't shown anywhere in the app | Action needed before release | App |
| 2 | No privacy policy | Required before App Store release | Legal and App |
| 3 | No app privacy manifest (`PrivacyInfo.xcprivacy`) | Add, then check Xcode's privacy report | App |
| 4 | Voice notes in states that require everyone's consent to record | Add a notice; confirm | App and Legal |
| 5 | Shared summaries drop where the age and ENERGY STAR status came from | Fix to avoid misleading homeowners | App |
| 6 | Use of the ENERGY STAR name | Confirm rules for a non-partner app | Legal |
| 7 | Encryption export declaration | Confirm the answer | Legal |
| 8 | Speech recognition permission | Confirm on a real iPhone | App |
| 9 | Customer photos and location are saved in the contractor's device backups | Decide whether that's acceptable | Legal |
| 10 | Deferred 3D capture: model licenses, consent for uploads | Resolve before restarting | Legal |
| 11 | Future selling and financing features | Checklist for later | Legal |

## What the app does with data today

Everything stays on the phone. The app makes no network requests of its own.

- **Photos of equipment labels:** saved in the app's storage with the text read from them. Taken at
  customers' homes, so they can show the property.
- **Location:** with permission, each photo taken in the app is stamped with where it was taken.
  Location is optional, and the camera works without it.
- **Voice notes:** speech is turned into text on the phone by Apple's speech framework. Only the text is
  kept; the audio isn't saved.
- **Apple Intelligence:** reads label text on the phone, when the rules leave gaps.
- **Read aloud:** the Kokoro voice model runs on the phone and is bundled in the app.
- **Sharing:** the contractor can share a text summary through the share sheet. It includes the
  location coordinates and voice notes. Tapping the location opens Apple Maps with the coordinates.
- **Backups:** scans live in Application Support, so they're included in the contractor's iCloud or
  computer backups.

## 1. Third-party software and models in the app

These are compiled into the app or shipped in its bundle:

| Component | Used for | License |
|---|---|---|
| speech-swift (`KokoroTTS`, `AudioCommon`) | Kokoro voice | Apache-2.0 |
| Kokoro-82M weights, 8-bit Core ML conversion | Kokoro voice | Apache-2.0 |
| Misaki dictionaries and pronunciation models | Kokoro voice | Apache-2.0 |
| swift-transformers (`Hub`), swift-huggingface, swift-jinja | Pulled in by speech-swift | Apache-2.0 |
| swift-crypto | Pulled in by swift-huggingface | Apache-2.0, has a `NOTICE.txt` |
| swift-collections | Pulled in by speech-swift | Apache-2.0 |
| eventsource, yyjson | Pulled in by swift-huggingface | MIT |
| ENERGY STAR certified-product lists | Offline lookups | U.S. government data from data.energystar.gov |
| DOE Compliance Certification Database exports | Offline lookups | U.S. government data from regulations.doe.gov |
| California Energy Commission solar equipment lists | Offline lookups | California state data from solarequipment.energy.ca.gov |
| California Energy Commission archive of appliance lists | Offline lookups | California state data from energy.ca.gov/files/archived-appliance-lists |

No GPL code. Both Apache-2.0 and MIT allow commercial use, but both require including the license
text with copies of the software, and Apache-2.0 also requires including any `NOTICE` file contents.

**Action (App):** add an acknowledgements screen, or a Settings bundle page, listing each component
with its license and swift-crypto's `NOTICE.txt`. Regenerate it whenever dependencies change.

## 2. Apple's rules

- **Privacy policy (guideline 5.1.1(i)).** "All apps must include a link to their privacy policy" in
  App Store Connect and in the app, even when no data leaves the phone. **Action:** write one. It
  should cover photos, location, voice notes, what's shared and with whom (only by the contractor,
  through the share sheet), and how to delete data.
- **App privacy details in App Store Connect.** Today "Data Not Collected" looks accurate, because
  nothing is sent anywhere. This changes the moment any upload or sync is added.
- **Purpose strings.** Camera, location, and microphone each have one, and location is optional, as
  guideline 5.1.2(i) requires ("may not require users to enable system functionalities (such as …
  location services …)").
- **Privacy manifest.** The app's own code uses none of Apple's "required reason" APIs.
  speech-swift and swift-huggingface call `FileManager.attributesOfItem` only to read file sizes, in
  download code the app never runs. swift-crypto ships its own manifests. **Action (App):** add a
  `PrivacyInfo.xcprivacy` declaring no tracking and no collected data, then archive and check Xcode's
  privacy report.
- **Speech recognition permission.** The app asks only for the microphone. Apple's newer speech API
  may also need `NSSpeechRecognitionUsageDescription`. **Action (App):** confirm on a real iPhone.
- **Apple Intelligence acceptable use.** Reading equipment labels is fine. The terms prohibit
  "decisions without human supervision that have a material impact on individual rights, in high-risk
  domains, including in employment, medical, legal, or finance". If financing features are added,
  the on-device model must not make or drive credit decisions.
- **Export compliance.** The app makes no network calls. swift-crypto, which includes an encryption
  library, is compiled in through swift-huggingface's download code, which the app doesn't use.
  **Legal:** confirm the answer to App Store Connect's encryption question
  (`ITSAppUsesNonExemptEncryption`).

## 3. Voice notes and recording laws

Some states require **everyone's consent** to record a conversation. Sources list California,
Delaware, Florida, Illinois, Maryland, Massachusetts, Montana, Nevada, New Hampshire, Pennsylvania,
and Washington. Connecticut, Michigan, and Oregon are treated differently by different sources, and
some states apply this only to private or confidential conversations.

Voice notes don't save audio, but turning a conversation into text likely still counts as recording
it. A contractor talking near a homeowner could capture the homeowner's words.

- **Action (App):** on the first voice note, show a short notice: voice notes are for the
  contractor's own observations; don't record anyone without their agreement.
- **Legal:** confirm whether that's enough, and whether the app should stop recording when another
  voice is detected.

## 4. Photos and location of customers' homes

Photos of a home with location coordinates are personal information about the homeowner once linked
to an address. Today they stay on the contractor's phone, so nobody else has them.

- **Legal:** if scans are ever uploaded or synced to a server, state privacy laws apply. Under
  California's CPRA, precise geolocation is "sensitive personal information". That would require a
  notice at collection, retention limits, and deletion rights.
- **Legal:** scans are included in the contractor's device backups. Decide whether customer photos
  and locations should be excluded from backup. In the app, that's a one-line change.

## 5. Accuracy of what's shared with homeowners

On screen, every value shows where it came from, for example "From the serial: week 11 of 2007" or
the date of the ENERGY STAR list. The shared text summary drops those notes, so a homeowner sees
"Made: Mar 2007 (19 years old)" or "ENERGY STAR: Not listed" as plain facts.

Ages decoded from serials can be wrong, and the ENERGY STAR list is a snapshot. If these feed a sales
conversation, unqualified claims are a risk under the FTC Act's ban on deceptive practices and state
equivalents.

**Action (App):** include the source in the shared summary: "Made: Mar 2007, from the serial number
(19 years old)", and "ENERGY STAR: Not listed as of <list date>".

## 6. The ENERGY STAR name

The app shows "ENERGY STAR certified" with a green check seal icon, which is a system symbol, not the
ENERGY STAR logo. It also shows "Not listed" for certifiable types missing from the list. EPA's
guidelines say:

- The name "should always appear in all capital letters and as two words". The app does this.
- "The registration symbol ® must be used the first time the words 'ENERGY STAR' appear". The app
  doesn't do this.
- The name and marks "may never be used in any manner that would imply EPA or ENERGY STAR endorsement",
  and "may never be associated with products … that are *not* ENERGY STAR certified".
- "In most cases, organizations must sign a Partnership Agreement" to use the marks.

**Legal:** confirm with the ENERGY STAR Help Desk whether these rules apply to a non-partner app
stating certification facts, whether "Not listed" is acceptable wording, and whether to add ® on
first use.

## Deferred 3D capture

Before restarting [3D capture](3d-capture.md):

- **Model licenses.** Avoid these:
  - Depth Anything 3 Giant and Large: CC BY-NC 4.0, non-commercial. MV-SAM3D uses one by default.
  - Hunyuan3D: not licensed in the EU, UK, or South Korea, and a company whose products had more than
    1 million monthly active users at release must ask Tencent.
  - Stable Fast 3D: free only under $1M revenue.

  Have legal review the SAM License (trade-control terms; gated weights). TRELLIS, TRELLIS.2, and
  TripoSR are MIT.
- **Uploads to an AI service.** Guideline 5.1.2(i) now says: "You must clearly disclose where personal
  data will be shared with third parties, including with third-party AI, and obtain explicit
  permission before doing so." A self-hosted server still needs a privacy notice and consent
  for customer photos.
- **Manufacturer 3D files.** BIM and Revit files are usually licensed for building design. Get
  permission before showing them in the app.
- **Training data.** Using field captures of customers' homes to train models needs notice, consent,
  and a retention policy.

## Future selling and financing features

Not built, and not reviewed in depth. This is a starting checklist for a compliance review.

- **FTC Cooling-Off Rule (16 CFR 429).** Covers sales of $25 or more made at the buyer's home, and $130
  or more at other temporary locations. Buyers get 3 business days to cancel, with written and oral
  notice. Exclusions include bona fide emergency repairs the buyer requests (with a signed handwritten
  waiver) and buyer-requested repairs, unless other goods are also sold.
- State home-solicitation and home-improvement contractor laws (licensing, contract contents).
- If financing is offered: Truth in Lending (Regulation Z) disclosures and advertising rules, Equal
  Credit Opportunity (Regulation B), the FTC Holder Rule, the Fair Credit Reporting Act if credit is
  pulled, the Gramm-Leach-Bliley Safeguards Rule, and UDAAP.
- Any savings or efficiency claims shown to homeowners must be substantiated.

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (5.1.1, 5.1.2,
  2.5.2), and [coverage of the 5.1.2(i) AI update](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai)
- [Foundation Models acceptable use requirements](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework/)
- [ENERGY STAR logo and name use](https://www.energystar.gov/logouse)
- [16 CFR 429.0](https://www.law.cornell.edu/cfr/text/16/429.0) and the
  [FTC rule summary](https://www.ftc.gov/legal-library/browse/rules/cooling-period-sales-made-home-or-other-locations)
- All-party consent states: [Oxford University Press summary](https://learninglink.oup.com/access/content/bender12e-student-resources/bender12e-states-that-require-consent-of-all-parties-for-taping),
  [2026 state-by-state guide](https://scribbl.co/post/do-you-have-to-tell-people-youre-recording)
  (secondary sources; confirm against each statute)
- Licenses: each package's repository and model card, checked October 27, 2026.
