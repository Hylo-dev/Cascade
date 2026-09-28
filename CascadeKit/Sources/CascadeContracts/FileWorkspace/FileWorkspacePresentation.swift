//
//  FileWorkspacePresentation.swift
//  Cascade
//

import Foundation

/// FileWorkspaceMode selects one host-rendered shelf surface.
public enum FileWorkspaceMode: String, Codable, Equatable, Sendable {
    case deck, list, conversion
}

/// FileWorkspaceActionBinding gives one closed semantic role a complete published action.
///
/// The renderer uses the target only to choose a control. It always dispatches the immutable
/// descriptor verbatim, so target identifiers never become authority or synthesized payloads.
public struct FileWorkspaceActionBinding: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case openList, closeList, select, nextPage, convert, selectFormat, start, cancel
        case remove, relink, preview, reveal
    }

    public let role      : Role
    public let entryID   : UUID?
    public let formatID  : String?
    public let jobID     : UUID?
    public let descriptor: ActionDescriptor

    public init(
        role      : Role,
        entryID   : UUID? = nil,
        formatID  : String? = nil,
        jobID     : UUID? = nil,
        descriptor: ActionDescriptor
    ) throws {
        self.role       = role
        self.entryID    = entryID
        self.formatID   = formatID
        self.jobID      = jobID
        self.descriptor = descriptor
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown file workspace action field"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            role      : values.decode(Role.self, forKey: .role),
            entryID   : values.decodeIfPresent(UUID.self, forKey: .entryID),
            formatID  : values.decodeIfPresent(String.self, forKey: .formatID),
            jobID     : values.decodeIfPresent(UUID.self, forKey: .jobID),
            descriptor: values.decode(ActionDescriptor.self, forKey: .descriptor)
        )
    }

    public func validate() throws {
        try descriptor.validate()
        if let formatID {
            try ContractValidation.require(
                ContractValidation.identifier(formatID),
                "Invalid file workspace action format"
            )
        }
        switch role {
        case .select, .remove, .relink, .preview, .reveal:
            try ContractValidation.require(
                entryID != nil && formatID == nil && jobID == nil,
                "File workspace entry action requires exactly one entry target"
            )
        case .selectFormat:
            try ContractValidation.require(
                entryID == nil && formatID != nil && jobID == nil,
                "File workspace format action requires exactly one format target"
            )
        case .cancel:
            try ContractValidation.require(
                entryID == nil && formatID == nil && jobID != nil,
                "File workspace cancel action requires exactly one job target"
            )
        case .openList, .closeList, .nextPage, .convert, .start:
            try ContractValidation.require(
                entryID == nil && formatID == nil && jobID == nil,
                "File workspace global action cannot carry a target"
            )
        }
    }

    fileprivate var semanticKey: String {
        [role.rawValue, entryID?.uuidString, formatID, jobID?.uuidString]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role, entryID, formatID, jobID, descriptor
    }
}

/// FileWorkspacePresentation is one bounded, host-rendered snapshot of the shared file shelf.
public struct FileWorkspacePresentation: Codable, Equatable, Sendable {
    public static let maximumActions = 64
    public static let maximumFormats = 32

    public let snapshot        : FileWorkspaceSnapshot
    public let mode            : FileWorkspaceMode
    public let selectedEntryIDs: [UUID]
    public let formats         : [FileConversionFormat]
    public let selectedFormatID: String?
    public let actions         : [FileWorkspaceActionBinding]

    public init(
        snapshot        : FileWorkspaceSnapshot,
        mode            : FileWorkspaceMode,
        selectedEntryIDs: [UUID],
        formats         : [FileConversionFormat],
        selectedFormatID: String?,
        actions         : [FileWorkspaceActionBinding]
    ) throws {
        self.snapshot         = snapshot
        self.mode             = mode
        self.selectedEntryIDs = selectedEntryIDs
        self.formats          = formats
        self.selectedFormatID = selectedFormatID
        self.actions          = actions
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown file workspace presentation field"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let selected = try BoundedContractArray.decode(
            UUID.self,
            from   : values.superDecoder(forKey: .selectedEntryIDs),
            maximum: 32
        )
        let formats = try BoundedContractArray.decode(
            FileConversionFormat.self,
            from   : values.superDecoder(forKey: .formats),
            maximum: Self.maximumFormats
        )
        let actions = try BoundedContractArray.decode(
            FileWorkspaceActionBinding.self,
            from   : values.superDecoder(forKey: .actions),
            maximum: Self.maximumActions
        )
        try self.init(
            snapshot        : values.decode(FileWorkspaceSnapshot.self, forKey: .snapshot),
            mode            : values.decode(FileWorkspaceMode.self, forKey: .mode),
            selectedEntryIDs: selected,
            formats         : formats,
            selectedFormatID: values.decodeIfPresent(String.self, forKey: .selectedFormatID),
            actions         : actions
        )
    }

    public func validate() throws {
        try snapshot.validate()
        try FileWorkspaceWire.validateIDs(selectedEntryIDs, requiresNonempty: false)
        try ContractValidation.require(formats.count <= Self.maximumFormats, "Too many conversion formats")
        try ContractValidation.require(actions.count <= Self.maximumActions, "Too many file workspace actions")
        try ContractValidation.unique(formats.map(\.id), "Duplicate conversion formats")
        try ContractValidation.unique(actions.map(\.semanticKey), "Duplicate file workspace action binding")
        try ContractValidation.unique(actions.map(\.descriptor.id), "Duplicate file workspace action descriptor")

        let entryIDs  = Set(snapshot.entries.map(\.id))
        let resultIDs = Set(snapshot.jobs.flatMap(\.resultIDs))
        let formatIDs = Set(formats.map(\.id))
        let jobIDs    = Set(snapshot.jobs.map(\.id))
        try ContractValidation.require(
            Set(selectedEntryIDs).isSubset(of: entryIDs),
            "File workspace selection references an entry outside the presented page"
        )
        try ContractValidation.require(
            selectedFormatID.map(formatIDs.contains) ?? true,
            "Selected conversion format is not presented"
        )
        for format in formats { try format.validate() }
        for action in actions {
            try action.validate()
            if let entryID = action.entryID {
                try ContractValidation.require(
                    entryIDs.contains(entryID) || resultIDs.contains(entryID),
                    "File workspace action references an unpresented entry"
                )
            }
            if let formatID = action.formatID {
                try ContractValidation.require(
                    formatIDs.contains(formatID),
                    "File workspace action references an unpresented format"
                )
            }
            if let jobID = action.jobID {
                try ContractValidation.require(
                    jobIDs.contains(jobID),
                    "File workspace action references an unpresented job"
                )
            }
        }
    }

    /// action returns the exact descriptor published for one semantic control.
    public func action(
        for role : FileWorkspaceActionBinding.Role,
        entryID  : UUID? = nil,
        formatID : String? = nil,
        jobID    : UUID? = nil
    ) -> ActionDescriptor? {
        actions.first {
            $0.role == role && $0.entryID == entryID && $0.formatID == formatID && $0.jobID == jobID
        }?.descriptor
    }

    var referencedAssets: Set<String> {
        Set(snapshot.entries.compactMap(\.thumbnailAssetID))
    }

    var actionIdentifiers: [String] {
        actions.map(\.descriptor.id)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case snapshot, mode, selectedEntryIDs, formats, selectedFormatID, actions
    }
}
