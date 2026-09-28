//
//  BluetoothBatterySnapshot.swift
//  Cascade
//

/// BluetoothBatterySnapshot contains only measured percentages. Its summary
/// uses the least charged known earbud; the case never substitutes for a bud.
nonisolated struct BluetoothBatterySnapshot: Equatable, Sendable {

    let level    : Int?
    let left     : Int?
    let right    : Int?
    let caseLevel: Int?

    init(
        level    : Int? = nil,
        left     : Int? = nil,
        right    : Int? = nil,
        caseLevel: Int? = nil
    ) {
        self.left      = Self.validPercentage(left)
        self.right     = Self.validPercentage(right)
        self.caseLevel = Self.validPercentage(caseLevel)
        self.level     = [self.left, self.right].compactMap { $0 }.min() ?? Self.validPercentage(level)
    }

    var hasMeasurement: Bool {
        level != nil || caseLevel != nil
    }

    /// fillingMissing preserves the more authoritative sample for each component.
    func fillingMissing(from fallback: BluetoothBatterySnapshot?) -> BluetoothBatterySnapshot {
        BluetoothBatterySnapshot(
            level    : level ?? fallback?.level,
            left     : left ?? fallback?.left,
            right    : right ?? fallback?.right,
            caseLevel: caseLevel ?? fallback?.caseLevel
        )
    }

    private static func validPercentage(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }

        return value
    }
}
