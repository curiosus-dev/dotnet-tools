#!/usr/bin/env python3
"""Applies or checks repository settings described in ./settings for every repository in settings/repositories.json.

    scripts/repo-settings.py check [repository...]   exit code 1 when a setting differs from ./settings
    scripts/repo-settings.py apply [repository...]   makes repositories match ./settings (needs repository admin rights)

Uses the gh CLI and its authentication (GH_TOKEN on CI).
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'settings'
GITHUB_ACTIONS_APP_ID = 15368


def load(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def gh(method, path, body=None, allow_missing=False):
    args = ['gh', 'api', '--method', method, path, '-H', 'X-GitHub-Api-Version: 2022-11-28']
    if body is not None:
        args += ['--input', '-']
    result = subprocess.run(args, input=json.dumps(body) if body is not None else None, capture_output=True, text=True)
    if result.returncode != 0:
        if allow_missing and '"status":"404"' in result.stdout.replace(' ', ''):
            return None
        raise RuntimeError(f'{method} {path}: {result.stdout.strip() or result.stderr.strip()}')
    return json.loads(result.stdout) if result.stdout.strip() else None


def path_exists(path):
    result = subprocess.run(['gh', 'api', path, '--silent'], capture_output=True, text=True)
    return result.returncode == 0


def subset_diff(expected, actual, where=''):
    """Differences of expected values that are missing or different in actual (extra actual keys are ignored)."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f'{where}: expected an object, got {actual!r}']
        diffs = []
        for key, value in expected.items():
            diffs += subset_diff(value, actual.get(key), f'{where}.{key}' if where else key)
        return diffs
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            return [f'{where}: expected {expected!r}, got {actual!r}']
        diffs = []
        for index, (e, a) in enumerate(zip(sorted_items(expected), sorted_items(actual))):
            diffs += subset_diff(e, a, f'{where}[{index}]')
        return diffs
    return [] if expected == actual else [f'{where}: expected {expected!r}, got {actual!r}']


def sorted_items(items):
    return sorted(items, key=lambda x: json.dumps(x.get('type', x) if isinstance(x, dict) else x, sort_keys=True))


def rulesets_for(config):
    checks = [{'context': name, 'integration_id': GITHUB_ACTIONS_APP_ID} for name in config['required_checks']]
    for path in sorted((ROOT / 'rulesets').glob('*.json')):
        ruleset = json.loads(path.read_text(encoding='utf-8'))
        rules = []
        for rule in ruleset['rules']:
            if rule['type'] == 'required_status_checks':
                if not checks:
                    continue
                rule = json.loads(json.dumps(rule))
                rule['parameters']['required_status_checks'] = checks
            rules.append(rule)
        ruleset['rules'] = rules
        yield ruleset


