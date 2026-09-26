import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'check_addon_boundaries.py'
spec = importlib.util.spec_from_file_location('addon_boundaries', SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def target(name, dependencies=(), kind='regular'):
    return {'name': name, 'type': kind, 'dependencies': list(dependencies),
            'settings': [], 'exclude': [], 'resources': []}


def local(name):
    return {'byName': [name, None]}


def sdk_model():
    return {'name': 'CascadeKit', 'dependencies': [],
            'products': [{'name': name, 'targets': [name], 'type': {'library': ['automatic']}}
                         for name in checker.PUBLIC_MODULES],
            'targets': [target('CascadeContracts'),
                        target('CascadePresentation', [local('CascadeContracts')]),
                        target('CascadeAddonSDK', [local('CascadeContracts'), local('CascadePresentation')]),
                        target('CascadeRuntime'), target('CascadeKit'), target('CascadeAddonTool', kind='executable')]}


def example_model(sdk_root):
    return {'name': 'Example',
            'dependencies': [{'fileSystem': [{'identity': 'cascadekit',
                                             'nameForTargetDependencyResolutionOnly': 'PublicCascadeSDK',
                                             'path': str(sdk_root), 'productFilter': None}]}],
            'products': [],
            'targets': [target('Provider', [{'product': ['CascadeAddonSDK', 'PublicCascadeSDK', None, None]}]),
                        target('ProviderTests', [local('Provider')], kind='test')]}


class GraphTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name).resolve()

    def tearDown(self):
        self.directory.cleanup()

    def test_clock_manifest_is_required_before_toolchain_execution(self):
        for relative in ['CascadeKit', 'Examples/StandaloneFocus', 'Examples/ServiceConsumer']:
            package = self.root / relative
            package.mkdir(parents=True)
            (package / 'Package.swift').write_text('// Trusted manifest placeholder for input check\n')
        with mock.patch.object(checker, 'dump_package', side_effect=AssertionError('Clock omitted from audit')):
            with self.assertRaisesRegex(checker.BoundaryError, 'StandaloneClock'):
                checker.audit(self.root, 'unused-scanner', 'unused-swift', self.root / 'cache')

    def test_public_sdk_does_not_inherit_exported_host_runtime(self):
        model = sdk_model()
        model['products'].append({'name': 'CascadeRuntime', 'targets': ['CascadeRuntime'], 'type': {'library': ['automatic']}})
        model['targets'][2]['dependencies'].append(local('CascadeRuntime'))
        with self.assertRaisesRegex(checker.BoundaryError, 'private|public'):
            checker.validate_package(model, self.root, self.root, sdk=True)

    def test_transitive_dependency_cannot_hide_in_contracts(self):
        model = sdk_model()
        model['targets'][0]['dependencies'].append(local('CascadeRuntime'))
        with self.assertRaises(checker.BoundaryError):
            checker.validate_package(model, self.root, self.root, sdk=True)

    def test_expected_public_closure_remains_allowed(self):
        result = checker.validate_package(sdk_model(), self.root, self.root, sdk=True)
        self.assertEqual({value['name'] for value in result}, set(checker.PUBLIC_MODULES))

    def test_sdk_products_targets_and_configuration_fail_closed(self):
        def missing(model):
            model['targets'].pop(2)
        def duplicate(model):
            model['targets'].append(copy.deepcopy(model['targets'][0]))
        def wrong_product(model):
            model['products'][0]['targets'] = ['CascadeRuntime']
        def cycle(model):
            model['targets'][0]['dependencies'] = [local('CascadeAddonSDK')]
        def unsafe(model):
            model['targets'][2]['settings'] = [{'tool': 'swift', 'kind': {'unsafeFlags': {'_0': ['-I', '../host']}}}]
        def plugin(model):
            model['targets'][2]['pluginUsages'] = [{'plugin': ['Generator', None]}]
        def binary(model):
            model['targets'][2]['type'] = 'binary'
        def malformed(model):
            model['targets'][2]['dependencies'] = [{'byName': ['CascadeContracts', None], 'target': ['CascadeRuntime', None]}]
        for mutate in [missing, duplicate, wrong_product, cycle, unsafe, plugin, binary, malformed]:
            with self.subTest(mutate=mutate.__name__):
                model = sdk_model(); mutate(model)
                with self.assertRaises(checker.BoundaryError):
                    checker.validate_package(model, self.root, self.root, sdk=True)

    def test_example_uses_own_targets_and_exact_sdk_package(self):
        model = example_model(self.root)
        result = checker.validate_package(model, self.root, self.root, sdk=False)
        self.assertEqual({value['name'] for value in result}, {'Provider', 'ProviderTests'})
        for change in ['host_product', 'wrong_package', 'aliases', 'wrong_path', 'unknown_local', 'cycle', 'macro']:
            with self.subTest(change=change):
                candidate = copy.deepcopy(model)
                if change == 'host_product': candidate['targets'][0]['dependencies'][0]['product'][0] = 'CascadeRuntime'
                if change == 'wrong_package': candidate['targets'][0]['dependencies'][0]['product'][1] = 'Other'
                if change == 'aliases': candidate['targets'][0]['dependencies'][0]['product'][2] = {'CascadeAddonSDK': 'Other'}
                if change == 'wrong_path': candidate['dependencies'][0]['fileSystem'][0]['path'] = str(self.root / 'other')
                if change == 'unknown_local': candidate['targets'][0]['dependencies'] = [local('HostPrivate')]
                if change == 'cycle': candidate['targets'][0]['dependencies'].append(local('ProviderTests'))
                if change == 'macro': candidate['targets'][0]['type'] = 'macro'
                with self.assertRaises(checker.BoundaryError):
                    checker.validate_package(candidate, self.root, self.root, sdk=False)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name).resolve()

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, contents='import Foundation\n'):
        p = self.root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(contents)
        return p

    def test_exact_described_sources_and_explicit_root_target_are_contained(self):
        swift = self.write('Sources/Provider/Provider.swift')
        self.write('Sources/Provider/Ignored/Host.swift', 'import CascadeRuntime\n')
        self.write('Sources/Provider/Fixtures/Example.swift', 'not source')
        model = dict(target('Provider'), path='Sources/Provider', sources=['Provider.swift'])
        self.assertEqual(checker.source_files(model, self.root), [swift])
        test_file = self.write('Tests/ProviderTests/Test.swift')
        root_target = target('ProviderTests', kind='test')
        root_target.update(path='.', sources=['Tests/ProviderTests/Test.swift'])
        self.assertEqual(checker.source_files(root_target, self.root), [test_file])

    def test_missing_escaping_and_symlink_sources_do_not_silently_pass(self):
        valid = self.write('Sources/Provider/Provider.swift')
        model = dict(target('Provider'), path='Sources/Provider', sources=['Provider.swift'])
        for sources in [['missing.swift'], ['../../../outside.swift'], []]:
            with self.subTest(sources=sources):
                candidate = dict(model, sources=sources)
                with self.assertRaises(checker.BoundaryError): checker.source_files(candidate, self.root)
        inside = self.root / 'Sources/Provider/Inside.swift'; inside.symlink_to(valid)
        model['sources'].append('Inside.swift')
        self.assertEqual(len(checker.source_files(model, self.root)), 1)
        outside = self.root / 'Sources/Provider/Outside.swift'; outside.symlink_to('/private/tmp/not-sdk-source.swift')
        model['sources'].append('Outside.swift')
        with self.assertRaises(checker.BoundaryError): checker.source_files(model, self.root)


