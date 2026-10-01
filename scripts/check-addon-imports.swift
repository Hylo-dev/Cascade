//
//  check-addon-imports.swift
//  Cascade
//

import Foundation
import SwiftParser
import SwiftSyntax

/// ImportAttributes collects an import's attribute names, walking every source
/// branch without resolving modules or executing provider code.
/// Macro expansion and manifest-environment alternatives are outside this check.
final class ImportAttributes: SyntaxVisitor {

    var names: [String] = []

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        names.append(node.attributeName.trimmedDescription)
        return .skipChildren
    }
}

final class ImportCollector: SyntaxVisitor {

    private let locations: SourceLocationConverter
    var imports          : [[String: Any]] = []

    init(
        file: String,
        tree: SourceFileSyntax
    ) {
        locations = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let first = node.path.first else { return .skipChildren }

        let attributes = ImportAttributes()
        attributes.walk(node.attributes)

        let location = locations.location(for: node.importKeyword.positionAfterSkippingLeadingTrivia)
        let module   = first.name.text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        imports.append([
            "module"    : module,
            "attributes": attributes.names,
            "line"      : location.line,
            "column"    : location.column,
        ])

        return .skipChildren
    }
}

let paths   = try JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
var reports: [[String: Any]] = []

for path in paths {
    do {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let tree   = Parser.parse(source: source)
        guard !tree.hasError else {
            reports.append(["path": path, "error": "Swift syntax could not be parsed", "imports": []])
            continue
        }

        let collector = ImportCollector(file: path, tree: tree)
        collector.walk(tree)
        reports.append(["path": path, "error": NSNull(), "imports": collector.imports])
    } catch {
        reports.append(["path": path, "error": error.localizedDescription, "imports": []])
    }
}

let data = try JSONSerialization.data(withJSONObject: reports, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
