# herdr-db — orchestrator + sub-agents + SQLite task queue for herdr

> **Unofficial fork.** This branch (`custom/db-orchestrator`) adds tooling on top of
> [herdr](https://github.com/herdrdev/herdr) ([herdr.dev](https://herdr.dev)), "the runtime your coding agents live on",
> by **herdrdev**, licensed under Apache-2.0. herdr's code is unchanged: everything new lives in
> `contrib/herdr-db/`. Please use and support the original project.

A small toolkit on top of herdr. It sets up a workspace with:

- an **orchestrator** (Claude Code);
- one **scoped OpenCode agent per project folder**;
- a single **repository agent** that owns branches, commits and pushes;
- a **SQLite-backed task queue** (`q`), so the orchestrator never has to scrape agent terminals. Agents write their
  answers to the queue, and the orchestrator waits on it, reviews and validates.

## Why this exists

herdr solves the hard part really well. It keeps many coding agents alive in tabs, with detectable state (`idle`,
`working`, `blocked`, `done`), and offers an API to send prompts and read terminals. Running herdr day to day with an
orchestrator and several agents over a workspace with many repositories, we hit problems that were not herdr's fault.
They came from how the work on top of it was organized:

1. **The orchestrator kept reading the agents' screens.** To know whether a task was done, it called `herdr agent
   read` over and over. That burned context on terminal chrome (borders, side panel, spinners) and was fragile: the
   answer came back truncated, mixed with the model list, or already scrolled out of view.
2. **No record of what was asked and what was delivered.** When the conversation ended, everything went with it:
   the prompt sent to each agent, its answer, and what was checked. Nothing could be resumed or audited later.
3. **"Done" did not mean done.** An agent said it had finished, and nobody checked independently.
4. **Blurry scope.** Any agent could edit any folder and touch git. In practice, branch cleanups were scattered across
   several agents, and uncommitted work got stuck on an old branch.
5. **Setting up the workspace was manual.** Recreating the tabs, model, permissions and each agent's instructions after
   a reboot took time and relied on memory.

herdr-db answers with four small pieces:

- a **SQLite queue** where the agent writes the answer and the orchestrator reads it;
- **roles whose scope is enforced by permissions**, not just by instructions: project agent, repository agent and
  orchestrator;
- an explicit **validation** step;
- an **idempotent setup** driven by a config file.

## Example (fictional)

> Illustrative scenario. The company, repositories, ticket and outputs are made up to show the flow.
> The commands and output formats are the real ones.

**Acme Deliveries** has three repositories in `~/acme`: `api` (Node/Express), `web` (React) and `app` (React Native).
Ticket *ACME-512: "customers cannot enter the address line 2"* comes in.

**1. Set up the workspace** (once; after a reboot, just run it again):

```sh
cd ~/acme && herdr-db-setup
# creates the orchestrator, api, web, app and repository tabs, each with the right agent, model, permissions and instructions
```

**2. The request.** You tell the orchestrator: *"fix ACME-512"*. It reads the code (read-only), finds that the field
must exist in the API and in the web form, and splits the work:

```sh
q add api - <<'EOF'
ACME-512: add `address_line2` (optional string, up to 120 chars) to the customer address.
Migration + model + validation on POST/PUT /customers/:id/address + test. Do not touch other routes.
Answer: changed files, test output.
EOF
q add web - <<'EOF'
ACME-512: optional "Address line 2" field in the address form, sending `address_line2` to the API.
Answer: changed files, lint and test output; say what was not tested in the browser.
EOF
q wait 1 2        # in the background; the orchestrator stays free and is notified when the answers arrive
```

**3. Validation catches a problem.** Both tasks come back `answered`. The orchestrator does not take the agent's word
for it. It runs the API tests (they pass) and checks the web diff: the form sends `addressLine2`, not
`address_line2`.

```sh
q validate 1 "api tests pass (checked)"
q reject 2 "the payload sends 'addressLine2'; the API expects 'address_line2'" --retry
#3 re-queued for web
q wait 3
q validate 3 "payload checked in the diff; lint ok"
```

**4. Version control goes through a single agent:**

```sh
q add repository-manager - <<'EOF'
Create branch feat/ACME-512-address-line2 in api and web from main, commit only the files listed
in tasks #1 and #3, and push. No PR.
EOF
```

**5. The history stays.** Weeks later, someone asks why the field is limited to 120 characters:

```sh
q list --all
#1    validated  api              10-02 14:03  ACME-512: add `address_line2` (optional string, up to 120 chars) to t…
#2    rejected   web              10-02 14:03  ACME-512: optional "Address line 2" field in the address form, sendi…
#3    validated  web              10-02 14:21  ACME-512: optional "Address line 2" field in the address form, sendi…
#4    validated  repository-manager 10-02 14:30  Create branch feat/ACME-512-address-line2 in api and web from main,…
q show 1      # the exact prompt, the agent's answer and the validation note
```

### What changes (qualitative comparison)

| | Without herdr-db | With herdr-db |
|---|---|---|
| Knowing an agent is done | reading its terminal over and over | `q wait` in the background notifies |
| Orchestrator context | spent on terminal chrome | only the answer text |
| Agent stuck waiting for approval | only noticed by looking at the tab | `wait` returns and flags `blocked` |
| The agent's "done" | accepted as is | `validate`/`reject --retry`, with a note |
| Cross-project integration bug (e.g. field name) | shows up in QA or production | tends to show up in the orchestrator's validation |
| Who can edit what | any agent, any folder | each agent only in its own folder; the repository agent edits no files |
| Commit and push | scattered across agents | a single agent, with rules (no force, no secrets) |
| History | gone with the conversation | `queue.db`: prompt, answer, timestamps and validation |
| Rebuilding everything after a reboot | manual | `herdr-db-setup` |

The gains depend on discipline: if the orchestrator skips validation or implements things itself, the queue becomes
just a log. That is why the orchestrator instructions forbid both.

## What's here

| File | Role |
|---|---|
| `bin/herdr-db-setup` | builds/restores the workspace from a config file (idempotent) |
| `bin/q` | task queue CLI (SQLite), used by the orchestrator and the agents |
| `templates/project-agent.md` | instructions for each project agent |
| `templates/repository-agent.md` | instructions for the repository agent |
| `templates/ORCHESTRATOR.md` | instructions for the orchestrator (how to delegate through the queue) |
| `examples/workspace.sh` | example config |

## Architecture

```
 you ──► orchestrator (Claude Code, workspace root)
             │  q add <agent> ...        q wait / q show / q validate
             ▼
      ┌─────────────── queue (SQLite: <root>/.herdr-db/queue.db) ──────────────┐
      │ pending → sent → answered|failed → validated|rejected                   │
      └──────────────────────────────────────────────────────────────────────────┘
             │ herdr agent prompt (1 task per agent)        ▲ q answer <id>
             ▼                                               │
   project agents (OpenCode, 1 per folder)  ─────────────────┘
   repository agent (OpenCode, root): branch/commit/push, edits no files
```

- **Project agents:** each one writes only in its own folder. They may read, without asking, the root paths listed in
  `ROOT_READONLY` (docs), and they do not commit or push.
- **Repository agent:** sees every repository, has `edit: deny` on everything and is the only one touching version
  control.
- **Orchestrator:** splits the work, enqueues self-contained prompts, waits on the queue and validates the results
  independently (git, tests) before accepting them.

## Install

Prerequisites: [herdr](https://herdr.dev), `python3`, `git`, [OpenCode](https://opencode.ai) and, for the orchestrator,
[Claude Code](https://docs.anthropic.com/claude-code).

```sh
git clone -b custom/db-orchestrator https://github.com/edrobeda/herdr-db.git
cd <your-workspace-root>
cp /path/herdr-db/contrib/herdr-db/examples/workspace.sh herdr-db.sh   # adjust WS_LABEL, TABS...
herdr            # in another terminal: the herdr server must be running
/path/herdr-db/contrib/herdr-db/bin/herdr-db-setup --dry-run
/path/herdr-db/contrib/herdr-db/bin/herdr-db-setup
```

The setup generates everything in `<root>/.herdr-db/`:

- `q`: a shim that points the queue at this workspace's database;
- `queue.db`: the queue database;
- `ORCHESTRATOR.md`: the orchestrator instructions;
- `agents/<name>.md` and `agents/<name>.opencode.json`: each agent's instructions and permissions.

To make the orchestrator load its instructions, add this line to the root `CLAUDE.md`:

```
@.herdr-db/ORCHESTRATOR.md
```

If the root is a git repository, add `.herdr-db/` to `.gitignore`.

For your team's rules (language, commit convention, list of repositories...), use `PROJECT_INSTRUCTIONS` and
`REPOSITORY_INSTRUCTIONS` in the config. They are `.md` files added to the generated instructions, and the templates
stay untouched.

Setup options: `-c CONFIG` (default `./herdr-db.sh`), `--dry-run`, `--status`, `--check` and `--no-orchestrator`.

## Queue (`q`)

```sh
q add <agent> "<task>"               # enqueue and dispatch if the agent is free (idle/done)
q add <agent> - <<'EOF'              # long task via stdin
...
EOF
q wait [id ...] [--timeout S]        # wait for the answers; run it in the background
q list [--all | --status S]
q show <id>
q validate <id> "note"
q reject <id> "reason" --retry       # re-queue for the same agent, with the reason
q cancel <id>
# used by the agents:
q answer <id> <<'END_Q' ... END_Q    # can be repeated to fix it, until the task is validated
q fail <id> <<'END_Q' ... END_Q
```

- **One task per agent:** each agent gets one task at a time, and the next one goes out when it is free again.
- **What gets sent:** the task goes with a `[task #N from the orchestrator queue]` header and a footer explaining
  exactly how to answer.
- **When `wait` returns early:** it also returns when an agent is `blocked` (waiting for approval) or has been idle for
  more than 90s without storing an answer. That way the orchestrator never waits forever.
- **Answer checks:** `q` rejects empty answers, answers that are just an unexpanded variable (e.g. `$RESPONSE`, which
  happened in practice) and answers to tasks already validated.
- **Database:** `Q_DB` selects the database (the shim sets it). Without it, the default is
  `~/.local/share/herdr-db/queue.db`.

## Lessons learned (worth reading before customizing)

- **OpenCode `.md` agent permissions beat everything.** If the primary agent (`OPENCODE_AGENT`) declares `permission`
  in its frontmatter, those rules are applied after `OPENCODE_CONFIG` and override the scope generated here. An
  `edit: allow` lets the repository agent edit files; a `bash: ask` makes the agents get stuck as `blocked` on every
  command. Keep the primary agent free of `permission`. To check the effective rules:
  `OPENCODE_CONFIG=.herdr-db/agents/<name>.opencode.json opencode debug agent <agent>`.
- **Agents can break their own tools.** An agent once overwrote `q` and updated the database by hand after storing a
  wrong answer. That is why `answer` accepts corrections and the task footer forbids touching `q` and the database. For
  an extra lock (Linux/ext4, as root): `chattr +i contrib/herdr-db/bin/q` (run `chattr -i` on it before a `git pull`).
- **An orchestrator started before `CLAUDE.md` existed is just a regular assistant.** A Claude session opened before
  the setup created the instructions implemented the fix itself and used its own sub-agents instead of the queue.
  Instructions only load at startup: after the first setup, restart any open orchestrator session.
- **Running agents do not reload instructions.** After changing config or model, close the tab
  (`herdr tab close <id>`) and run the setup again.
- **Git belongs to the repository agent.** Sending branch cleanup to the project agents works, but it spreads the
  responsibility around and breaks their scope.

## License

Same as the original project: Apache-2.0 (see `LICENSE` at the root). herdr belongs to herdrdev; this directory is an
independent contribution, not affiliated with the original authors.
