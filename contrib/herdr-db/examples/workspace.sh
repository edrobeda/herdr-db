# Example config for herdr-db-setup (a bash file, loaded with `source`).
# Copy it to the root of your workspace (e.g. ~/projects/my-company/herdr-db.sh) and adjust it.

# Workspace name in herdr.
WS_LABEL="my-company"

# Workspace root. Tab folders (TABS) are relative to it.
# State (generated instructions, queue and q shim) lives in $ROOT_DIR/.herdr-db/.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# OpenCode model and primary agent for the tabs. Empty = OpenCode default.
# List models with `opencode models` and agents with `opencode agent list`.
OPENCODE_MODEL=""            # e.g. "minimax/MiniMax-M2.5-highspeed"
OPENCODE_AGENT=""            # e.g. "my-agent" (must NOT declare `permission` in its frontmatter; see the README)

# Root paths the project agents may READ without asking (globs relative to ROOT_DIR).
# Editing these paths is denied.
ROOT_READONLY=("*.md" "docs/**")

# Extra instructions for your workspace (conventions, language, commit rules...), added to the templates.
# Paths relative to ROOT_DIR or absolute. Do not edit the templates: use these files instead.
PROJECT_INSTRUCTIONS=()      # e.g. ("docs/project-agents.md")
REPOSITORY_INSTRUCTIONS=()   # e.g. ("docs/repository-agent.md")

# Max time (ms) for each agent to become ready when starting (max 300000).
START_TIMEOUT=90000

# Tabs: "label|folder (relative to ROOT_DIR, or .)|type|agent name|description"
#   type: orchestrator  -> orchestrator (Claude Code): talks to you and delegates through the queue
#         opencode      -> project agent: writes only in its own folder
#         repository    -> repository agent (OpenCode): reads every repository, edits no files,
#                          owns branch/commit/push ("git" is accepted as an alias)
TABS=(
  "orchestrator|.|orchestrator|orchestrator|Orchestrator (you talk here)."
  "api|api|opencode|api|Node.js/Express backend."
  "web|web|opencode|web|React frontend."
  "repository|.|repository|repository-manager|The only one responsible for commit and push."
)