class ImportPolicyTests(unittest.TestCase):
    path = '/private/tmp/boundary-fixture.swift'

    def report(self, module, attributes=()):
        return [{'path': self.path, 'error': None,
                 'imports': [{'module': module, 'attributes': list(attributes), 'line': 3, 'column': 1}]}]

    def check(self, reports):
        return checker.inspect_imports(reports, [self.path], {'CascadeRuntime', 'CascadeKit', 'CascadeAddonTool'})

    def test_host_imports_and_nonpublic_sdk_access_are_rejected(self):
        for module, attrs in [('CascadeRuntime', []), ('CascadeKit', ['_exported']),
                              ('CascadeAddonSDK', ['testable']), ('CascadeContracts', ['_spi']),
                              ('CascadePresentation', ['`testable`'])]:
            with self.subTest(module=module, attrs=attrs):
                violations = self.check(self.report(module, attrs))
                self.assertTrue(violations)
                self.assertIn(self.path + ':3:', violations[0])

    def test_example_local_testable_and_public_api_are_allowed(self):
        for module, attrs in [('Provider', ['testable']), ('Foundation', []),
                              ('CascadeAddonSDK', []), ('CascadePresentation', ['_exported'])]:
            contexts = {self.path: [{'example': True, 'type': 'test', 'local_modules': {'Provider', 'ProviderTests'}}]}
            self.assertEqual(checker.inspect_imports(self.report(module, attrs), [self.path], {'CascadeRuntime'}, contexts), [])

    def test_local_testable_requires_own_example_test_target_for_every_file_owner(self):
        valid = {'example': True, 'type': 'test', 'local_modules': {'Provider', 'ProviderTests'}}
        cases = [None, {}, {self.path: [dict(valid, type='regular')]},
                 {self.path: [dict(valid, type='executable')]},
                 {self.path: [dict(valid, example=False)]},
                 {self.path: [dict(valid, local_modules={'Other'})]},
                 {self.path: [valid, dict(valid, type='regular')]}]
        for contexts in cases:
            with self.subTest(contexts=contexts):
                self.assertTrue(checker.inspect_imports(self.report('Provider', ['testable']),
                                                       [self.path], {'CascadeRuntime'}, contexts))

    def test_missing_duplicate_or_corrupt_scanner_results_never_pass(self):
        valid = self.report('Foundation')
        for reports in [[], valid + valid, [{'path': self.path, 'imports': []}],
                        [{'path': self.path, 'error': None, 'imports': [{'module': 'Foundation', 'attributes': [], 'line': 0, 'column': 1}]}]]:
            with self.subTest(reports=reports):
                with self.assertRaises(checker.BoundaryError): self.check(reports)
        self.assertTrue(self.check([{'path': self.path, 'error': 'Swift syntax could not be parsed', 'imports': []}]))


