# On-demand reference recipes

**The rule this file exists to enforce:** anything you need occasionally does
not belong in session-start context. Session-start context is paid for on every
single turn of every single session; a recipe you use once a fortnight is not
worth that.

So:

1. Keep the recipe **here**, under a heading that names its **trigger**.
2. Leave a **one-line pointer** in `~/.claude/CLAUDE.md`, naming the trigger and
   the one-sentence rule — never the detail.
3. **Read a section only when its trigger fires.** Never read this file whole,
   and never load it "just in case".

A good trigger is a thing that happens ("running a dev server", "an MCP server
reports connection refused"), not a topic ("networking"). If you cannot write
the trigger as an event, the recipe probably belongs in the project's own docs
instead.

Delete the two examples below once you have written your own.

---

## Dev servers — full detail (trigger: running or previewing a dev server)

_Example of the shape. Replace with your own._

Rule (the one line that lives in `CLAUDE.md`): always bind `0.0.0.0` and tell
the user the URL.

- Per-framework flags: Vite `npm run dev -- --host 0.0.0.0`;
  Next `next dev -H 0.0.0.0`; Python `python3 -m http.server <port> --bind 0.0.0.0`.
- Which address the user actually opens on their phone or another machine, and
  why that address and not a LAN one.
- Background servers: use the harness's own background flag rather than a bare
  `&`, which gets killed when the tool call returns.

---

## Screenshots and browser automation (trigger: need a screenshot, or to drive a page)

_Example of the shape. Replace with your own._

- Which browser binary this machine actually has, and its full path.
- Whether to use the Playwright MCP or launch an isolated instance — and the
  reason, which is usually "the shared one clashes with the user's own browser
  session".
- The exact launch snippet, including the flags this machine needs.
- Where to write the output, and how to convert it.

---

<!--
## <Recipe name> (trigger: <the event that makes this worth reading>)

Rule (in CLAUDE.md): <the one line that lives in CLAUDE.md>

<The detail. Commands, paths, exact flags, the gotcha that cost you an hour.>
-->
