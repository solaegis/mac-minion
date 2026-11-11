# Self-hosted CI runner (atreides)

Trusted CI (`push` to `main` and same-repo pull requests) runs `swift test` on a
repo-scoped GitHub Actions runner on **atreides**. Fork PRs stay on GitHub-hosted
`macos-26` so untrusted workflow code never runs on the Mac. Release and Docs
workflows stay on GitHub-hosted runners.

## Layout

| Item | Path |
|------|------|
| Runner home | `~/actions-runner/mac-minion` |
| LaunchAgent | `~/Library/LaunchAgents/actions.runner.solaegis-mac-minion.atreides.plist` |
| Logs | `~/Library/Logs/actions.runner.solaegis-mac-minion.atreides/` |
| Labels | `self-hosted`, `macOS`, `ARM64` |
| Runner name | `atreides` |

## Service control

From `~/actions-runner/mac-minion`:

```bash
./svc.sh status
./svc.sh stop
./svc.sh start
```

GitHub UI: **Settings → Actions → Runners**. API check:

```bash
gh api repos/solaegis/mac-minion/actions/runners --jq '.runners[] | {name, status, busy}'
```

If the Mac sleeps, jobs wait until it wakes. Use `awake` when overnight CI matters.

## Re-register after revoke

1. Stop and uninstall the service: `./svc.sh stop && ./svc.sh uninstall`
2. Remove local config: `./config.sh remove` (needs a remove token from the UI, or delete the runner in GitHub first)
3. Get a new registration token:

   ```bash
   gh api -X POST repos/solaegis/mac-minion/actions/runners/registration-token --jq .token
   ```

4. Configure and start again:

   ```bash
   ./config.sh --url https://github.com/solaegis/mac-minion \
     --token <registration-token> --name atreides \
     --labels macOS,ARM64 --work _work --unattended
   ./svc.sh install && ./svc.sh start
   ```

Do not commit registration tokens or `.credentials*` under the runner home.
