"""Static public SDK/package checks. Evaluates trusted development manifests only."""

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

PUBLIC_MODULES = ('CascadeAddonSDK', 'CascadeContracts', 'CascadePresentation')
PRIVATE_HOST_MODULES = {'Cascade'}  # Xcode application target, outside the SDK package graph.


class BoundaryError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise BoundaryError(message)


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value) is not None


def contains_key(value, key):
    if isinstance(value, dict):
        return key in value or any(contains_key(child, key) for child in value.values())
    if isinstance(value, list):
        return any(contains_key(child, key) for child in value)
    return False


def validate_package(model, package_root, sdk_root, *, sdk):
    require(isinstance(model, dict) and isinstance(model.get('targets'), list), 'Malformed package target graph')
    targets = {}
    for value in model['targets']:
        require(isinstance(value, dict) and identifier(value.get('name')), 'Unsupported target name or target shape')
        name = value['name']
        require(name not in targets, f'Duplicate target: {name}')
        targets[name] = value
    require(targets, 'Package has no targets to audit')
    if sdk:
        require(set(PUBLIC_MODULES) <= targets.keys(), 'Missing public SDK target')
        products = model.get('products')
        require(isinstance(products, list) and all(isinstance(p, dict) for p in products), 'Malformed SDK products')
        for name in PUBLIC_MODULES:
            matches = [p for p in products if p.get('name') == name]
            require(len(matches) == 1 and matches[0].get('targets') == [name]
                    and isinstance(matches[0].get('type'), dict)
                    and set(matches[0]['type']) == {'library'}, f'{name}: public product must expose only its expected target')
        selected = {name: targets[name] for name in PUBLIC_MODULES}
        sdk_aliases = set()
    else:
        dependencies = model.get('dependencies')
        require(isinstance(dependencies, list) and len(dependencies) == 1, 'Example must declare exactly one local SDK package')
        package = dependencies[0]
        require(isinstance(package, dict) and set(package) == {'fileSystem'}
                and isinstance(package['fileSystem'], list) and len(package['fileSystem']) == 1,
                'Example SDK dependency must be an explicit local package')
        package = package['fileSystem'][0]
        require(isinstance(package, dict) and isinstance(package.get('path'), str), 'Malformed local SDK dependency')
        require(Path(package['path']).is_absolute() and Path(package['path']).resolve() == Path(sdk_root).resolve(),
                'Example package path does not match the selected public SDK')
        sdk_aliases = {x for x in [package.get('identity'), package.get('nameForTargetDependencyResolutionOnly')] if isinstance(x, str) and x}
        require(sdk_aliases, 'Missing SDK package identity')
        require(not (set(PUBLIC_MODULES) & targets.keys()), 'Example target shadows a public SDK module')
        selected = targets
    graph = {}
    for name, value in selected.items():
        require(value.get('type') in ({'regular'} if sdk else {'regular', 'executable', 'test'}),
                f'{name}: unsupported target type in source-only SDK/examples')
        plugins = value.get('pluginUsages', [])
        require(plugins is None or isinstance(plugins, list) and not plugins, f'{name}: plugin generation is outside the audited source profile')
        settings = value.get('settings', [])
        require(isinstance(settings, list) and not contains_key(settings, 'unsafeFlags'), f'{name}: unsafe build settings are forbidden')
        dependencies = value.get('dependencies')
        require(isinstance(dependencies, list), f'{name}: malformed target dependencies')
        graph[name] = []
        for dependency in dependencies:
            require(isinstance(dependency, dict) and len(dependency) == 1, f'{name}: malformed dependency')
            kind, payload = next(iter(dependency.items()))
            require(isinstance(payload, list), f'{name}: malformed dependency payload')
            if kind in {'byName', 'target'}:
                require(len(payload) == 2 and identifier(payload[0]), f'{name}: unsupported target dependency')
                require(payload[0] in selected, f'{name}: dependency {payload[0]} is outside the public SDK/example targets')
                graph[name].append(payload[0])
            elif kind == 'product':
                require(not sdk and len(payload) == 4 and payload[0] in PUBLIC_MODULES
                        and payload[1] in sdk_aliases and payload[2] is None,
                        f'{name}: product is not an unaliased public SDK dependency')
            else:
                raise BoundaryError(f'{name}: unsupported dependency kind {kind}')
    visited, active = set(), set()

    def visit(name):
        require(name not in active, f'Dependency cycle at {name}')
        if name in visited:
            return
        active.add(name)
        for child in graph[name]:
            visit(child)
        active.remove(name)
        visited.add(name)

    for name in graph:
        visit(name)
    return [selected[name] for name in sorted(selected)]


