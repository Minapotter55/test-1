import Foundation
import SwiftData

@Model
final class Deal {
    var title: String = ""
    var value: Double = 0
    var stageRaw: String = DealStage.new.rawValue
    var probability: Int = 10
    var expectedCloseDate: Date?
    var notes: String = ""
    var createdAt: Date = Date()
    var closedAt: Date?
    var customer: Customer?

    init(title: String, value: Double, stage: DealStage = .new) {
        self.title = title
        self.value = value
        self.stageRaw = stage.rawValue
        self.probability = stage.defaultProbability
        self.createdAt = Date()
    }

    var stage: DealStage {
        get { DealStage(rawValue: stageRaw) ?? .new }
        set {
            stageRaw = newValue.rawValue
            if newValue.isOpen {
                closedAt = nil
            } else if closedAt == nil {
                closedAt = Date()
            }
        }
    }

    var weightedValue: Double { value * Double(probability) / 100 }
}
