# Equipment recognition

On-device equipment recognition for iPhone.

## Layout

- `FieldCopilot/`: the iOS app. Open `FieldCopilot/FieldCopilot.xcodeproj` in Xcode.
  - `FieldCopilot/`: the reading engine (text, barcodes, the equipment database, model-number rules, serial dates).
  - `FieldCopilot/App/`: the screens and the scan flow.
  - `RuleTests/`: tests for the reading engine. Run `FieldCopilot/RuleTests/run.sh` on a Mac.
  - `Scripts/`: builds the equipment database the app ships with, and downloads the voice model.
  - `Kokoro/`: the voice model the app reads results aloud with. Not in git.
- `docs/`: plans and reviews.
  - `compliance.md`: licenses, Apple's rules, and laws the app has to meet, with open actions.
  - `3d-capture.md`: the deferred plan for 3D capture and AR previews.
- `training/`: scripts that train the Core ML models on a Mac. Not used yet.
  - `data/`: photos, one folder per equipment type. Not in git.
  - `models/`: trained `.mlmodel` files. Not in git.

## Rebuild the equipment database

The app looks up model numbers offline in `FieldCopilot/FieldCopilot/Equipment.sqlite` (about 29 MB, 215,000
listings). Each listing names its source:

- ENERGY STAR (data.energystar.gov): certified heat pumps and their indoor units, light commercial HVAC
  (residential-size central ACs and packaged units), furnaces, water heaters, boilers, geothermal heat pumps.
- DOE's Compliance Certification Database (regulations.doe.gov/certification-data): every central AC and heat
  pump, with the coils and air handlers it's certified with, plus every multi-split heat pump, furnace, boiler and
  water heater certified to federal standards, ENERGY STAR or not.
- California Energy Commission (solarequipment.energy.ca.gov): solar inverters, batteries, energy storage
  systems and PV modules.
