//
//  NetworkMonitoring.swift
//  Cascade
//

/// NetworkMonitoring supplies local network availability without probing hosts
/// or reading network names. True describes an available route, not a guarantee
/// that a remote service or the Internet is reachable.
@MainActor
protocol NetworkMonitoring: AnyObject {

    func start() -> AsyncStream<Bool>
    func stop()
}
