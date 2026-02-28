//
//  ReadingPlanDay.swift
//  ScriptureScribe
//
//  One day of the Bible-in-a-Year reading plan.
//  Loaded from BibleReadingPlan.json (365 entries covering all 1,189 chapters).
//

import Foundation

struct ReadingPlanDay: Codable {
    let day: Int              // 1-365
    let label: String         // e.g. "Genesis 1-3"
    let chapters: [String]    // e.g. ["GEN.1", "GEN.2", "GEN.3"]
}