@unittest.skipUnless(os.environ.get('CASCADE_BOUNDARY_SCANNER'), 'compiled parser scanner not supplied')
class ParserTests(unittest.TestCase):
    def scan(self, source=None, missing=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Fixture.swift'
            if not missing:
                path.write_text(source)
            result = subprocess.run([os.environ['CASCADE_BOUNDARY_SCANNER']],
                                    input=json.dumps([str(path)]), text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            reports = json.loads(result.stdout)
            self.assertEqual(len(reports), 1)
            self.assertEqual(reports[0]['path'], str(path))
            return reports[0]

    def test_real_parser_sees_typed_conditional_attributed_and_escaped_imports(self):
        report = self.scan('''#if DEBUG
@testable import CascadeRuntime
#else
import struct CascadeRuntime.ResourcePolicy
#endif
@_spi(Internal) import CascadeAddonSDK
import `CascadeKit`
''')
        self.assertIsNone(report['error'])
        self.assertEqual([x['module'] for x in report['imports']],
                         ['CascadeRuntime', 'CascadeRuntime', 'CascadeAddonSDK', 'CascadeKit'])
        self.assertEqual(report['imports'][0]['attributes'], ['testable'])
        self.assertEqual(report['imports'][2]['attributes'], ['_spi'])
        self.assertEqual([x['line'] for x in report['imports']], [2, 4, 6, 7])

    def test_comments_and_strings_are_not_imports(self):
        report = self.scan('''// import CascadeRuntime
/* outer /* import CascadeKit */ still comment */
let raw = #"import CascadeRuntime"#
let multiline = """
import CascadeRuntime
"""
import Foundation
''')
        self.assertIsNone(report['error'])
        self.assertEqual([x['module'] for x in report['imports']], ['Foundation'])

    def test_malformed_swift_and_unreadable_files_fail_closed(self):
        self.assertIsNotNone(self.scan('import {')['error'])
        self.assertIsNotNone(self.scan(missing=True)['error'])


@unittest.skipUnless(os.environ.get('CASCADE_BOUNDARY_FIXTURE_ROOT') and os.environ.get('CASCADE_BOUNDARY_SCANNER'),
                     'immutable package fixture and scanner not supplied')
class CommandTests(unittest.TestCase):
    def test_swiftpm_ignored_files_are_not_audited_as_compiled_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            source_root = root / 'Examples/StandaloneFocus/Sources/StandaloneFocusProvider'
            for name in ['.Hidden.swift', '.Hidden/Host.swift', 'Fixture.xcodeproj/Host.swift',
                         'Fixture.xcworkspace/Host.swift', 'Fixture.playground/Host.swift']:
                source = source_root / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text('import CascadeRuntime\nimport {\n')
            for name in ['Ignored/Host.swift', 'Fixtures/Host.swift']:
                source = source_root / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text('import CascadeRuntime\nimport {\n')
            manifest = root / 'Examples/StandaloneFocus/Package.swift'
            contents = manifest.read_text()
            before = '                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),\n            ]\n        ),'
            after = '                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),\n            ],\n            exclude: ["Ignored"],\n            resources: [.copy("Fixtures")]\n        ),'
            self.assertIn(before, contents)
            manifest.write_text(contents.replace(before, after, 1))
            result = subprocess.run(['python3', str(SCRIPT), '--root', str(root),
                                     '--scanner', os.environ['CASCADE_BOUNDARY_SCANNER'],
                                     '--cache-root', str(Path(directory) / 'cache'), '--json',
                                     '--swift', os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift')],
                                    text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertFalse(any('.Hidden' in path or 'Fixture.xc' in path or 'Fixture.playground' in path
                                 or '/Ignored/' in path or '/Fixtures/' in path
                                 for path in report['input_sha256']))

    def test_selected_version_specific_manifest_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            package = root / 'Examples/StandaloneFocus'
            swift = os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift')
            version = subprocess.run([swift, '--version'], text=True, capture_output=True, check=True).stdout
            import re
            major_minor = re.search(r'Swift version (\d+\.\d+)', version).group(1)
            variant = package / f'Package@swift-{major_minor}.swift'
            variant.write_text((package / 'Package.swift').read_text().replace('name: "StandaloneFocus",', 'name: "SelectedVariant",'))
            model, _ = checker.dump_package(swift, package, root / 'CascadeKit', Path(directory) / 'probe-cache')
            self.assertEqual(model['name'], 'SelectedVariant', 'The installed SwiftPM must actually select this fixture manifest')
            result = subprocess.run(['python3', str(SCRIPT), '--root', str(root),
                                     '--scanner', os.environ['CASCADE_BOUNDARY_SCANNER'],
                                     '--cache-root', str(Path(directory) / 'audit-cache'), '--swift', swift],
                                    text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('Version-specific manifests are unsupported', result.stderr)

    def test_manifest_changes_during_audit_cannot_receive_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            package = root / 'Examples/StandaloneFocus'
            base = package / 'Package.swift'
            original = base.read_text()
            variant = package / 'Package@swift-6.swift'
            for kind in ['base_contents', 'versioned_addition']:
                with self.subTest(kind=kind):
                    def mutate(*args):
                        if kind == 'base_contents': base.write_text(original + '\n// changed during audit\n')
                        else: variant.write_text(original)
                        return []
                    with mock.patch.object(checker, 'inspect_imports', side_effect=mutate) as inspection:
                        with self.assertRaisesRegex(checker.BoundaryError, 'Manifest changed|Version-specific manifests'):
                            checker.audit(root.resolve(), os.environ['CASCADE_BOUNDARY_SCANNER'],
                                          os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift'), Path(directory) / 'cache')
                        inspection.assert_called_once()
                    base.write_text(original)
                    variant.unlink(missing_ok=True)

    def test_app_host_imports_are_rejected_by_actual_parser_and_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            source = root / 'Examples/StandaloneFocus/Sources/StandaloneFocusProvider/FocusSession.swift'
            original = source.read_text()
            source.write_text(original + '''\n#if CASCADE_BOUNDARY_INACTIVE_TEST
import Cascade
import struct Cascade.PrivateState
@testable import Cascade
@_spi(Internal) import Cascade
#endif
''')
            command = ['python3', str(SCRIPT), '--root', str(root),
                       '--scanner', os.environ['CASCADE_BOUNDARY_SCANNER'],
                       '--cache-root', str(Path(directory) / 'cache'),
                       '--swift', os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift')]
            result = subprocess.run(command, text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(result.stderr.count('private host import Cascade\n'), 4, result.stderr)
            source.write_text(original + '\n@testable import StandaloneFocusProvider\n')
            result = subprocess.run(command, text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('@testable requires an own-package example test target', result.stderr)

    def test_actual_command_accepts_public_sources_and_rejects_malformed_swift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            command = ['python3', str(SCRIPT), '--root', str(root),
                       '--scanner', os.environ['CASCADE_BOUNDARY_SCANNER'],
                       '--cache-root', str(Path(directory) / 'cache'), '--json',
                       '--swift', os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift')]
            result = subprocess.run(command, text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['status'], 'PASS')
            self.assertEqual(report['packages'], 4)
            self.assertGreater(report['swift_files'], 0)
            self.assertEqual(len(report['input_sha256']), report['swift_files'] + 4)
            source = root / 'Examples/StandaloneFocus/Sources/StandaloneFocusProvider/FocusSession.swift'
            source.write_text(source.read_text() + '\nimport {\n')
            result = subprocess.run(command, text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('Swift syntax could not be parsed', result.stderr)

    def test_actual_command_rejects_private_import_in_source_example(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'Fixture Repo'
            shutil.copytree(os.environ['CASCADE_BOUNDARY_FIXTURE_ROOT'], root)
            source = root / 'Examples/StandaloneFocus/Sources/StandaloneFocusProvider/FocusSession.swift'
            source.write_text(source.read_text() + '\nimport CascadeRuntime\n')
            result = subprocess.run(['python3', str(SCRIPT), '--root', str(root),
                                     '--scanner', os.environ['CASCADE_BOUNDARY_SCANNER'],
                                     '--cache-root', str(Path(directory) / 'cache'),
                                     '--swift', os.environ.get('CASCADE_BOUNDARY_SWIFT', 'swift')],
                                    text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('private host import CascadeRuntime', result.stderr)


if __name__ == '__main__':
    unittest.main()
