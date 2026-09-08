import Foundation

enum SharedInterestIdentity {
    static func recordName(for name: String) -> String {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var slug = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.append(Character(scalar))
            } else if scalar == " " || scalar == "-" || scalar == "_" {
                slug.append("-")
            }
        }
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty {
            slug = folded.utf8.map { String(format: "%02x", $0) }.joined()
        }
        return "interest." + String(slug.prefix(80))
    }
}

enum SharedInterestMergeLogic {
    static func harvested(from profiles: [UserProfile]) -> [CustomInterestRecord] {
        var seen = Set<String>()
        var records: [CustomInterestRecord] = []
        for profile in profiles {
            if LocalLLMIdentity.isLLM(profile.deviceID) { continue }
            for interest in Set(profile.interests) where interest.isCustom {
                let key = interest.rawValue.lowercased()
                guard seen.insert(key).inserted else { continue }
                records.append(
                    CustomInterestRecord(name: interest.rawValue, emoji: interest.emoji)
                )
            }
        }
        return records
    }

    static func merging(
        _ incoming: [CustomInterestRecord],
        into existing: [CustomInterestRecord]
    ) -> [CustomInterestRecord] {
        var byKey: [String: CustomInterestRecord] = [:]
        for item in existing {
            byKey[item.name.lowercased()] = item
        }
        for item in incoming {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if Interest.builtInCases.contains(where: {
                $0.rawValue.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }) {
                continue
            }
            let key = trimmed.lowercased()
            let incomingRecord = CustomInterestRecord(name: trimmed, emoji: item.emoji)
            if let current = byKey[key] {
                if current.emoji == "✨", incomingRecord.emoji != "✨" {
                    byKey[key] = CustomInterestRecord(name: current.name, emoji: incomingRecord.emoji)
                }
            } else {
                byKey[key] = incomingRecord
            }
        }
        return byKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
