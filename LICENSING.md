# Cascade licensing

Copyright (c) 2026 Cascade contributors.

## Default license: Cascade app and host

Except for the MIT-covered paths below and separately licensed third-party
material, Cascade is licensed under the GNU General Public License, version 3
only (`GPL-3.0-only`), with the additional permission in
[`LICENSES/Cascade-Plugin-Exception.txt`](LICENSES/Cascade-Plugin-Exception.txt).
The unmodified GPLv3 text is in [`LICENSE`](LICENSE).

Cascade is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, version 3 of the License, with the additional permission identified
above.

Cascade is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
Cascade. If not, see <https://www.gnu.org/licenses/>.

The default includes the app, notch engine, host renderer, plugin engine
(kernel), PluginHost, runtime, bundled first-party plugins, development tools
and tests outside the MIT-covered paths. A public Swift symbol or SwiftPM
product is not, by itself, an MIT license grant.

## MIT-covered SDK and contracts

The following repository-relative paths, including their original source,
resources and documentation, are licensed under the MIT License in
[`LICENSES/MIT.txt`](LICENSES/MIT.txt). Directory entries cover their complete
contents; individual file entries cover only that file.

| Path | Scope |
| --- | --- |
| `CascadeKit/Sources/CascadePluginSDK/` | Public plugin protocol and document builder |
| `CascadeKit/Sources/CascadeContracts/` | Public value models and protocol contracts |
| `CascadeKit/Tests/CascadeContractsTests/` | Contract tests and fixtures |
| `CascadeKit/Package.swift` | Package manifest; this does not change target licenses |
| `docs/plugins/` | Developer guides, plugin contract and manifest schema |

These grants permit proprietary plugins and reuse of the SDK, subject to
retaining the MIT copyright and permission notices. They do not grant an MIT
license to `CascadeKit`, `CascadeRuntime`, `CascadePluginHost`,
`CascadePluginEngine`, `CascadePlugins` or `CascadePluginTool`. Plugins may
call host services; those host implementations retain their default GPLv3
license.

When copying SDK sources into another project, include the MIT notice with
the copied material. A plugin author may license their own additions under
different terms, including proprietary terms.

## Proprietary plugins

The [Cascade Plugin Exception](LICENSES/Cascade-Plugin-Exception.txt) is an
additional permission under GPLv3 section 7. It permits independently authored
plugins and their source apps to use the public SDK and documented plugin
interfaces under licenses of their authors' choosing, including proprietary
licenses. This permission covers the intended events, publications, actions
and service requests through those interfaces.

It does not permit distributing a proprietary fork of Cascade, copying
GPL-covered engine or host implementation into a closed plugin, or bypassing
the GPL by naming a modified host a plugin. Modifications to GPL-covered
Cascade code remain subject to GPLv3 when conveyed. Purely private modifications
do not require publication, and the GPL does not require a pull request to this
repository or payment to its maintainers.

This license permission does not relax the plugin engine's admission,
signing, permissions, process isolation or resource policies.

## Third-party material and distribution

Existing third-party notices and terms take precedence for the material they
cover. This licensing notice does not relicense third-party code or Apple
frameworks, system libraries, fonts or SF Symbols. FFmpeg and ffprobe retain
their own terms; see [`Config/FFmpeg/Notices/`](Config/FFmpeg/Notices/) and
[`docs/third-party/ffmpeg.md`](docs/third-party/ffmpeg.md).

The app build includes `LICENSE`, this notice, the MIT text and the plugin
exception in `Cascade.app/Contents/Resources/Licenses/`. Binary distributors
must also meet GPLv3's corresponding-source requirements for the version they
convey and the applicable third-party obligations. Including license texts
alone does not fulfill those source requirements.

New contributions must be licensed under the terms applicable to their paths,
including the plugin exception where it applies. Contributors retain their
copyright. No copyright assignment or commercial license is established by
this notice.
