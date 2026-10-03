# Copyable issue assignment prompts

Every issue in the initial 76-ticket backlog receives a separate generated GitHub comment headed **Copyable agent assignment**. Copy the complete comment into an agent with repository/GitHub access. It supplies project context, the documentation reading route, the exact task and requirements, prior dependencies, future consumers, path ownership, domain cautions, acceptance/evidence, and the build/review/merge/handoff procedure.

The initial prompts retain the owner-review gate. Their existence does not start product implementation. `PLAN-REVIEW` helps prepare the human decision, epics coordinate phase evidence, three broad work packages first split into bounded leaves, spikes prove a measured decision, and ordinary tasks deliver focused implementations. An LLM cannot replace owner or qualified pilot/instructor acceptance.

## Generate, publish and audit

```powershell
# Offline preview; renders one Markdown prompt per canonical backlog entry:
node tools/agent-prompts.mjs

# Explicit authorized GitHub comment publication/update:
node tools/agent-prompts.mjs --apply

# Read-only audit of exactly one matching current comment on every planned issue:
node tools/agent-prompts.mjs --verify
```

Node 20+ is sufficient for preview; apply/verify also require the authenticated GitHub CLI. Preview writes ignored `.local/agent-prompts/` files. The ignored atomic report `.local/agent-prompt-report.json` records actual comment URLs/IDs and comparison results. Publication discovers remote stable markers, validates the issue identity against the backlog/index and checks comment ownership before writing. Retry after interruption uses those markers to recover without creating duplicate assignments. It never changes issue state, scope/body, labels, assignees or unrelated comments.

The default CI preview is offline and carries no GitHub write credentials. Apply is reserved for an explicit publication request. Run one publisher at a time. Only comments beginning with the generated marker are managed; quoting a marker inside a work note does not make that note replaceable. When scope or requirements change, update canonical documents/backlog and issue mappings before reapplying; owned generated prompt comments may then be replaced. Keep ongoing work notes, review decisions and closure evidence in separate comments or linked reports.

## Read live evidence first

Prompts link to latest main and live issues. Agents must inspect current dependency comments/PRs, actual code/build commands and phase gate reports. Foundation PRs and the documentation release provide historical context; they do not prove a product was built. Do not copy a stale snapshot, close a prerequisite to make it appear satisfied, invent build/test successes, or implement later work simply because it is referenced.

Issue [index](issue-index.md), [phase briefs](phases/README.md), [traceability](requirements.md), and [agent operations](agent-operations.md) are the navigation spine. Future leaf tickets created after their shared contracts land need the same assignment fields; add their canonical backlog/index entries to use this publication tool.
