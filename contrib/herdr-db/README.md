# herdr-db — orquestrador + subagentes + fila em SQLite para o herdr

> **Fork não oficial.** Esta branch (`custom/db-orchestrator`) adiciona ferramentas por cima do
> [herdr](https://github.com/herdrdev/herdr) ([herdr.dev](https://herdr.dev)), "the runtime your coding agents live on",
> de **herdrdev**, licenciado sob Apache-2.0. O código do herdr não foi alterado: tudo o que é novo está em
> `contrib/herdr-db/`. Use e apoie o projeto original.

*English summary:* a small toolkit on top of herdr that sets up a workspace with an orchestrator (Claude Code), one
scoped OpenCode agent per project folder, a single repository agent that owns branches/commits/pushes, and a
SQLite-backed task queue (`q`) so the orchestrator never has to scrape agent terminals: agents write their answers
to the queue, the orchestrator waits on it, reviews and validates.

## O que tem aqui

| Arquivo | Papel |
|---|---|
| `bin/herdr-db-setup` | monta/restaura o workspace a partir de um arquivo de config (idempotente) |
| `bin/q` | CLI da fila de tarefas (SQLite), usada pelo orquestrador e pelos agentes |
| `templates/project-agent.md` | instruções de cada agente de projeto |
| `templates/repository-agent.md` | instruções do agente de repositório |
| `templates/ORCHESTRATOR.md` | instruções do orquestrador (como delegar pela fila) |
| `examples/workspace.sh` | config de exemplo |

## Arquitetura

```
 você ──► orquestrador (Claude Code, raiz do workspace)
             │  q add <agente> ...        q wait / q show / q validate
             ▼
      ┌─────────────── fila (SQLite: <raiz>/.herdr-db/queue.db) ───────────────┐
      │ pending → sent → answered|failed → validated|rejected                   │
      └──────────────────────────────────────────────────────────────────────────┘
             │ herdr agent prompt (1 tarefa por agente)     ▲ q answer <id>
             ▼                                               │
   agentes de projeto (OpenCode, 1 por pasta)  ──────────────┘
   agente de repositório (OpenCode, raiz): branch/commit/push, sem editar arquivos
```

- **Agentes de projeto:** cada um só escreve na própria pasta. Podem ler, sem pedir permissão, os caminhos da raiz
  listados em `ROOT_READONLY` (docs), e não fazem commit nem push.
- **Agente de repositório:** enxerga todos os repositórios, tem `edit: deny` em tudo e é o único que mexe em
  versionamento.
- **Orquestrador:** divide o trabalho, enfileira prompts autocontidos, espera pela fila e valida os resultados de forma
  independente (git, testes) antes de aceitar.

## Instalação

Pré-requisitos: [herdr](https://herdr.dev), `python3`, `git`, [OpenCode](https://opencode.ai) e, para o orquestrador,
[Claude Code](https://docs.anthropic.com/claude-code).

```sh
git clone -b custom/db-orchestrator https://github.com/edrobeda/herdr-db.git
cd <raiz-do-seu-workspace>
cp /caminho/herdr-db/contrib/herdr-db/examples/workspace.sh herdr-db.sh   # ajuste WS_LABEL, TABS...
herdr            # em outro terminal: o servidor do herdr precisa estar rodando
/caminho/herdr-db/contrib/herdr-db/bin/herdr-db-setup --dry-run
/caminho/herdr-db/contrib/herdr-db/bin/herdr-db-setup
```

O setup gera tudo em `<raiz>/.herdr-db/`:

- `q`: um shim que aponta a fila para o banco deste workspace;
- `queue.db`: o banco da fila;
- `ORCHESTRATOR.md`: as instruções do orquestrador;
- `agents/<nome>.md` e `agents/<nome>.opencode.json`: as instruções e permissões de cada agente.

Para o orquestrador carregar as instruções, adicione esta linha ao `CLAUDE.md` da raiz:

```
@.herdr-db/ORCHESTRATOR.md
```

Se a raiz for um repositório git, coloque `.herdr-db/` no `.gitignore`.

Opções do setup: `-c CONFIG` (default `./herdr-db.sh`), `--dry-run`, `--status`, `--check` e `--no-orchestrator`.

## Fila (`q`)

```sh
q add <agente> "<tarefa>"            # enfileira e despacha se o agente estiver livre (idle/done)
q add <agente> - <<'EOF'             # tarefa longa via stdin
...
EOF
q wait [id ...] [--timeout S]        # espera as respostas; rode em background
q list [--all | --status S]
q show <id>
q validate <id> "nota"
q reject <id> "motivo" --retry       # reenfileira para o mesmo agente, com o motivo
q cancel <id>
# usados pelos agentes:
q answer <id> <<'FIM_Q' ... FIM_Q    # pode ser repetido para corrigir, até a tarefa ser validada
q fail <id> <<'FIM_Q' ... FIM_Q
```

- **Uma tarefa por agente:** cada agente recebe uma tarefa de cada vez, e a próxima sai quando ele volta a ficar livre.
- **Mensagem enviada:** a tarefa vai com um cabeçalho `[tarefa #N da fila do orquestrador]` e um rodapé que explica
  exatamente como responder.
- **Quando o `wait` para antes:** ele também termina quando um agente fica `blocked` (pedindo aprovação) ou fica livre
  por mais de 90s sem ter gravado a resposta. Assim o orquestrador não espera para sempre.
- **Validações da resposta:** o `q` recusa resposta vazia, resposta que seja só uma variável não expandida (ex.:
  `$RESPONSE`, erro que já aconteceu na prática) e resposta para tarefa já validada.
- **Banco:** `Q_DB` escolhe o banco (o shim já define). Sem ele, o padrão é `~/.local/share/herdr-db/queue.db`.

## Lições aprendidas (vale ler antes de customizar)

- **Permissões em agentes `.md` do OpenCode ganham de tudo.** Se o agente primary (`OPENCODE_AGENT`) declarar
  `permission` no frontmatter, essas regras são aplicadas depois do `OPENCODE_CONFIG` e anulam o escopo gerado aqui.
  Um `edit: allow` libera o agente de repositório para editar arquivos; um `bash: ask` faz os agentes travarem em
  `blocked` a cada comando. Deixe o agente primary sem `permission`. Para conferir as regras efetivas:
  `OPENCODE_CONFIG=.herdr-db/agents/<nome>.opencode.json opencode debug agent <agente>`.
- **Agentes podem estragar a própria ferramenta.** Um agente já sobrescreveu o `q` e atualizou o banco na mão depois
  de gravar uma resposta errada. Por isso o `answer` aceita correção, e a mensagem da tarefa proíbe mexer no `q` e no
  banco. Se quiser uma trava extra (Linux/ext4, como root): `chattr +i contrib/herdr-db/bin/q`.
- **Agentes que já estavam rodando não recarregam instruções.** Depois de mudar config ou modelo, feche a aba
  (`herdr tab close <id>`) e rode o setup de novo.
- **Git é com o agente de repositório.** Mandar limpeza de branches para os agentes de projeto funciona, mas espalha a
  responsabilidade e fura o escopo deles.

## Licença

As mesmas do projeto original: Apache-2.0 (veja `LICENSE` na raiz). herdr é de herdrdev; este diretório é uma
contribuição independente, sem vínculo com os autores originais.