def source_files(target, package_root):
    """Validate the exact source list selected by the installed SwiftPM describe."""
    package_root = Path(package_root).resolve()

    def relative(base, value):
        require(isinstance(value, str) and value and not Path(value).is_absolute()
                and '..' not in Path(value).parts, f"{target['name']}: source path escapes package")
        path = base / value
        require(path.resolve().is_relative_to(package_root), f"{target['name']}: symlink escapes package")
        return path

    base = relative(package_root, target.get('path'))
    require(base.is_dir(), f"{target['name']}: missing source directory {base}")
    sources = target.get('sources')
    require(isinstance(sources, list) and sources, f"{target['name']}: no explicit SwiftPM source list")
    files = set()
    for value in sources:
        path = relative(base, value)
        require(path.is_file() and path.suffix == '.swift', f"{target['name']}: missing or unsupported Swift source {path}")
        files.add(path.resolve())
    return sorted(files)


def source_targets(description, selected, package_root):
    require(isinstance(description, dict) and isinstance(description.get('targets'), list),
            'Malformed SwiftPM source description')
    targets = {}
    for target in description['targets']:
        require(isinstance(target, dict) and identifier(target.get('name'))
                and target['name'] not in targets, 'Duplicate or malformed described target')
        targets[target['name']] = target
    result = {}
    for target in selected:
        name = target['name']
        require(name in targets and targets[name].get('module_type') == 'SwiftTarget',
                f'{name}: missing or unsupported described Swift target')
        described = targets[name]
        default = ('Tests' if target['type'] == 'test' else 'Sources') + '/' + name
        require(isinstance(described.get('path'), str)
                and (package_root / described['path']).resolve() == (package_root / target.get('path', default)).resolve(),
                f'{name}: manifest and described target paths disagree')
        result[name] = source_files(described, package_root)
    return result


def inspect_imports(reports, files, private_modules, file_contexts=None):
    expected = {str(path) for path in files}
    require(expected and isinstance(reports, list), 'Scanner received no auditable files or returned malformed output')
    seen, violations = set(), []
    for report in reports:
        require(isinstance(report, dict) and set(report) == {'path', 'error', 'imports'}, 'Malformed scanner file report')
        path = report['path']
        require(isinstance(path, str) and path in expected and path not in seen, 'Scanner file coverage mismatch')
        seen.add(path)
        require(report['error'] is None or isinstance(report['error'], str) and report['error'], 'Malformed scanner error')
        require(isinstance(report['imports'], list), 'Malformed scanner import list')
        if report['error'] is not None:
            violations.append(f"{path}: {report['error']}")
        for value in report['imports']:
            require(isinstance(value, dict) and set(value) == {'module', 'attributes', 'line', 'column'}, 'Malformed import record')
            module, attributes = value['module'], value['attributes']
            require(isinstance(module, str) and module and isinstance(attributes, list)
                    and all(isinstance(a, str) for a in attributes)
                    and type(value['line']) is int and value['line'] > 0
                    and type(value['column']) is int and value['column'] > 0, 'Malformed import location or identity')
            location = f"{path}:{value['line']}:{value['column']}"
            if module in private_modules:
                violations.append(f'{location}: private host import {module}')
            normalized = {a.replace('`', '').split('.')[-1] for a in attributes}
            if module in PUBLIC_MODULES and normalized & {'testable', '_spi'}:
                violations.append(f'{location}: nonpublic SDK access through import {module}')
            elif 'testable' in normalized:
                contexts = (file_contexts or {}).get(path, [])
                if not contexts or not all(context['example'] and context['type'] == 'test'
                                           and module in context['local_modules'] for context in contexts):
                    violations.append(f'{location}: @testable requires an own-package example test target: {module}')
    require(seen == expected, 'Scanner omitted source files')
    return violations


def run(command, *, environment=None, stdin=None):
    result = subprocess.run(command, input=stdin, text=True, capture_output=True,
                            env=environment, timeout=120)
    require(result.returncode == 0,
            f"Command failed ({result.returncode}): {command[0]}\n{result.stderr.strip()}")
    return result.stdout


