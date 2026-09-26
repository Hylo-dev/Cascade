import CascadeContracts
import Foundation

public enum ResourceDimension: Hashable, Sendable {
    case publications, activities, notices, jobs, commands, providers, scenes
    case retainedStateBytes, assetBytes, admittedMemoryBytes, diskStateBytes, diskCacheBytes, diskBytes
}

public enum ResourceRequest: Sendable {
    case publication(Publication.Kind)
    case job, command, provider, scene
    case state(bytes: Int), asset(bytes: Int), temporaryMemory(bytes: Int)
    case diskState(bytes: Int), diskCache(bytes: Int)
}

/// Host policy can tighten ceilings. Package origin and publisher do not select a policy.
public struct ResourcePolicy: Sendable {
    // Includes the reservation, bounded charge map and owner-index overhead.
    static let reservationCharge = 1_024
    static let mebibyte = 1_024 * 1_024
    public let maximumRetainedStateBytes: Int
    public init(maximumRetainedStateBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumRetainedStateBytes = min(8 * 1_024 * 1_024, max(0, maximumRetainedStateBytes))
    }

    func ceiling(_ dimension: ResourceDimension, perOwner: Bool) -> Int {
        let mib = Self.mebibyte
        switch dimension {
        case .publications: return perOwner ? 16 : Int.max
        case .activities: return perOwner ? 4 : 16
        case .notices: return 8
        case .jobs: return perOwner ? 1 : 2
        case .commands: return perOwner ? 4 : Int.max
        case .providers: return perOwner ? 1 : 3
        case .scenes: return 1
        case .retainedStateBytes: return maximumRetainedStateBytes
        case .assetBytes: return (perOwner ? 8 : 32) * mib
        case .admittedMemoryBytes: return (perOwner ? 128 : 256) * mib
        case .diskStateBytes: return (perOwner ? 10 : 100) * mib
        case .diskCacheBytes: return (perOwner ? 20 : 100) * mib
        case .diskBytes: return (perOwner ? 30 : 100) * mib
        }
    }

    func charges(for request: ResourceRequest) throws -> [ResourceDimension: Int] {
        var result: [ResourceDimension: Int] = [.retainedStateBytes: Self.reservationCharge]
        func bytes(_ value: Int, dimension: ResourceDimension) throws {
            // Check before addition, including malformed host requests and Int.max.
            let previous = result[dimension, default: 0]
            guard value >= 0, previous <= ceiling(dimension, perOwner: true),
                  value <= ceiling(dimension, perOwner: true) - previous else {
                throw AddonFailure(code: .resourceDenied, reason: "The requested resource amount exceeds its budget.")
            }
            result[dimension] = previous + value
        }
        switch request {
        case .publication(let kind):
            result[.publications] = 1
            if kind == .activity { result[.activities] = 1 }
            if kind == .notice { result[.notices] = 1 }
        case .job: result[.jobs] = 1
        case .command: result[.commands] = 1
        case .provider:
            result[.providers] = 1
            result[.admittedMemoryBytes] = 64 * Self.mebibyte
        case .scene:
            result[.scenes] = 1
            result[.admittedMemoryBytes] = 64 * Self.mebibyte
        case .state(let count): try bytes(count, dimension: .retainedStateBytes)
        case .asset(let count):
            try bytes(count, dimension: .assetBytes)
            try bytes(count, dimension: .admittedMemoryBytes)
        case .temporaryMemory(let count): try bytes(count, dimension: .admittedMemoryBytes)
        case .diskState(let count):
            try bytes(count, dimension: .diskStateBytes)
            try bytes(count, dimension: .diskBytes)
        case .diskCache(let count):
            try bytes(count, dimension: .diskCacheBytes)
            try bytes(count, dimension: .diskBytes)
        }
        return result
    }
}

public struct ResourceReservation: Sendable {
    public let id: UUID
    public let owner: AddonID
}
