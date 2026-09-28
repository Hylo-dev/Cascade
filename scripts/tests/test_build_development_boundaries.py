"""Real development-entry-point boundary regression; never builds an app.

Run with Xcode-beta DEVELOPER_DIR. For an isolated two-file delivery, point
CASCADE_BOUNDARY_CHECKER_SCRIPTS at the unchanged existing checker scripts.
Optional CASCADE_BUILD_BOUNDARY_EVIDENCE retains each fixture, argv/allowlisted environment/hashes
and complete trace. Removing the mandatory hook must break the negative tests.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
CHECKER_SCRIPTS = Path(os.environ.get('CASCADE_BOUNDARY_CHECKER_SCRIPTS', SCRIPTS))
CHECKER_FILES = ('check-addon-boundaries.sh', 'check-addon-imports.swift',
                 'check_addon_boundaries.py', 'tests/test_addon_boundaries.py')
PUBLIC = ('CascadeContracts', 'CascadePresentation', 'CascadeAddonSDK')
RECORDED_ENVIRONMENT = ('DEVELOPER_DIR', 'CASCADE_DERIVED_DATA', 'TMPDIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFTPM_MODULECACHE_OVERRIDE', 'XDG_CACHE_HOME', 'PATH', 'LANG', 'LANGUAGE', 'LC_ALL', 'LC_CTYPE', 'LC_MESSAGES', 'LC_COLLATE', 'LC_MONETARY', 'LC_NUMERIC', 'LC_TIME')


class BuildDevelopmentBoundaries(unittest.TestCase):
    def setUp(self):
        self.assertEqual(os.environ.get('DEVELOPER_DIR'),
                         '/Applications/Xcode-beta.app/Contents/Developer',
                         'This integration test requires the selected Xcode-beta toolchain')
        evidence = os.environ.get('CASCADE_BUILD_BOUNDARY_EVIDENCE')
        if evidence:
            parent = Path(evidence).resolve()
            parent.mkdir(parents=True, exist_ok=True)
            self.base = Path(tempfile.mkdtemp(prefix=self._testMethodName + '-', dir=parent))
        else:
            temporary = tempfile.TemporaryDirectory(prefix='cascade-build-boundaries-', dir='/private/tmp')
            self.addCleanup(temporary.cleanup)
            self.base = Path(temporary.name)
        self.root = self.base / 'Fixture With Spaces'
        self.cwd = self.base / 'Unrelated Working Directory'
        self.cwd.mkdir()
        self.fixture_scripts = self.root / 'scripts'
        self.fixture_scripts.mkdir(parents=True)
        self.candidate = self.fixture_scripts / 'build-development.sh'
        shutil.copy2(SCRIPTS / 'build-development.sh', self.candidate)
        for name in CHECKER_FILES:
            destination = self.fixture_scripts / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(CHECKER_SCRIPTS / name, destination)
            self.assertEqual(destination.read_bytes(), (CHECKER_SCRIPTS / name).read_bytes())
        # An absent updater makes accidental continuation fail, never touch Applications.
        self.assertFalse((self.fixture_scripts / 'update-application-link.sh').exists())
        self.sdk_manifest = self.root / 'CascadeKit/Package.swift'
        self.write(self.sdk_manifest, self.sdk_package())
        for name in (*PUBLIC, 'CascadeRuntime'):
            self.write(self.root / f'CascadeKit/Sources/{name}/Source.swift', 'import Foundation\n')
        for name in ('StandaloneFocus', 'ServiceConsumer', 'StandaloneClock'):
            self.write(self.root / f'Examples/{name}/Package.swift', f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "{name}",
    products: [.library(name: "{name}", targets: ["{name}"])],
    dependencies: [.package(name: "PublicCascadeSDK", path: "../../CascadeKit")],
    targets: [.target(name: "{name}", dependencies: [
        .product(name: "CascadeAddonSDK", package: "PublicCascadeSDK")
    ])]
)
''')
            self.write(self.root / f'Examples/{name}/Sources/{name}/Source.swift',
                       'import CascadeAddonSDK\n')
        self.source = self.root / 'Examples/StandaloneFocus/Sources/StandaloneFocus/Source.swift'

    @staticmethod
    def write(path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    @staticmethod
    def sdk_package(private_dependency=False):
        products = ',\n'.join(f'.library(name: "{name}", targets: ["{name}"])' for name in PUBLIC)
        targets = ',\n'.join(f'.target(name: "{name}", dependencies: '
                              + ('["CascadeRuntime"]' if private_dependency and name == 'CascadeAddonSDK' else '[]')
                              + ')' for name in (*PUBLIC, 'CascadeRuntime'))
        return f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CascadeKit", products: [{products}], targets: [{targets}])
'''

    def hashes(self):
        return {str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(self.root.rglob('*')) if path.is_file()}

    def execute(self):
        # Required safety prerequisite checked immediately before the exact script runs.
        self.assertFalse(any(self.root.rglob('*.xcodeproj')))
        self.assertFalse((self.root / 'Cascade.xcodeproj').exists())
        environment = dict(os.environ)
        for key in list(environment):
            if 'CACHE' in key or key.startswith(('CASCADE_', 'SWIFTPM_', 'SWIFT_', 'CLANG_')):
                environment.pop(key)
        for name in ('tmp', 'derived', 'clang-cache', 'swiftpm-cache', 'xdg-cache'):
            (self.base / name).mkdir()
        environment.update({
            'DEVELOPER_DIR': '/Applications/Xcode-beta.app/Contents/Developer',
            'CASCADE_DERIVED_DATA': str(self.base / 'derived'),
            'TMPDIR': str(self.base / 'tmp') + '/',
            'CLANG_MODULE_CACHE_PATH': str(self.base / 'clang-cache'),
            'SWIFTPM_MODULECACHE_OVERRIDE': str(self.base / 'swiftpm-cache'),
            'XDG_CACHE_HOME': str(self.base / 'xdg-cache'), 'PYTHONDONTWRITEBYTECODE': '1',
        })
        # Preserve reserved/inherited home inputs; record only boolean proof.
        home_inputs_unchanged = all(
            environment.get(key) == os.environ.get(key)
            and (key in environment) == (key in os.environ)
            for key in ('HOME', 'CODEX_HOME', 'CFFIXED_USER_HOME')
        )
        self.assertTrue(home_inputs_unchanged, 'Inherited home inputs must remain unchanged')
        command = ['/bin/zsh', '-x', str(self.candidate)]
        before = self.hashes()
        record = {'argv': command, 'cwd': str(self.cwd), 'environment': {key: environment[key] for key in RECORDED_ENVIRONMENT
                                  if key in environment},
                  'inherited_home_inputs_unchanged': home_inputs_unchanged,
                  'preimage_sha256': before, 'timeout_seconds': 240,
                  'project_absent': True}
        # Record only explicit nonsecret execution inputs, never the inherited environment.
        evidence = self.base / 'execution.json'
        evidence.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
        evidence.chmod(0o600)
        process = subprocess.Popen(command, cwd=self.cwd, env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=240)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            (self.base / 'stdout.log').write_text(stdout)
            (self.base / 'stderr.log').write_text(stderr)
            self.fail('Command timed out; process group killed and joined (not a behavioral RED)')
        (self.base / 'stdout.log').write_text(stdout)
        (self.base / 'stderr.log').write_text(stderr)
        record.update(returncode=process.returncode, postimage_sha256=self.hashes(), joined=True)
        evidence.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
        self.assertEqual(before, record['postimage_sha256'], 'Fixture inputs changed during execution')
        self.assertNotEqual(process.returncode, 0, stdout + stderr)
        return stdout, stderr

    @staticmethod
    def executed(trace):
        # zsh -x command records only, not commands mentioned in diagnostic prose.
        return '\n'.join(line for line in trace.splitlines() if re.match(r'^\+.*> ', line))

    def assert_stopped_before_build(self, trace):
        executed = self.executed(trace)
        for forbidden in ('/usr/bin/xcodebuild', '/usr/bin/codesign', 'update-application-link.sh'):
            self.assertNotIn(forbidden, executed, executed)
        self.assertIn('check-addon-boundaries.sh', executed)
        self.assertIn('--root', executed)
        self.assertIn(str(self.root), executed)
        self.assertIn('DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer', executed)

    def test_private_import_stops_before_build(self):
        self.source.write_text('import CascadeAddonSDK\nimport CascadeRuntime\n')
        stdout, trace = self.execute()
        self.assertIn('Addon boundary check failed:', trace, stdout + trace)
        self.assertIn('private host import CascadeRuntime', trace)
        self.assert_stopped_before_build(trace)

    def test_private_sdk_dependency_stops_before_build(self):
        self.sdk_manifest.write_text(self.sdk_package(private_dependency=True))
        stdout, trace = self.execute()
        self.assertIn('Addon boundary check failed:', trace, stdout + trace)
        self.assertIn('CascadeAddonSDK: dependency CascadeRuntime is outside the public SDK/example targets', trace)
        self.assert_stopped_before_build(trace)

    def test_clock_private_import_stops_before_build(self):
        source = self.root / 'Examples/StandaloneClock/Sources/StandaloneClock/Source.swift'
        source.write_text('import CascadeAddonSDK\nimport CascadeRuntime\n')
        stdout, trace = self.execute()
        self.assertIn('private host import CascadeRuntime', trace, stdout + trace)
        self.assert_stopped_before_build(trace)

    def test_missing_checker_stops_before_build(self):
        (self.fixture_scripts / 'check-addon-boundaries.sh').unlink()
        stdout, trace = self.execute()
        self.assertIn('check-addon-boundaries.sh', trace, stdout + trace)
        self.assertIn("can't open input file", trace)
        self.assert_stopped_before_build(trace)

    def test_public_fixture_passes_checker_then_reaches_missing_project(self):
        stdout, trace = self.execute()
        self.assertIn('PASS: 4 packages, 6 targets, 6 Swift files, 6 imports', stdout, stdout + trace)
        executed = self.executed(trace)
        self.assertLess(executed.index('check-addon-boundaries.sh'), executed.index('/usr/bin/xcodebuild'))
        self.assertIn('does not exist', trace, stdout + trace)
        self.assertIn(str(self.root / 'Cascade.xcodeproj'), trace)
        self.assertNotIn('/usr/bin/codesign', executed)
        self.assertNotIn('update-application-link.sh', executed)
        self.assertIn(str(self.base / 'derived'), executed)
        self.assertIn('--root', executed)
        self.assertIn(str(self.root), executed)


if __name__ == '__main__':
    unittest.main()