def dump_package(swift, package, sdk_root, cache, *, describe=False):
    cache.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, CASCADE_SDK_PATH=str(sdk_root),
                       CLANG_MODULE_CACHE_PATH=str(cache / 'modules'),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(cache / 'manifest'))
    command = [swift, 'package', '--package-path', str(package),
               '--scratch-path', str(cache / 'build'), '--cache-path', str(cache / 'swiftpm'),
               '--config-path', str(cache / 'config'), '--security-path', str(cache / 'security'),
               '--disable-sandbox'] + (['describe', '--type', 'json'] if describe else ['dump-package'])
    return json.loads(run(command, environment=environment)), command


def manifest_inputs(packages, root):
    manifests = {}
    for package in packages:
        require(package.resolve().is_relative_to(root), f'Package escapes repository: {package}')
        require(not list(package.glob('Package@swift-*.swift')),
                f'Version-specific manifests are unsupported by this source profile: {package}')
        manifest = package / 'Package.swift'
        require(manifest.is_file() and manifest.resolve().is_relative_to(package.resolve()),
                f'Missing or escaping trusted package manifest: {manifest}')
        manifests[str(manifest)] = hashlib.sha256(manifest.read_bytes()).hexdigest()
    return manifests


def audit(root, scanner, swift, cache):
    sdk_root = root / 'CascadeKit'
    packages = [sdk_root, root / 'Examples/StandaloneFocus', root / 'Examples/ServiceConsumer',
                root / 'Examples/StandaloneClock']
    manifests = manifest_inputs(packages, root)
    models, commands = [], []
    for index, package in enumerate(packages):
        model, command = dump_package(swift, package, sdk_root, cache / str(index))
        models.append(model)
        commands.append(command)
    selected = validate_package(models[0], sdk_root, sdk_root, sdk=True)
    private_modules = ({value['name'] for value in models[0]['targets']} - set(PUBLIC_MODULES)) | PRIVATE_HOST_MODULES
    targets = [(sdk_root, target, {'example': False, 'type': target['type'], 'local_modules': set()})
               for target in selected]
    for package, model in zip(packages[1:], models[1:]):
        selected = validate_package(model, package, sdk_root, sdk=False)
        require(not (private_modules & {value['name'] for value in selected}),
                f'{package.name}: example target shadows a private host module')
        local_modules = {target['name'] for target in selected}
        targets.extend((package, target, {'example': True, 'type': target['type'], 'local_modules': local_modules})
                       for target in selected)
    file_contexts, source_commands = {}, []
    for index, package in enumerate(packages):
        described, command = dump_package(swift, package, sdk_root, cache / str(index), describe=True)
        source_commands.append(command)
        selected = [(target, context) for owner, target, context in targets if owner == package]
        sources = source_targets(described, [target for target, _ in selected], package)
        for target, context in selected:
            for path in sources[target['name']]:
                file_contexts.setdefault(str(path), []).append(context)
    files = [Path(path) for path in sorted(file_contexts)]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    reports = json.loads(run([scanner], stdin=json.dumps([str(path) for path in files])))
    violations = inspect_imports(reports, files, private_modules, file_contexts)
    require(manifest_inputs(packages, root) == manifests, 'Manifest changed during audit')
    for path, digest in {**manifests, **before}.items():
        require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest,
                f'Input changed during audit: {path}')
    require(not violations, '\n'.join(violations))
    return {'status': 'PASS', 'packages': len(packages), 'targets': len(targets),
            'swift_files': len(files), 'imports': sum(len(report['imports']) for report in reports),
            'swift_version': run([swift, '--version']).strip(),
            'developer_dir': os.environ.get('DEVELOPER_DIR'), 'manifest_commands': commands,
            'source_commands': source_commands,
            'input_sha256': {**manifests, **before},
            'scope': 'Static source imports and target graph for these trusted manifest evaluations; '
                     'not macro expansion, alternate manifest environments, dynamic loading, or native runtime parity.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--scanner', required=True, help='Matching compiled SwiftParser helper')
    parser.add_argument('--swift', default='swift')
    parser.add_argument('--cache-root', required=True, type=Path, help='Private temporary cache directory')
    parser.add_argument('--json', action='store_true', help='Include exact input hashes and toolchain scope')
    args = parser.parse_args()
    try:
        result = audit(args.root.resolve(), args.scanner, args.swift, args.cache_root.resolve())
    except (BoundaryError, OSError, ValueError, subprocess.TimeoutExpired, RecursionError) as error:
        print(f'Addon boundary check failed: {error}', file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"PASS: {result['packages']} packages, {result['targets']} targets, "
              f"{result['swift_files']} Swift files, {result['imports']} imports")
        print(result['scope'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
