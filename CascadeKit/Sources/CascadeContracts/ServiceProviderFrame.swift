import Foundation

/// Dedicated provider input syntax. No source-update or runtime activation is implied.
public enum ServiceProviderFrame: Codable, Equatable, Sendable {
    case invocation(ServiceInvocation)

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try ContractValidation.require(
            try values.decode(String.self, forKey: .kind) == "providerInvoke",
            "Unknown service provider kind"
        )
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == ["schemaVersion", "kind", "invocation"],
            "Invalid service provider fields"
        )
        try ContractValidation.require(
            try values.decode(Int.self, forKey: .schemaVersion) == 1,
            "Unsupported service provider schema"
        )
        self = .invocation(try values.decode(ServiceInvocation.self, forKey: .invocation))
        try validate()
    }

    public func validate() throws {
        switch self { case .invocation(let invocation): try invocation.validate() }
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schemaVersion)
        try values.encode("providerInvoke", forKey: .kind)
        switch self { case .invocation(let invocation): try values.encode(invocation, forKey: .invocation) }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, kind, invocation }
}
