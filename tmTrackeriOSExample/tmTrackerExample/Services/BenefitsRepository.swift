//
//  BenefitsRepository.swift
//  tmTrackerExample
//
//  Created by Alban Elshani on 12.2.26.
//

import Foundation

final class BenefitsRepository {
    private static let benefitsLimit = 20
    private static let benefitsApiBaseUrl = "https://api.themiracle.io"
    /// Benefits API base URL. Set via Settings tab (UserDefaults), env BENEFITS_API_BASE_URL, or Info.plist.
    private static var benefitsApiDevUrl: String {
        AppConfig.string(key: "BENEFITS_API_BASE_URL", default: "")
    }

    /// API key. REQUIRED: Set via Settings tab, env BENEFITS_API_KEY, or Info.plist. Trims quotes/whitespace.
    /// No default - must be configured to avoid exposing secrets in code.
    private static var benefitsApiKey: String {
        let raw = AppConfig.requiredString(key: "BENEFITS_API_KEY")
        return raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }
    
    func fetchBenefits() async throws -> [BenefitItem] {
        let baseUrl = Self.benefitsApiDevUrl.isEmpty ? Self.benefitsApiBaseUrl : Self.benefitsApiDevUrl
        let urlString = "\(baseUrl)/api/v1/benefits?limit=\(Self.benefitsLimit)&sortBy=actionDate&sortDirection=DESC"
        
        #if DEBUG
        print("[BenefitsRepository] Fetching benefits from \(baseUrl) with apiKeyLength=\(Self.benefitsApiKey.count)")
        #endif
        
        guard let url = URL(string: urlString) else {
            throw BenefitsError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Always set X-API-KEY header (matching Android behavior)
        request.setValue(Self.benefitsApiKey, forHTTPHeaderField: "X-API-KEY")
        
        #if DEBUG
        print("[BenefitsRepository] Request URL: \(urlString)")
        print("[BenefitsRepository] X-API-KEY header: \(Self.benefitsApiKey.prefix(8))...")
        #endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BenefitsError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        return try parseBenefits(data: data)
    }
    
    private func parseBenefits(data: Data) throws -> [BenefitItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw BenefitsError.invalidJSON
        }
        
        let items: [[String: Any]]
        
        if let array = json as? [[String: Any]] {
            items = array
        } else if let dict = json as? [String: Any] {
            if let hydraMember = dict["hydra:member"] as? [[String: Any]] {
                items = hydraMember
            } else if let itemsArray = dict["items"] as? [[String: Any]] {
                items = itemsArray
            } else if let dataArray = dict["data"] as? [[String: Any]] {
                items = dataArray
            } else {
                return []
            }
        } else {
            return []
        }
        
        return items.compactMap { mapBenefit($0) }
    }
    
    private func mapBenefit(_ item: [String: Any]) -> BenefitItem? {
        let id: Int = {
            if let idValue = item["id"] as? Int { return idValue }
            if let idValue = item["id"] as? NSNumber { return idValue.intValue }
            if let idValue = item["id"] as? String, let intValue = Int(idValue) { return intValue }
            return 0
        }()
        
        let title = stringOrFallback(
            item["longTitle"] as? String,
            item["shortTitle"] as? String,
            item["title"] as? String,
            fallback: "Untitled benefit"
        )
        
        let description = stringOrFallback(
            item["shortDescription"] as? String,
            item["longDescription"] as? String,
            nil,
            fallback: "No description yet."
        )
        
        let labels = extractLabels(item)
        let dateLabel = formatDateLabel(from: item)
        let thumbnail = stringOrFallback(
            item["thumbnail"] as? String,
            item["thumbnailUrl"] as? String,
            item["image"] as? String,
            fallback: ""
        )
        
        return BenefitItem(
            id: id,
            thumbnail: thumbnail,
            title: title,
            description: description,
            labels: labels,
            dateLabel: dateLabel
        )
    }
    
    private func stringOrFallback(_ primary: String?, _ secondary: String?, _ tertiary: String?, fallback: String) -> String {
        for value in [primary, secondary, tertiary] {
            if let val = value, !val.trimmingCharacters(in: .whitespaces).isEmpty {
                return val.trimmingCharacters(in: .whitespaces)
            }
        }
        return fallback
    }
    
    private func extractLabels(_ item: [String: Any]) -> [String] {
        var labels: [String] = []
        
        if let type = item["type"] as? [String: Any],
           let typeName = type["name"] as? String,
           !typeName.isEmpty {
            labels.append(typeName)
        }
        
        if let companyName = item["companyName"] as? String, !companyName.isEmpty {
            labels.append(companyName)
        }
        
        if let location = item["location"] as? String, !location.isEmpty {
            labels.append(location)
        }
        
        if let tags = item["tags"] as? String, !tags.isEmpty {
            let tagList = tags.components(separatedBy: CharacterSet(charactersIn: ";,|"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            labels.append(contentsOf: tagList)
        }
        
        return normalizeLabels(labels)
    }
    
    private func normalizeLabels(_ labels: [String]) -> [String] {
        var deduped: [String] = []
        var seen = Set<String>()
        
        for label in labels {
            let trimmed = label.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.isEmpty || trimmed == "null" || trimmed == "undefined" {
                continue
            }
            if seen.contains(trimmed) {
                continue
            }
            seen.insert(trimmed)
            deduped.append(label.trimmingCharacters(in: .whitespaces))
        }
        
        while deduped.count < 2 {
            deduped.append(deduped.isEmpty ? "Benefit" : "New")
        }
        
        return Array(deduped.prefix(2))
    }
    
    private func formatDateLabel(from item: [String: Any]) -> String {
        let dateValue = item["validTo"] as? String
            ?? item["actionDate"] as? String
            ?? item["dateCreated"] as? String
        
        guard let dateString = dateValue, !dateString.isEmpty else {
            return "No expiry"
        }
        
        // Try ISO8601 with fractional seconds first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateString)
        
        // Try ISO8601 without fractional seconds
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }
        
        // Try simple date format as fallback
        if date == nil {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            date = dateFormatter.date(from: dateString)
        }
        
        guard let finalDate = date else {
            return "No expiry"
        }
        
        let calendar = Calendar.current
        let day = calendar.component(.day, from: finalDate)
        let month = calendar.component(.month, from: finalDate)
        let year = calendar.component(.year, from: finalDate)
        
        let monthName = calendar.monthSymbols[month - 1]
        let ordinalSuffix = ordinalSuffix(for: day)
        
        return "\(day)\(ordinalSuffix) \(monthName) \(year)"
    }
    
    private func ordinalSuffix(for day: Int) -> String {
        if (11...13).contains(day) {
            return "th"
        }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

enum BenefitsError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidJSON:
            return "Invalid JSON response"
        }
    }
}
