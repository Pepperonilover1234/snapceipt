// Trains Snapceipt's item-category text classifier with Create ML.
//
// Run on a Mac from the Keptang project folder (compile first; the interpreter can't load Create ML):
//     swiftc -O Tools/TrainItemCategory.swift -o /tmp/train-item-category && /tmp/train-item-category
//
// It reads Tools/item-categories.json (category → example item names, Thai and English)
// and writes Keptang/Intelligence/ItemCategory.mlmodel, which Xcode compiles into the app.

import CreateML
import Foundation

let input = URL(fileURLWithPath: "Tools/item-categories.json")
let output = URL(fileURLWithPath: "Keptang/Intelligence/ItemCategory.mlmodel")

let examples = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: input))
// Lower-case English names so "Milk" and "milk" are the same example; the app does the same before predicting.
let training = examples.mapValues { names in names.map { $0.lowercased() } }

let classifier = try MLTextClassifier(trainingData: training)
let accuracy = (1 - classifier.trainingMetrics.classificationError) * 100
print("Trained on \(training.values.map(\.count).reduce(0, +)) items, training accuracy \(String(format: "%.1f", accuracy))%")

let metadata = MLModelMetadata(
    author: "Snapceipt",
    shortDescription: "Sorts receipt item names (Thai and English) into spending categories.",
    version: "1.0"
)
try classifier.write(to: output, metadata: metadata)
print("Wrote \(output.path)")
