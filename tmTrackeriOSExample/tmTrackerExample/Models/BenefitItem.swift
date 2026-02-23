//
//  BenefitItem.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import Foundation

struct BenefitItem: Identifiable, Codable, Equatable {
    let id: Int
    let thumbnail: String
    let title: String
    let description: String
    let labels: [String]
    let dateLabel: String
}
