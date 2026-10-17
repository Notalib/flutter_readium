const { execFileSync } = require('node:child_process');

function isAncestor(base, head) {
  if (![base, head].every((sha) => /^[a-f0-9]{40}$/.test(sha))) return false;
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', base, head], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

module.exports = async ({ github, context, core, ancestor = isAncestor }) => {
  const pr = context.payload.pull_request;
  const head = pr ? pr.head.sha : context.sha;
  const fallback = {
    base: pr ? pr.base.sha : head,
    ref: head,
    force: !pr,
    reason: pr ? 'Checking the full PR diff.' : 'No successful baseline; running all platforms.',
  };
  if (context.eventName === 'workflow_dispatch' || context.runAttempt > 1) {
    return { ...fallback, force: true, reason: 'Manual dispatch or rerun: running all platforms.' };
  }

  try {
    const { data } = await github.rest.actions.listWorkflowRuns({
      ...context.repo,
      workflow_id: 'ci.yml',
      event: context.eventName,
      branch: pr ? pr.head.ref : context.ref.replace('refs/heads/', ''),
      status: 'success',
      per_page: 20,
    });
    const repositoryId = pr ? pr.head.repo.id : context.payload.repository.id;
    const candidates = data.workflow_runs.filter((run) =>
      run.id !== context.runId && run.conclusion === 'success' &&
      run.head_repository?.id === repositoryId && ancestor(run.head_sha, head),
    ).slice(0, 5);

    for (const run of candidates) {
      if (pr) {
        // A PR head SHA alone does not identify the base used by its test merge.
        const { data: artifacts } = await github.rest.actions.listWorkflowRunArtifacts({
          ...context.repo, run_id: run.id, per_page: 100,
        });
        const marker = `ci-baseline-v1-pr-${pr.number}-base-${pr.base.sha}`;
        if (!artifacts.artifacts.some((artifact) => artifact.name === marker && !artifact.expired)) continue;
      }
      return {
        base: run.head_sha, ref: head, force: false,
        reason: `Checking platform changes since successful [CI run](${run.html_url}).`,
      };
    }
  } catch (error) {
    core.warning(`Could not verify a successful CI baseline: ${error.message}`);
  }
  return fallback;
};
