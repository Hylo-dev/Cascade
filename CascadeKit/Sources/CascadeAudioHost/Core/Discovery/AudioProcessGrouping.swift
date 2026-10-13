//
//  AudioProcessGrouping.swift
//  CascadeKit
//

import CascadeContracts

/// AudioProcessGrouping folds Core Audio's per-process view into the per-app view the user sees.
///
/// Core Audio reports audio per process, but a browser renders its audio in helper processes
/// (`Google Chrome Helper.app` nested inside `Google Chrome.app`), so steering "Chrome" means
/// steering all of them. Everything here is a pure walk over strings and injected lookups: no
/// disk access, no HAL calls, so it is cheap, deterministic and testable without any real app.
public enum AudioProcessGrouping {

    /// Returns the path of the outermost `.app` bundle that contains `executablePath`, or nil when
    /// the path lies in no bundle.
    ///
    /// The *first* `.app` component wins on purpose: a helper is an `.app` nested inside the real
    /// app, and the outer one is the identity the user knows. For
    /// `/Applications/Google Chrome.app/Contents/Frameworks/.../Helper.app/Contents/MacOS/x` it
    /// returns `/Applications/Google Chrome.app`.
    public static func outermostApp(of executablePath: String) -> String? {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: false)

        guard let appIndex = components.firstIndex(where: isAppBundleName) else { return nil }

        return components[...appIndex].joined(separator: "/")
    }

    /// Groups `processes` under the app that owns them, keeping the input order inside each group.
    ///
    /// The identity of a process is, in order of preference:
    ///
    /// 1. the bundle ID of the outermost `.app` of its executable path, resolved through
    ///    `bundleIDOfApp`, which is how every browser helper lands under its browser;
    /// 2. the bundle ID of the app at `responsibleAppPath(pid)`, for a process that lives outside
    ///    its app (WebKit's audio process can sit in a system framework, not in Safari.app);
    /// 3. the process's own bundle ID.
    ///
    /// A process none of these identifies is left out: an unidentified process is never controlled,
    /// because muting something we cannot name would be a guess. Every record is grouped whether
    /// or not it is producing output; filtering on `isRunningOutput` is the caller's decision.
    public static func group(
        _ processes        : [AudioProcessRecord],
        bundleIDOfApp      : (String) -> String?,
        responsibleAppPath : (Int32) -> String? = { _ in nil }
    ) -> [AudioAppIdentity: [AudioProcessRecord]] {
        var groups: [AudioAppIdentity: [AudioProcessRecord]] = [:]

        for process in processes {
            let resolvedBundleID = bundleID(
                for                : process,
                bundleIDOfApp      : bundleIDOfApp,
                responsibleAppPath : responsibleAppPath
            )

            guard
                let resolvedBundleID,
                let identity = try? AudioAppIdentity(bundleID: resolvedBundleID)
            else { continue }

            groups[identity, default: []].append(process)
        }

        return groups
    }

    private static func isAppBundleName(_ component: Substring) -> Bool {
        component.hasSuffix(".app") && component.count > ".app".count
    }

    private static func bundleID(
        for process        : AudioProcessRecord,
        bundleIDOfApp      : (String) -> String?,
        responsibleAppPath : (Int32) -> String?
    ) -> String? {
        if
            let executablePath = process.executablePath,
            let enclosingApp   = outermostApp(of: executablePath),
            let bundleID       = nonEmpty(bundleIDOfApp(enclosingApp))
        {
            return bundleID
        }

        if let responsiblePath = responsibleAppPath(process.pid) {
            let responsibleApp = outermostApp(of: responsiblePath) ?? responsiblePath

            if let bundleID = nonEmpty(bundleIDOfApp(responsibleApp)) { return bundleID }
        }

        return nonEmpty(process.bundleID)
    }

    private static func nonEmpty(_ bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }

        return bundleID
    }
}
