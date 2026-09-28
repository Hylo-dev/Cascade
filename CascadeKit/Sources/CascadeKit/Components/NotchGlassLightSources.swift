import CascadeContracts

/// One contribution per hosting surface; generations reject late SwiftUI
/// preference deliveries after content has been replaced or removed.
nonisolated struct NotchGlassLightSources {
    struct Token: Equatable, Sendable {
        let source: ObjectIdentifier
        let generation: UInt64
    }

    private var generations: [ObjectIdentifier: UInt64] = [:]
    private var contributions: [ObjectIdentifier: [GlassLight]] = [:]
    private var order: [ObjectIdentifier] = []

    var lights: [GlassLight] {
        Array(order.flatMap { contributions[$0] ?? [] }.prefix(GlassLight.maximumCount))
    }

    /// Replacement revokes the old contribution immediately, before SwiftUI
    /// can asynchronously deliver the new root's lights or privacy placeholder.
    mutating func replace(source: ObjectIdentifier) -> Token {
        if generations[source] == nil { order.append(source) }
        let generation = (generations[source] ?? 0) &+ 1
        generations[source] = generation
        contributions[source] = nil
        return Token(source: source, generation: generation)
    }

    /// remove forgets a source that will never contribute again, so emitters
    /// that come and go leave no entries behind.
    mutating func remove(source: ObjectIdentifier) {
        generations[source] = nil
        contributions[source] = nil
        order.removeAll { $0 == source }
    }

    @discardableResult
    mutating func update(_ lights: [GlassLight], for token: Token) -> Bool {
        guard generations[token.source] == token.generation else { return false }
        let bounded = Array(lights.prefix(GlassLight.maximumCount))
        guard (contributions[token.source] ?? []) != bounded else { return false }
        contributions[token.source] = bounded
        return true
    }
}
