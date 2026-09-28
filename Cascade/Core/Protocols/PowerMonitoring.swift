//
//  PowerMonitoring.swift
//  Cascade
//

@MainActor
protocol PowerMonitoring: AnyObject {

    func start() -> AsyncStream<PowerConnectionUpdate>
    func stop()
}