- [California Energy Commission's archive](https://www.energy.ca.gov/files/archived-appliance-lists): models no
  longer sold in California, with the date each was first listed. Home central air conditioners, packaged units,
  furnaces and boilers from 1981 to 2023, central heat pumps from 2023, and water heaters from 2019 to 2023. About
  103,000 listings, half the database.

DOE and ENERGY STAR list only models sold today, so a model drops off when its maker stops selling it. Each
rebuild keeps the models in the current `Equipment.sqlite` that have dropped off, marked with when they were last
listed, and the app shows them as no longer sold. So the database grows into a history from Oct 29, 2026 on.
Rebuild on top of the committed file: deleting it first loses that history. California's archive covers most
older units, but not split heat pumps before 2023, water heaters before 2019, or models archived since 2024 (they
stay in California's live database for two years first). The lookup order is the database, then the model-number
rules, then Apple Intelligence for anything left. California's archive names whichever brands filed a model there,
so when a model-number rule also decodes the model, the app takes the rule's brands.

ENERGY STAR and the California Energy Commission are downloaded by the script. California's archive files (about
190 MB) are downloaded once into `~/Library/Caches/FieldCopilot/cec-archive`, since they don't change. DOE's lists
have no API, so download them first:

1. Open [DOE's certification database](https://www.regulations.doe.gov/certification-data/).
2. For each of these product groups, open it, leave the filters empty, and download it as CSV:
   - Air Conditioners and Heat Pumps - Central
   - Air Conditioners and Heat Pumps - Central Multi-Split
   - Furnaces (home boilers are in this one too)
   - Water Heaters
3. Put the four files in one folder, for example `~/Downloads/doe`. Keep the names DOE gives them.

Then run this with that folder (about 6 minutes) and rebuild the app:

```bash
swift FieldCopilot/Scripts/build_equipment_db.swift ~/Downloads/doe
```

DOE's central AC list names whoever certified each pairing, often a coil maker (ADP, Aspen, Mortex) pairing its
coil with another maker's outdoor unit. So outdoor units and indoor units from that list keep no brand; their
brand comes from the label, ENERGY STAR or the model-number rules.

## Check the model-number rules

After changing a rule in `FieldCopilot/FieldCopilot/ModelRules+*.swift` or rebuilding the database, run:

```bash
FieldCopilot/Scripts/check_model_rules.sh
```

It decodes every ENERGY STAR heat pump, furnace and water heater model number with the app's rules and
compares the type, AFUE, refrigerant, fuel, gallons and gas input with what ENERGY STAR lists, and fails
if any disagree. The agreement check in `RuleTests` does the same against every list in the equipment
database, DOE's and California's archive included, for type, brand and AFUE. It doesn't compare the archive's
brands, and `RuleTests/AgreementTests.swift` lists the families where the archive and the rules still disagree,
with why. ENERGY STAR doesn't list central air conditioners, coils, air handlers or discontinued
models; those rules rest on the manufacturer documents cited in each rules file and in
`RuleTests/SourcedModelTests.swift`, which checks model numbers printed in those documents.

California's archive corrected seven rules on Oct 30, 2026: Bryant's packaged units from before about 2008 (577B,
589A, 674A) were read as split systems, Trane's 4TCA and 4TCX packaged units as heat pumps, and Goodman's GKS9
furnaces as 93%+ AFUE (California certifies them at 92.1%). The other four matched other makers' equipment:
Reliance water heaters (6 50 MDV0 250) read as Bryant heat pumps, Allied Air's Magic-Pak (26HWC124A) as a Carrier
air conditioner, Armstrong's packaged units (PGE10124D050A) as American Water Heater electric heaters, and Smith
Cast Iron's steam boilers (GSX-88-CON) as State water heaters.

The rules added on Nov 5, 2026 for Nortek, Johnson Controls (York, Luxaire, Coleman, Guardian, Hitachi) and the
mini-split lines of Mitsubishi, Fujitsu, LG, Gree, Daikin, Carrier and ICP rest on the lists instead of manufacturer
documents: each takes the letter that splits every listed heat pump from every listed air conditioner (Mitsubishi's
MUZ and MUY), so the agreement check is their evidence. They're there to tell heat pumps from air conditioners
the lists don't carry (see `heatpumps` below).

The equipment database answers first, so the rules matter for what it lacks. `measure_accuracy.sh rules` shows
each rule's share. On Nov 5, 2026, with California's archive, no rule was retired:

- 64 of the 103 rules decode model numbers from manufacturer documents that no list carries. The archive has no
  split heat pumps before 2023, no water heaters before 2019, and nothing archived since 2024.
- 17 give listed models a brand or type their listing lacks. DOE's central AC list names no brand, and ENERGY
  STAR's indoor units have no type.
- The other 22 decode only models the lists carry (Lennox ML180 furnaces, Rheem Professional water heaters).
  They could go, but the app takes a rule's brand and type over the archive's: the archive names only the brands
  that filed a model in California (R4A442 only as Smart Comfort, though ICP sells it under ten), and marks some
  indoor furnaces as outdoor units. Retiring them would trade those for the archive's.

## Measure coverage and accuracy

The tests in `RuleTests` pass or fail. This reports numbers, from a fixed random seed, so two runs on the same
code and database agree and a change shows up as a real difference:

```bash
FieldCopilot/Scripts/measure_accuracy.sh
```

It runs four parts (about 4 minutes), or one at a time: `coverage` (how many listed models the model-number
rules also decode, by type and maker), `lookup` (database lookups on listed models read right, cut short, or
misread), `serials` (serial numbers and other label text mistaken for a model) and `synthetic [labels]`
(nameplates drawn from listed models, damaged four ways, read with Vision OCR and the rules).
`rules` lists what each model-number rule decodes that the lists don't carry, the evidence for keeping it.

`heatpumps [per maker]` (about 10 minutes, needs Apple Intelligence) checks heat pump or air conditioner for
listed split-system outdoor units read without their listing, as for units the database doesn't have, on a
nameplate that doesn't print "heat pump". With 40 of each per maker:

- Apple Intelligence calls nearly everything an air conditioner, so it gets 99% of the air conditioners right
  without telling them apart, and almost every heat pump the rules don't decode wrong.
- On Nov 2, 2026 the rules decoded 41% of the heat pumps, so the app called 58% of them air conditioners.
- With the rules added on Nov 5, they decode 68% (Trane 95%, Nortek 100%, Daikin and Johnson Controls 93%, ICP 83%,
  Rheem 80%, Carrier 68%, Lennox 48%; Gree's other brands and the long tail of mini-split makers 10–13%), and the
  app calls 32% air conditioners. The rules still never give the wrong type, and air conditioners stay at 99%.
- Since Nov 5, Apple Intelligence also copies the printed words that say which (HEAT PUMP, HSPF, COOLING ONLY…),
  and the app takes its heat pump or air conditioner only with those words on the label. Otherwise it shows
  "Air conditioner or heat pump" and says to look for HEAT PUMP or a reversing valve. Now no heat pump or air
  conditioner gets the wrong type: the rules type 68% of the heat pumps and 36% of the air conditioners, and the
  rest are shown as either. On the real photos, Apple Intelligence alone had typed three of the five heat pumps and
  air conditioners wrong; now it calls them all either, and the app still gets all 28 fields right.

To score real label photos, put them in a folder with a `truth.csv` of the right answers, then run
`FieldCopilot/Scripts/measure_accuracy.sh photos <folder>`:

```
file,brand,type,model,serial
carrier-ac.png,Carrier,airConditioner,24ACA336A300,1107E27968
```

It compares Apple Intelligence alone, the rules alone, and the app. Keep the photos out of git: `test-photos/`
is ignored for this.

## Get the voice model

The app reads results aloud with [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), an open voice model
(Apache-2.0) that runs on the phone, through [speech-swift](https://github.com/soniqo/speech-swift) (Apache-2.0).
The model is bundled in the app from `FieldCopilot/Kokoro`, so it works offline, but it's 88 MB and isn't in git.
Run this once, and again if the script's revision changes, then rebuild the app:

```bash
swift FieldCopilot/Scripts/fetch_voice.swift
```

Without the model, the app uses the phone's own voice.

## Train the equipment classifier

Put photos in `training/data/<type>/`, for example `training/data/inverter/`, then run:

```bash
swift training/train_classifier.swift
```
