//
//  main.swift
//  CascadeKit
//

import Darwin
import Foundation

let result = PluginToolCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
let stream = result.exitCode == 0 ? FileHandle.standardOutput : FileHandle.standardError
stream.write(Data((result.output + "\n").utf8))
exit(result.exitCode)
