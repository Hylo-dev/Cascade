import CascadeContracts
import Foundation

/// Actor-owned routing scalars, not history or permission to disclose broker results.
/// Every row is prepaid in the owner pool; no Data, task, timer or continuation lives here.
struct RuntimeServiceInvocationExchange: Sendable {
    enum Admission: Equatable, Sendable { case refused(AddonFailure.Code), admitted(UUID) }
    enum Terminal: Equatable, Sendable { case completed, refused(AddonFailure.Code), unknown }
    struct Route: Sendable {
        let id: UUID
        let consumer: AddonID
        let incarnation: RuntimeIncarnation
        let connectionToken: UUID
        let sequence: UInt64
        let grantID: UUID
        let requestID: UUID
        let contractID: String
        let operation: String
        var deadline: Duration
        var workID: UUID?
        var provider: AddonID?
        var providerIncarnation: RuntimeIncarnation?
        var providerReservation: UUID?
        var terminal: Terminal?
        var acceptedReceipt: RuntimeServiceReceipt?
        var settlement: RuntimeServiceSettlement {
            RuntimeServiceSettlement(routeID: id, incarnation: incarnation,
                                     connectionToken: connectionToken, sequence: sequence)
        }
    }
    static let maximumRoutes = 32
    static let routeBytes = max(4_096, 4 * MemoryLayout<Route>.stride)
    private(set) var routes: [UUID: Route] = [:]
    var count: Int { routes.count }
    func hasRoute(incarnation: RuntimeIncarnation) -> Bool { routes.values.contains { $0.incarnation == incarnation } }
    func retainedBytes(owner: AddonID) -> Int { routes.values.filter { $0.consumer == owner }.count * Self.routeBytes }
    mutating func insert(_ route: Route) { precondition(count < Self.maximumRoutes && !hasRoute(incarnation: route.incarnation)); routes[route.id] = route }
    mutating func update(_ route: Route) { guard routes[route.id] != nil else { return }; routes[route.id] = route }
    @discardableResult mutating func remove(_ id: UUID) -> Route? { routes.removeValue(forKey: id) }
    mutating func mark(workID: UUID, terminal: Terminal) {
        for id in routes.keys where routes[id]?.workID == workID && routes[id]?.terminal == nil { routes[id]?.terminal = terminal }
    }
    mutating func invalidate(owner: AddonID) {
        for id in routes.keys where routes[id]?.consumer == owner || routes[id]?.provider == owner {
            routes[id]?.terminal = .unknown
        }
    }
}
