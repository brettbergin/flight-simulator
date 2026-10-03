# Contributing

Read [the project plan](docs/README.md), [agent workflow](docs/agent-operations.md), and [delivery policy](docs/delivery.md). The implementation plan awaits the owner's review. Work from a ready issue after that gate; coordinate interface changes before starting consumers.

Use an isolated branch or worktree for each task. Keep PRs reviewable and attach the evidence requested by the issue. Aircraft realism claims require the exact variant and reference provenance. A pilot's qualitative feedback complements measured validation.

For foundation work, Node.js 20 or newer is sufficient. No package installation is needed:

```powershell
node tools/check-docs.mjs
node tools/sync-github.mjs
```

The second command previews the checked-in backlog without contacting GitHub. `--apply` makes explicit GitHub changes using your authenticated `gh` CLI; see [the backlog guide](docs/backlog.md). Never commit `.local/` publication state or private flight logs.

Git signing remains the contributor's normal choice. For owner-dispatched agent work on this project, the owner authorized per-command unsigned commits when GPG signing requires interaction. Use `git -c commit.gpgsign=false commit` when needed; do not change global Git settings.

Source contributions use the repository MIT license. Third-party software, data, artwork, aircraft documents, and trademarks retain their respective terms. Do not assume an aircraft document available online can be redistributed.
