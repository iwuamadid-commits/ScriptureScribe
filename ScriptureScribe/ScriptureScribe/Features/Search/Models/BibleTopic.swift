//
//  BibleTopic.swift
//  ScriptureScribe
//
//  Predefined Bible topics for the one-tap topic search feature.
//  Each topic has a display name, an SF Symbol icon, and the keyword
//  that gets sent to the API.Bible search endpoint.
//

import Foundation

struct BibleTopic: Identifiable {
    let id      = UUID()
    let name:    String
    let icon:    String    // SF Symbol name
    let keyword: String    // query sent to API.Bible search
}

enum BibleTopics {
    static let all: [BibleTopic] = [
        .init(name: "Love",        icon: "heart.fill",               keyword: "love"),
        .init(name: "Faith",       icon: "sparkles",                 keyword: "faith"),
        .init(name: "Hope",        icon: "sun.horizon.fill",         keyword: "hope"),
        .init(name: "Peace",       icon: "leaf.fill",                keyword: "peace"),
        .init(name: "Strength",    icon: "bolt.heart.fill",          keyword: "strength"),
        .init(name: "Forgiveness", icon: "hands.and.sparkles.fill",  keyword: "forgive"),
        .init(name: "Fear Not",    icon: "shield.fill",              keyword: "fear not"),
        .init(name: "Prayer",      icon: "hands.sparkles.fill",      keyword: "prayer"),
        .init(name: "Wisdom",      icon: "lightbulb.fill",           keyword: "wisdom"),
        .init(name: "Joy",         icon: "face.smiling.fill",        keyword: "joy"),
        .init(name: "Grief",       icon: "cloud.rain.fill",          keyword: "sorrow"),
        .init(name: "Anxiety",     icon: "waveform.path.ecg",        keyword: "anxious"),
        .init(name: "Salvation",   icon: "cross.fill",               keyword: "salvation"),
        .init(name: "Grace",       icon: "gift.fill",                keyword: "grace"),
        .init(name: "Trust",       icon: "figure.stand",             keyword: "trust God"),
        .init(name: "Healing",     icon: "bandage.fill",             keyword: "heal"),
        .init(name: "Praise",      icon: "music.note",               keyword: "praise"),
        .init(name: "Humility",    icon: "arrow.down.circle.fill",   keyword: "humble"),
        .init(name: "Patience",    icon: "hourglass",                keyword: "patient"),
        .init(name: "Obedience",   icon: "checkmark.circle.fill",    keyword: "obey"),
    ]
}
