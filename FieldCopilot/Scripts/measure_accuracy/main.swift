// Measures how far the app's reading engine reaches and how often it's wrong, in seven parts:
//   coverage   how many listed models the model-number rules also decode, by type and maker: the rules
//              are what's left for older units the lists no longer carry
//   lookup     database lookups on listed models read right, cut short, or misread
//   serials    serial numbers and other label text mistaken for a listed model
//   synthetic  nameplates drawn from listed models in five layouts, damaged four ways, read with Vision OCR
//              and the rules
//   rules      what each model-number rule decodes that the lists don't carry, from the model numbers in
//              RuleTests: evidence for keeping or retiring a rule
//   heatpumps  heat pump or air conditioner for listed outdoor units read without their listing, as for the
//              ones the database doesn't have: the rules, then Apple Intelligence on a nameplate that doesn't say
//   photos     real label photos against the right answers in their folder's truth.csv, read by Apple
//              Intelligence alone, the rules alone, and the app (rules first, then Apple Intelligence)
// Samples come from a fixed seed, so two runs on the same database give the same numbers.
//
// Run from the repository root after changing the rules or the database:
//   FieldCopilot/Scripts/measure_accuracy.sh                     coverage, lookup, serials and synthetic
//   FieldCopilot/Scripts/measure_accuracy.sh synthetic 100       100 labels instead of 250
//   FieldCopilot/Scripts/measure_accuracy.sh heatpumps 40        40 of each type per maker (needs Apple Intelligence)
//   FieldCopilot/Scripts/measure_accuracy.sh photos test-photos  a folder of photos with truth.csv

import Foundation

let root = URL(filePath: CommandLine.arguments[1])
EquipmentDatabase.fileURL = root.appending(path: "FieldCopilot/Equipment.sqlite")
let arguments = Array(CommandLine.arguments.dropFirst(2))

switch arguments.first {
case "coverage": measureCoverage()
case "lookup": measureLookups()
case "serials": measureFalseMatches()
case "rules": measureRules(root: root)
case "heatpumps": try await measureHeatPumps(perMaker: arguments.dropFirst().first.flatMap { Int($0) } ?? 40)
case "synthetic": try await measureSynthetic(labels: arguments.dropFirst().first.flatMap { Int($0) } ?? 250)
case "photos":
    guard let folder = arguments.dropFirst().first else { fatalError("Which folder? measure_accuracy.sh photos <folder>") }
    try await measurePhotos(in: URL(filePath: folder, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath + "/")))
case nil:
    measureCoverage()
    measureLookups()
    measureFalseMatches()
    try await measureSynthetic(labels: 250)
case let other?:
    fatalError("No part called \(other). Try coverage, lookup, serials, synthetic, rules, heatpumps or photos.")
}
