const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { test } = require('node:test');
const selectBaseline = require('./ci-baseline.cjs');

const base = 'a'.repeat(40);
const head = 'b'.repeat(40);
const previous = 'c'.repeat(40);

function fixture({ eventName = 'pull_request', runs, artifacts, apiError = false, ancestor = () => true } = {}) {
  const context = {
    repo: { owner: 'Notalib', repo: 'flutter_readium' },
    runId: 100, eventName, sha: head, ref: 'refs/heads/main',
    payload: { repository: { id: 1 } },
  };
  if (eventName === 'pull_request') {
    context.payload.pull_request = {
      number: 274, base: { sha: base }, head: { sha: head, ref: 'fix/example', repo: { id: 2 } },
    };
  }
  const calls = [];
  const warnings = [];
  const github = { rest: { actions: {
    listWorkflowRuns: async (args) => {
      calls.push(args);
      if (apiError) throw new Error('API unavailable');
      return { data: { workflow_runs: runs ?? [{
        id: 99, conclusion: 'success', head_sha: previous,
        head_repository: { id: eventName === 'pull_request' ? 2 : 1 },
        html_url: 'https://github.com/Notalib/flutter_readium/actions/runs/99',
      }] } };
    },
    listWorkflowRunArtifacts: async () => ({ data: { artifacts: artifacts ?? [{
      name: `ci-baseline-v1-pr-274-base-${base}`, expired: false,
    }] } }),
  } } };
  return {
    context, calls, warnings,
    run: () => selectBaseline({ github, context, core: { warning: (message) => warnings.push(message) }, ancestor }),
  };
}

test('PR updates compare against successful code tested with the same base', async () => {
  const f = fixture();
  const plan = await f.run();
  assert.equal(plan.base, previous);
  assert.equal(plan.ref, head);
  assert.equal(plan.force, false);
  assert.match(plan.reason, /actions\/runs\/99/);
  assert.equal(f.calls[0].event, 'pull_request');
  assert.equal(f.calls[0].branch, 'fix/example');
});

for (const [name, artifacts] of [
  ['changed PR base', [{ name: `ci-baseline-v1-pr-274-base-${previous}`, expired: false }]],
  ['another PR', [{ name: `ci-baseline-v1-pr-275-base-${base}`, expired: false }]],
  ['expired provenance', [{ name: `ci-baseline-v1-pr-274-base-${base}`, expired: true }]],
  ['missing provenance', []],
]) {
  test(`${name} falls back to the full PR diff`, async () => {
    const plan = await fixture({ artifacts }).run();
    assert.equal(plan.base, base);
    assert.equal(plan.force, false);
  });
}

for (const conclusion of ['failure', 'cancelled', null]) {
  test(`${conclusion} results cannot establish a successful baseline`, async () => {
    const plan = await fixture({ runs: [{
      id: 99, conclusion, head_sha: previous, head_repository: { id: 2 },
    }] }).run();
    assert.equal(plan.base, base);
  });
}

test('a same-named branch in another fork cannot provide the baseline', async () => {
  const plan = await fixture({ runs: [{
    id: 99, conclusion: 'success', head_sha: previous, head_repository: { id: 3 },
  }] }).run();
  assert.equal(plan.base, base);
});

test('rewritten history cannot reuse a non-ancestor run', async () => {
  const plan = await fixture({ ancestor: () => false }).run();
  assert.equal(plan.base, base);
});

test('the current run cannot provide its own baseline', async () => {
  const plan = await fixture({ runs: [{
    id: 100, conclusion: 'success', head_sha: head, head_repository: { id: 2 },
  }] }).run();
  assert.equal(plan.base, base);
});

test('main compares to its last successful run, covering intervening cancelled pushes', async () => {
  const f = fixture({ eventName: 'push' });
  const plan = await f.run();
  assert.equal(plan.base, previous);
  assert.equal(plan.force, false);
  assert.equal(f.calls[0].branch, 'main');
  assert.equal(f.calls[0].event, 'push');
});

