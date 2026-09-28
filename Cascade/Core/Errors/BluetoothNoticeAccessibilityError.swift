//
//  BluetoothNoticeAccessibilityError.swift
//  Cascade
//

/// BluetoothNoticeAccessibilityError preserves the difference between absent AX support and failure.
nonisolated enum BluetoothNoticeAccessibilityError: Error {

    case unsupported(String)
    case failure    (Int32)

    var status: BluetoothNoticeSuppressionStatus {
        switch self {
            case .unsupported(let reason): .unsupported(reason)
            case .failure(let code)      : .failure("Accessibility error \(code).")
        }
    }
}
