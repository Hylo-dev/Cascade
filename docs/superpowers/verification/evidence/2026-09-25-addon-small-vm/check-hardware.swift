import Foundation
import Virtualization
let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let data = Data(base64Encoded: configuration["hardwareModel"] as! String)!
let model = VZMacHardwareModel(dataRepresentation: data)
let result: [String: Any] = ["hardwareModelValid": model != nil, "hardwareModelSupported": model?.isSupported ?? false, "virtualizationSupported": VZVirtualMachine.isSupported]
let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: encoded, encoding: .utf8)!)