test('main with no successful baseline runs every platform', async () => {
  assert.equal((await fixture({ eventName: 'push', runs: [] }).run()).force, true);
});

test('API failure preserves PR coverage and forces full coverage on main', async () => {
  const pr = fixture({ apiError: true });
  assert.equal((await pr.run()).base, base);
  assert.equal(pr.warnings.length, 1);
  assert.equal((await fixture({ eventName: 'push', apiError: true }).run()).force, true);
});

test('manual dispatch always runs all platforms without looking up a baseline', async () => {
  const f = fixture({ eventName: 'workflow_dispatch' });
  assert.equal((await f.run()).force, true);
  assert.equal(f.calls.length, 0);
});

test('rerunning a workflow requests real tests rather than result reuse', async () => {
  const f = fixture();
  f.context.runAttempt = 2;
  assert.equal((await f.run()).force, true);
  assert.equal(f.calls.length, 0);
});

test('the CI result gate accepts intentional skips and rejects detection/test failures', () => {
  const workflow = readFileSync(join(__dirname, '../workflows/ci.yml'), 'utf8');
  const gate = workflow.match(/      - name: Check required jobs\n[\s\S]*?        run: \|\n([\s\S]*)$/)[1];
  for (const [detection, results, expected] of [
    ['success', 'success,skipped,success', 0],
    ['success', 'success,skipped,failure', 1],
    ['success', 'success,cancelled,skipped', 1],
    ['failure', 'failure,skipped,skipped', 1],
    ['cancelled', 'cancelled,skipped,skipped', 1],
    ['skipped', 'skipped,skipped,skipped', 1],
  ]) {
    const result = spawnSync('bash', ['-e', '-c', gate], {
      env: { ...process.env, CHANGE_RESULT: detection, JOB_RESULTS: results },
    });
    assert.equal(result.status, expected, `${detection}: ${results}`);
  }
});

test('real Git ancestry rejects divergent commits and accepts tested ancestors', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-baseline-'));
  const cwd = process.cwd();
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' }).trim();
  try {
    git('init', '-q');
    git('config', 'user.name', 'CI test');
    git('config', 'user.email', 'ci@example.invalid');
    git('config', 'commit.gpgsign', 'false');
    writeFileSync(join(dir, 'README.md'), 'Initial documentation\n');
    git('add', '.');
    git('commit', '-qm', 'initial');
    const initial = git('rev-parse', 'HEAD');
    writeFileSync(join(dir, 'README.md'), 'Updated documentation\n');
    git('commit', '-qam', 'docs update');
    const updated = git('rev-parse', 'HEAD');
    process.chdir(dir);
    const f = fixture();
    f.context.payload.pull_request.head.sha = updated;
    const args = {
      context: f.context, core: { warning: assert.fail },
      github: { rest: { actions: {
        listWorkflowRuns: async () => ({ data: { workflow_runs: [{
          id: 99, conclusion: 'success', head_sha: initial, head_repository: { id: 2 },
        }] } }),
        listWorkflowRunArtifacts: async () => ({ data: { artifacts: [{
          name: `ci-baseline-v1-pr-274-base-${base}`, expired: false,
        }] } }),
      } } },
    };
    const plan = await selectBaseline(args);
    assert.equal(plan.base, initial);
    git('checkout', '-qb', 'divergent', initial);
    writeFileSync(join(dir, 'README.md'), 'Divergent documentation\n');
    git('commit', '-qam', 'divergent update');
    args.context.payload.pull_request.head.sha = git('rev-parse', 'HEAD');
    args.github.rest.actions.listWorkflowRuns = async () => ({ data: { workflow_runs: [{
      id: 99, conclusion: 'success', head_sha: updated, head_repository: { id: 2 },
    }] } });
    assert.equal((await selectBaseline(args)).base, base);
  } finally {
    process.chdir(cwd);
    rmSync(dir, { recursive: true, force: true });
  }
});
