# Config de exemplo do herdr-db-setup (é um arquivo bash, carregado com `source`).
# Copie para a raiz do seu workspace (ex.: ~/projetos/minha-empresa/herdr-db.sh) e ajuste.

# Nome do workspace no herdr.
WS_LABEL="minha-empresa"

# Raiz do workspace. As pastas das abas (TABS) são relativas a ela.
# O estado (instruções geradas, fila e shim do q) fica em $ROOT_DIR/.herdr-db/.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Modelo e agente primary do OpenCode para as abas. Vazio = padrão do OpenCode.
# Veja os modelos com `opencode models` e os agentes com `opencode agent list`.
OPENCODE_MODEL=""            # ex.: "minimax/MiniMax-M2.5-highspeed"
OPENCODE_AGENT=""            # ex.: "meu-agente" (NÃO pode declarar `permission` no frontmatter; veja o README)

# Caminhos da raiz que os agentes de projeto podem LER sem pedir permissão (globs relativos a ROOT_DIR).
# Edição nesses caminhos é negada.
ROOT_READONLY=("*.md" "docs/**")

# Instruções extras do seu workspace (convenções, idioma, regras de commit...), somadas às dos templates.
# Caminhos relativos a ROOT_DIR ou absolutos. Não edite os templates: use estes arquivos.
PROJECT_INSTRUCTIONS=()      # ex.: ("docs/agentes-projeto.md")
REPOSITORY_INSTRUCTIONS=()   # ex.: ("docs/agente-repositorio.md")

# Tempo máximo (ms) para cada agente ficar pronto ao iniciar (máx. 300000).
START_TIMEOUT=90000

# Abas: "label|pasta (relativa a ROOT_DIR, ou .)|tipo|nome do agente|descrição"
#   tipo: orchestrator  -> orquestrador (Claude Code), conversa com você e delega pela fila
#         opencode      -> agente de projeto: escreve só na própria pasta
#         repository    -> agente de repositório (OpenCode): lê todos os repositórios, não edita arquivos,
#                          cuida de branch/commit/push (aceita também "git")
TABS=(
  "orquestrador|.|orchestrator|orquestrador|Orquestrador (você conversa aqui)."
  "api|api|opencode|api|Backend em Node.js/Express."
  "web|web|opencode|web|Frontend em React."
  "repository|.|repository|repository-manager|Único responsável por commit e push."
)
