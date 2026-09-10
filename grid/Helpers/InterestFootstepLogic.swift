import Foundation
import CoreLocation

/// Public per-interest walking trail. Each device refresh appends a ping; older pings render dimmer.
enum InterestFootstepLogic {
    static let cellSizeDegrees = 0.0008
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    static let sameCellMinInterval: TimeInterval = 0
    static let maxStoredPings = 400
    static let minRadius: CLLocationDistance = 8
    static let extraRadius: CLLocationDistance = 6
    static let minOpacity = 0.2
    static let extraOpacity = 0.72
    static let redHotVisitCount = 8

    struct Sample: Equatable, Codable {
        let id: String
        let interest: String
        let latitude: Double
        let longitude: Double
        let visitCount: Int
        let timestamp: Date
        let deviceID: String
        let userID: String
        let cellKey: String

        init(
            id: String = UUID().uuidString,
            interest: String,
            latitude: Double,
            longitude: Double,
            visitCount: Int,
            timestamp: Date,
            deviceID: String,
            userID: String,
            cellKey: String
        ) {
            self.id = id
            self.interest = interest
            self.latitude = latitude
            self.longitude = longitude
            self.visitCount = visitCount
            self.timestamp = timestamp
            self.deviceID = deviceID
            self.userID = userID
            self.cellKey = cellKey
        }
    }

    struct LastWrite: Equatable {
        let cellKey: String
        let timestamp: Date
    }

    struct HeatBlob: Identifiable, Equatable {
        let id: String
        let latitude: Double
        let longitude: Double
        let visitCount: Int
        let timestamp: Date
        let radius: CLLocationDistance
        let opacity: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    static func heatmapInterest(from tab: GridPeopleTab) -> String? {
        guard case .interest(let raw) = tab else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Heatmaps are public to everyone on that interest page, including hidden accounts.
    static func canViewHeatmap(tab: GridPeopleTab, isDiscoverable: Bool) -> Bool {
        _ = isDiscoverable
        return heatmapInterest(from: tab) != nil
    }

    static func recordableInterests(from profile: UserProfile, viewing: String? = nil) -> [Interest] {
        var seen = Set<String>()
        var interests = profile.interests.filter { interest in
            let key = interest.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else { return false }
            return seen.insert(key.lowercased()).inserted
        }
        if let viewing = viewing?.trimmingCharacters(in: .whitespacesAndNewlines),
           viewing.isEmpty == false,
           seen.insert(viewing.lowercased()).inserted {
            interests.append(Interest(rawValue: viewing))
        }
        return interests
    }

    /// Hidden accounts still leave heatmap pings; they just do not show as a person pin.
    static func shouldContribute(
        profile: UserProfile,
        location: CLLocation,
        viewingInterest: String? = nil
    ) -> Bool {
        guard GridPresenceLogic.isLeftoverDebugPeer(profile) == false else { return false }
        guard LocalLLMIdentity.isLLM(profile.deviceID) == false else { return false }
        let coordinate = location.coordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return false }
        return recordableInterests(from: profile, viewing: viewingInterest).isEmpty == false
    }

