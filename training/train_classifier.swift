// Trains the equipment classifier with Create ML.
//
// Put photos in one folder per class:
//   training/data/inverter/*.jpg
//   training/data/water_heater/*.jpg
//   ...
//
// Run:
//   swift training/train_classifier.swift
//
// Holds out a random 20% of the photos to check accuracy, then writes
// training/models/EquipmentClassifier.mlmodel for the iOS app.

import CreateML
import Foundation

let here = URL(filePath: #filePath).deletingLastPathComponent()
let dataFolder = here.appending(path: "data")
let modelsFolder = here.appending(path: "models")

let parameters = MLImageClassifier.ModelParameters(
    validation: .split(strategy: .fixed(ratio: 0.2, seed: 7)),
    augmentation: []
)
let classifier = try MLImageClassifier(trainingData: .labeledDirectories(at: dataFolder), parameters: parameters)

print(String(format: "Training accuracy:   %.1f%%", (1 - classifier.trainingMetrics.classificationError) * 100))
if let error = classifier.validationMetrics.error {
    print("Validation didn't run: \(error)")
} else {
    print(String(format: "Validation accuracy: %.1f%%", (1 - classifier.validationMetrics.classificationError) * 100))
}

try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
try classifier.write(to: modelsFolder.appending(path: "EquipmentClassifier.mlmodel"))
print("Saved training/models/EquipmentClassifier.mlmodel")