def process(owner, name, config, apply):
    repo = f'repos/{owner}/{name}'
    diffs = []

    def section(title, expected, actual, update):
        found = subset_diff(expected, actual)
        if found and apply:
            update()
        diffs.extend(f'{title}: {d}' for d in found)

    repository = load('repository.json')
    section('repository', repository, gh('GET', repo), lambda: gh('PATCH', repo, repository))

    for endpoint in ('vulnerability-alerts', 'automated-security-fixes', 'private-vulnerability-reporting'):
        actual = gh('GET', f'{repo}/{endpoint}', allow_missing=True)
        enabled = actual.get('enabled', True) if isinstance(actual, dict) else path_exists(f'{repo}/{endpoint}')
        section(endpoint, True, enabled, lambda e=endpoint: gh('PUT', f'{repo}/{e}'))

    code_scanning = gh('GET', f'{repo}/code-scanning/default-setup')
    section('code-scanning', {'state': 'configured'}, code_scanning,
            lambda: gh('PATCH', f'{repo}/code-scanning/default-setup', {'state': 'configured'}))

    actions = load('actions.json')
    section('actions', actions['permissions'], gh('GET', f'{repo}/actions/permissions'),
            lambda: gh('PUT', f'{repo}/actions/permissions', actions['permissions']))
    try:
        selected = gh('GET', f'{repo}/actions/permissions/selected-actions')
    except RuntimeError:
        selected = {}  # 409 while all actions are allowed: there is no list yet
    section('actions.selected', actions['selected_actions'], selected,
            lambda: gh('PUT', f'{repo}/actions/permissions/selected-actions', actions['selected_actions']))
    section('actions.workflow', actions['workflow'], gh('GET', f'{repo}/actions/permissions/workflow'),
            lambda: gh('PUT', f'{repo}/actions/permissions/workflow', actions['workflow']))
    section('actions.fork-approval', actions['fork_pr_contributor_approval'],
            gh('GET', f'{repo}/actions/permissions/fork-pr-contributor-approval'),
            lambda: gh('PUT', f'{repo}/actions/permissions/fork-pr-contributor-approval',
                       actions['fork_pr_contributor_approval']))

    # Before environments: enabling Pages creates the github-pages environment.
    if config.get('docs'):
        pages = {'build_type': 'workflow'}
        actual_pages = gh('GET', f'{repo}/pages', allow_missing=True)
        if actual_pages is None:
            diffs.append('pages: disabled')
            if apply:
                gh('POST', f'{repo}/pages', pages)
        else:
            section('pages', pages, actual_pages, lambda: gh('PUT', f'{repo}/pages', pages))

    environments = load('environments.json')
    for env_name in config.get('environments', []):
        env = environments[env_name]
        env_path = f'{repo}/environments/{env_name}'
        policy = {'deployment_branch_policy': env['deployment_branch_policy']}
        actual_env = gh('GET', env_path, allow_missing=True)
        if actual_env is None:
            diffs.append(f'environment {env_name}: missing')
            if apply:
                gh('PUT', env_path, policy)
        else:
            section(f'environment {env_name}', policy, actual_env, lambda p=env_path, b=policy: gh('PUT', p, b))
        # A new environment has no branch policies yet, so they are compared after it is created.
        actual = (gh('GET', f'{env_path}/deployment-branch-policies', allow_missing=True) or {}).get('branch_policies', [])
        expected_policies = {(x['name'], x['type']) for x in env['branch_policies']}
        actual_policies = {(x['name'], x.get('type', 'branch')): x['id'] for x in actual}
        for name, kind in sorted(expected_policies - actual_policies.keys()):
            diffs.append(f'environment {env_name}: branch policy {kind} {name} missing')
            if apply:
                gh('POST', f'{env_path}/deployment-branch-policies', {'name': name, 'type': kind})
        for (name, kind), policy_id in sorted(actual_policies.items()):
            if (name, kind) not in expected_policies:
                diffs.append(f'environment {env_name}: unexpected branch policy {kind} {name}')
                if apply:
                    gh('DELETE', f'{env_path}/deployment-branch-policies/{policy_id}')

    existing = {r['name']: r['id'] for r in gh('GET', f'{repo}/rulesets?includes_parents=false') or []}
    for ruleset in rulesets_for(config):
        ruleset_id = existing.get(ruleset['name'])
        if not ruleset_id:
            diffs.append(f'ruleset {ruleset["name"]}: missing')
            if apply:
                gh('POST', f'{repo}/rulesets', ruleset)
            continue
        actual = gh('GET', f'{repo}/rulesets/{ruleset_id}')
        # bypass_actors are returned only to those who can edit the ruleset, not to the read-only drift check token.
        expected = ruleset if 'bypass_actors' in actual else {k: v for k, v in ruleset.items() if k != 'bypass_actors'}
        section(f'ruleset {ruleset["name"]}', expected, actual,
                lambda r=ruleset, i=ruleset_id: gh('PUT', f'{repo}/rulesets/{i}', r))

    return diffs


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('apply', 'check'):
        sys.exit(__doc__)
    apply = sys.argv[1] == 'apply'

    config = load('repositories.json')
    names = sys.argv[2:] or list(config['repositories'])
    drift = False
    for name in names:
        try:
            diffs = process(config['owner'], name, config['repositories'][name], apply)
        except RuntimeError as error:
            print(f'✗ {name}: {error}')
            drift = True
            continue
        if not diffs:
            print(f'✓ {name}')
            continue
        drift = drift or not apply
        print(f'{"↻" if apply else "✗"} {name}' + (' (updated)' if apply else ''))
        for diff in diffs:
            print(f'    {diff}')

    if drift:
        sys.exit(1)


if __name__ == '__main__':
    main()
