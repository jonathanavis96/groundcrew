VAULT + MEMORY SYNC — When the Obsidian vault is in scope, the canonical rules are the vault's own root `CLAUDE.md` and `_Agent_System/VAULT_AGENT_RULES.md`. Read them before writing; do not reconstruct the note model from memory.

- The project hub is a short current-state dashboard, not a diary. Replace stale state instead of appending dated history.
- Put executable actions in the project's task note. Waiting and Backlog items are plain bullets, not unchecked tasks.
- Put shipped history in the project changelog and durable implementation detail in the technical note.
- Do not copy the same task or state into the hub, the task note and memory. Link to the canonical detail.
- Before ending a vault-changing session, reconcile touched tasks, update current truth, and run the baseline-aware lint command.
- Do not auto-migrate large legacy notes or uncertain items. Preserve them and propose a focused migration.
- Memory is for behavioural rules and thin pointers, not duplicated live project state. If memory conflicts with the vault, trust the vault.