    static func shouldTrackWalks(
        isDiscoverable: Bool,
        interests: [Interest],
        authorizationStatus: CLAuthorizationStatus
    ) -> Bool {
        _ = isDiscoverable
        guard interests.contains(where: { $0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            return false
        }
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    static func shouldWrite(cellKey: String, last: LastWrite?, now: Date) -> Bool {
        _ = (cellKey, last, now)
        return true
    }

    static func quantized(_ value: Double) -> Double {
        (value / cellSizeDegrees).rounded() * cellSizeDegrees
    }

    static func cellKey(latitude: Double, longitude: Double) -> String {
        let latMilli = Int((quantized(latitude) * 10_000).rounded())
        let lonMilli = Int((quantized(longitude) * 10_000).rounded())
        return "\(latMilli)x\(lonMilli)"
    }

    static func coordinate(fromCellKey key: String) -> (latitude: Double, longitude: Double)? {
        let parts = key.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latMilli = Int(parts[0]),
              let lonMilli = Int(parts[1]) else {
            return nil
        }
        return (Double(latMilli) / 10_000.0, Double(lonMilli) / 10_000.0)
    }

    static func slug(_ raw: String, prefix: Int) -> String {
        let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var slug = ""
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.append(Character(scalar))
            } else if scalar == " " || scalar == "-" || scalar == "_" || scalar == "." {
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
        return String(slug.prefix(prefix))
    }

    static func recordName(interest: String, pingID: String) -> String {
        "if.\(slug(interest, prefix: 40)).\(slug(pingID, prefix: 48))"
    }

    static func sample(
        interest: String,
        location: CLLocation,
        deviceID: String,
        userID: String,
        visitCount: Int = 1,
        timestamp: Date = Date(),
        pingID: String = UUID().uuidString
    ) -> Sample {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        return Sample(
            id: recordName(interest: interest, pingID: pingID),
            interest: interest,
            latitude: latitude,
            longitude: longitude,
            visitCount: max(visitCount, 1),
            timestamp: timestamp,
            deviceID: deviceID,
            userID: userID,
            cellKey: cellKey(latitude: latitude, longitude: longitude)
        )
    }

    static func matching(_ samples: [Sample], interest: String) -> [Sample] {
        samples.filter {
            $0.interest.compare(interest, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Union by id, newest copy wins, drop anything older than a week.
    static func merging(_ samples: [Sample], now: Date = Date()) -> [Sample] {
        var seen = Set<String>()
        var merged: [Sample] = []
        for sample in samples.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard now.timeIntervalSince(sample.timestamp) <= maxAge else { continue }
            guard seen.insert(sample.id).inserted else { continue }
            merged.append(sample)
        }
        if merged.count <= maxStoredPings {
            return merged
        }
        return Array(merged.sorted { $0.timestamp > $1.timestamp }.prefix(maxStoredPings))
    }

    static func absorbing(_ sample: Sample, into samples: [Sample], now: Date = Date()) -> [Sample] {
        merging(samples + [sample], now: now)
    }

    /// Rank among currently visible pings: oldest = 0, newest = 1.
    static func recency(indexFromOldest: Int, count: Int) -> Double {
        guard count > 1 else { return 1 }
        return Double(indexFromOldest) / Double(count - 1)
    }

    /// Nudge stacked same-spot refreshes a few meters so each circle is visible beside the blue dot.
    static func displayOffset(for id: String) -> (latitude: Double, longitude: Double) {
        var hasher = Hasher()
        hasher.combine(id)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        let angle = Double(hash % 360) * .pi / 180
        let meters = 12.0 + Double(hash % 18)
        return (meters * cos(angle) / 111_320.0, meters * sin(angle) / 111_320.0)
    }

    static func pingBlob(
        at location: CLLocation,
        id: String,
        timestamp: Date,
        recency: Double,
        visitCount: Int = 1
    ) -> HeatBlob {
        let offset = displayOffset(for: id)
        let heat = min(1, max(0, recency))
        return HeatBlob(
            id: id,
            latitude: location.coordinate.latitude + offset.latitude,
            longitude: location.coordinate.longitude + offset.longitude,
            visitCount: max(visitCount, 1),
            timestamp: timestamp,
            radius: minRadius + extraRadius * heat,
            opacity: minOpacity + extraOpacity * heat
        )
    }

    static func blobs(from samples: [Sample], now: Date = Date()) -> [HeatBlob] {
        let fresh = merging(samples, now: now).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
            return lhs.timestamp < rhs.timestamp
        }
        return fresh.enumerated().map { index, sample in
            pingBlob(
                at: CLLocation(latitude: sample.latitude, longitude: sample.longitude),
                id: sample.id,
                timestamp: sample.timestamp,
                recency: recency(indexFromOldest: index, count: fresh.count),
                visitCount: sample.visitCount
            )
        }
    }

    static func intensity(visitCount: Int) -> Double {
        let steps = max(redHotVisitCount - 1, 1)
        return min(1, Double(max(visitCount, 1) - 1) / Double(steps))
    }
}

/// On-device cache of the public interest trail so map mode still has pings if CloudKit lags.
enum InterestFootstepStore {
    private static let lock = NSRecursiveLock()
    private static let pendingKey = "grid.interestFootsteps.pending"

    static func defaultsKey(interest: String) -> String {
        "grid.interestFootsteps.\(InterestFootstepLogic.slug(interest, prefix: 48))"
    }

    static func load(interest: String, defaults: UserDefaults = .standard, now: Date = Date()) -> [InterestFootstepLogic.Sample] {
        lock.lock()
        defer { lock.unlock() }
        return decode(defaults.data(forKey: defaultsKey(interest: interest)), now: now)
    }

    static func save(
        _ samples: [InterestFootstepLogic.Sample],
        interest: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        let merged = InterestFootstepLogic.merging(
            InterestFootstepLogic.matching(samples, interest: interest),
            now: now
        )
        lock.lock()
        defer { lock.unlock() }
        defaults.set(encode(merged), forKey: defaultsKey(interest: interest))
    }

    static func append(
        _ samples: [InterestFootstepLogic.Sample],
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var grouped: [String: [InterestFootstepLogic.Sample]] = [:]
        for sample in samples {
            grouped[sample.interest.lowercased(), default: []].append(sample)
        }
        for (key, incoming) in grouped {
            let interest = incoming.first?.interest ?? key
            let existing = load(interest: interest, defaults: defaults, now: now)
            save(existing + incoming, interest: interest, defaults: defaults, now: now)
        }
    }

    static func loadPending(defaults: UserDefaults = .standard, now: Date = Date()) -> [InterestFootstepLogic.Sample] {
        lock.lock()
        defer { lock.unlock() }
        return decode(defaults.data(forKey: pendingKey), now: now)
    }

    static func savePending(_ samples: [InterestFootstepLogic.Sample], defaults: UserDefaults = .standard, now: Date = Date()) {
        let merged = InterestFootstepLogic.merging(samples, now: now)
        lock.lock()
        defer { lock.unlock() }
        defaults.set(encode(merged), forKey: pendingKey)
    }

    static func enqueuePending(_ samples: [InterestFootstepLogic.Sample], defaults: UserDefaults = .standard, now: Date = Date()) {
        savePending(loadPending(defaults: defaults, now: now) + samples, defaults: defaults, now: now)
    }

    static func removePending(ids: Set<String>, defaults: UserDefaults = .standard, now: Date = Date()) {
        let remaining = loadPending(defaults: defaults, now: now).filter { ids.contains($0.id) == false }
        savePending(remaining, defaults: defaults, now: now)
    }

    private static func encode(_ samples: [InterestFootstepLogic.Sample]) -> Data? {
        try? JSONEncoder().encode(samples)
    }

    private static func decode(_ data: Data?, now: Date) -> [InterestFootstepLogic.Sample] {
        guard let data,
              let samples = try? JSONDecoder().decode([InterestFootstepLogic.Sample].self, from: data) else {
            return []
        }
        return InterestFootstepLogic.merging(samples, now: now)
    }
}
