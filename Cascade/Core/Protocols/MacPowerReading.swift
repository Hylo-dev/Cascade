//
//  MacPowerReading.swift
//  Cascade
//

nonisolated protocol MacPowerReading: Sendable {

    func read() -> MacPowerSnapshot?
}
