<p align="center">
  <img src="assets/logo.svg" alt="boxkite" width="72" height="72">
</p>

<h1 align="center">boxkite</h1>

<p align="center">
  <a href="LICENSE"><img alt="License: FSL-1.1-Apache-2.0" src="https://img.shields.io/badge/license-FSL--1.1--Apache--2.0-blue"></a>
  <a href="https://github.com/HarshitKmr10/boxkite/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/HarshitKmr10/boxkite/actions/workflows/ci.yml/badge.svg"></a>
</p>

**The missing batteries-included, self-hostable sandbox for agent code execution.**

Most "agent sandbox" projects give you raw isolation — a pod, a VM, a
container — and leave you to build the actual tool surface an LLM agent
needs on top of it. boxkite is the other half: a complete
`bash`/`python`/file/search/process tool surface (15 ready-to-wire,
framework-agnostic tools — LangChain, LangGraph, CrewAI, AutoGen, or plain
OpenAI-style function calling — plus an opt-in git tool set of 8 more)
running inside real Kubernetes pod isolation, built on industry-standard hardening
practices — non-root execution, all Linux capabilities dropped, a read-only
root filesystem, network egress denied by default, and output scrubbed for
leaked API keys and cloud credentials before it ever reaches your agent.
boxkite itself is early-stage (v0.1.0) — the isolation approach is proven,
the project's production track record is not, yet.

Self-host it, point your agent framework at it, and you have a real sandbox
in minutes instead of weeks. Everything here — the sandbox runtime, the
hosted-API control-plane, all four client SDKs, and the MCP server — is
self-hostable end to end; there's no piece of this product held back for a
separate, closed hosted offering.

**Who this is for:** boxkite is a self-hostable sandbox for teams *building
their own agent products* that need isolated, multi-tenant code execution at
scale — one Kubernetes pod per session, many sessions, many tenants. It is
**not** a single-user local dev-session sandbox like the built-in `bash` tool
in an IDE or CLI coding agent — if you just want your own coding assistant to
run shell commands on your own machine, boxkite is the wrong layer; it's for
when *you* are the one operating the sandbox infrastructure behind an agent
product other people use.

## Contents

- [Why this exists](#why-this-exists)
- [What's actually in here](#whats-actually-in-here)
- [The isolation model](#the-isolation-model)
- [Security](#security)
- [Self-hosting](#self-hosting)
- [The `boxkite` CLI](#the-boxkite-cli)
- [Published packages and images](#published-packages-and-images)
- [Cookbook / examples](#cookbook--examples)
- [Extending it: AuditSink and SessionMetadataStore](#extending-it-auditsink-and-sessionmetadatastore)
- [What's not included](#whats-not-included)
- [License](#license)
- [Contributing](#contributing)

## Why this exists

Raw pod-per-session isolation is no longer whitespace on its own —
[`kubernetes-sigs/agent-sandbox`](https://github.com/kubernetes-sigs/agent-sandbox)
(a Kubernetes SIG-Apps project) already does that well, and GKE's managed
version of it is faster to cold-start than this project's warm-pool claim.
boxkite is **not** a competitor to that primitive — it's designed to sit
compatibly alongside it, and a boxkite-style tool layer running on top of
`agent-sandbox`'s pod lifecycle is a reasonable future direction.

What boxkite fills in is the layer *above* raw isolation that, as of this
writing, nothing else ships as a complete, self-hostable package:

- **Daytona** was, in our assessment, the most credible open self-hosted
  alternative here, with a large GitHub star count. As of this writing
  (mid-2026) we believe it has privatized its core and that its OSS repo is
  no longer actively maintained — verify current licensing and repo activity
  directly on Daytona's GitHub page and website before relying on this, as
  we have not linked a snapshot/citation here and project status can change.
- **LangChain's own native sandbox integration** appears, as of this writing,
  to have been archived, with users redirected to hosted-only services —
  check LangChain's repo/changelog directly for the current status rather
  than treating this as a permanent fact.
- **E2B, Modal, Riza** and similar are excellent, but hosted-first —
  self-hosting isn't really the point of their product.

boxkite's pitch is narrow and specific: **if you want the whole
bash/python/file tool surface, hardened and wired to a real K8s pod, running
entirely on infrastructure you control — this is the reference
implementation to start from**, not a novel isolation primitive.

| | boxkite | Daytona | E2B | Modal |
|---|---|---|---|---|
| Self-hostable | Yes | No — core reportedly privatized mid-2026, OSS repo believed unmaintained (verify current status) | No — hosted-first | No — hosted-first |
| Batteries-included, framework-agnostic agent tool surface (bash/python/file tools, no LangChain dependency required) | Yes | Not the product focus | Not the product focus | Not the product focus |
| Isolation primitive | Kubernetes pod (one per session) | Unmaintained as OSS | Own hosted sandbox runtime[^isolation] | Own hosted sandbox runtime[^isolation] |
| Open source | Source-available (FSL-1.1, converts to Apache-2.0 after 2 years — see [License](#license)) | No longer — core is privatized | No | No |

[^isolation]: E2B and Modal don't publish their exact isolation primitive as part of this project's own docs — see each vendor's site for details. The comparison here is about self-hosting and tool-surface completeness, not the isolation technology itself.

## What's actually in here

This is one repo with several independently-versioned pieces in it, kept
together deliberately (see [CONTRIBUTING.md](CONTRIBUTING.md) for why)
rather than split across repos. If you only want to self-host the sandbox,
the **Core** section below is the entire surface you need — everything else
is optional, and mostly exists to talk to a control-plane you run yourself
instead of embedding the library directly.

**Core — embed the sandbox directly against your own Kubernetes cluster:**

- **`src/boxkite/`** — the Python package (`pip install boxkite-sandbox`):
  `SandboxManager` (K8s pod lifecycle + HTTP routing to the sidecar),
  `WarmPoolManager` (a pre-warmed pod pool so session start is a claim, not a
  cold boot), `LazySandboxRuntime` (defers pod creation until a tool call
  actually needs one), and `boxkite.tools` — fifteen framework-agnostic
  tools (LangChain `BaseTool`, LlamaIndex `FunctionTool`, OpenAI-style
  function-calling schema, or plain callables for CrewAI/AutoGen/anything
  else — see `boxkite.tools.adapters`):
  `bash_tool`, `python_interpreter`, `file_create`, `view`, `str_replace`,
  `present_files`, `ls`, `glob`, `grep`, `start_process`,
  `get_process_output`, `send_process_input`, `stop_process`,
  `list_processes`, `watch_directory` (a long-poll filesystem watcher).
  Tested by the root `tests/`. Several opt-in tool sets exist too, each
  gated behind its own flag and documented in that tool module's own
  docstrings: a git tool set (`git_clone`/`git_status`/`git_add`/`git_commit`/
  `git_push`/`git_pull`/`git_branch`/`git_checkout`), a persistent
  `node_interpreter` (the Node.js counterpart to `python_interpreter`),
  `run_tests`, browser automation (`browser_navigate`/`browser_exec`/
  `browser_screenshot`/`browser_close`, the riskiest opt-in tool this repo
  ships since it needs broad, non-enumerable HTTPS/DNS egress unlike every
  other tool here), and LSP completion (`lsp_start`/`lsp_completion`/
  `lsp_stop`, a persistent `pyright`/`typescript-language-server` process
  per session).
- **`sidecar/main.py`** — the FastAPI service that runs alongside the
  sandbox container in every pod. It owns the actual filesystem I/O, runs
  agent commands via `nsenter` into the sandbox's namespace (dropping to a
  non-root UID before exec), and syncs files to S3 or Azure Blob storage.
- **`deploy/`** — Kubernetes manifests (`pod-template.yaml`, `rbac.yaml`,
  `network-policy.yaml`), the container images (`sandbox.Dockerfile`,
  `sidecar.Dockerfile`, `control-plane/Dockerfile`), a `docker-compose.yml`
  for local dev without a cluster, and `deploy/local-kind/` for a real (if
  small) Kubernetes dev loop on your laptop.

**Optional — run or talk to a control-plane you host yourself instead of
embedding `SandboxManager` directly:**

- **`control-plane/`** — a separate FastAPI service (own `pyproject.toml`,
  own `src/control_plane`, own `tests/`) that puts signup/API-key auth,
  multi-tenant accounts, and fair-use rate limits in front of
  `SandboxManager`. Only needed if you want a hosted-API surface rather than
  embedding the library directly. Optional add-on auth surfaces, all off by
  default pending operator opt-in: GitHub/Google social login, an MCP OAuth
  2.1 authorization server (with RFC 7591 dynamic client registration) for
  inbound MCP clients, and enterprise SAML/OIDC SSO via a hosted broker.
- **`sdk-python/`** (`boxkite-client` on PyPI), **`sdk-js/`**
  (`boxkite-client` on npm), **`sdk-go/`**
  (`github.com/HarshitKmr10/boxkite/sdk-go`), and **`sdk-rust/`** — thin
  HTTP clients for *your own* running control-plane, not for `src/boxkite`
  itself. See each SDK's own `README.md` for what's implemented.
- **`mcp-server/`** (`boxkite-mcp`) — wraps `sdk-python` as an MCP tool
  source, for pointing Claude Code, Claude Desktop, Cursor, or any other
  MCP client at a control-plane you run.
- **`bastion/`** — a standalone SSH server (own `pyproject.toml`, own
  `tests/`) that lets `ssh <session_id>@host` authenticate with a takeover
  token as the SSH password and bridges straight into the same
  human-takeover WebSocket the control-plane exposes — real SSH access to a
  session's shell without a second `sshd` inside the sandbox itself.

**Everything else:**

- **`examples/`** — the runnable cookbook (LangGraph, LangChain, raw HTTP,
  a self-hosted control-plane walkthrough).
- **`scripts/`** — one-off maintenance/benchmark scripts, not part of any
  published package.
- **`tests/`** — tests for the root `src/boxkite` package specifically; each
  of `control-plane/`, `sdk-python/`, `sdk-js/`, `sdk-go/`, `sdk-rust/`, and
  `mcp-server/` has its own tests alongside its own source, run
  independently (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## The isolation model

Every session is one Kubernetes pod with two containers sharing volumes:

| | `sandbox` container | `sidecar` container |
|---|---|---|
| Runs | Agent-generated code | The HTTP API + storage sync |
| User | Non-root (UID 1001), `runAsNonRoot: true` | Root (needed for `nsenter`) |
| Capabilities | All dropped (`capabilities.drop: [ALL]`) | Only `SYS_PTRACE`/`SYS_ADMIN`, needed for `nsenter` — never inherited by agent code |
| Filesystem | Read-only root filesystem | Read-write (owns the shared volumes) |
| Network | Denied by default (`NetworkPolicy` + a fresh network namespace per `exec`) | Only what storage sync needs |
| Privilege escalation | `allowPrivilegeEscalation: false` | Same |

The sidecar drops to the sandbox's UID/GID via `nsenter --setuid --setgid`
*before* executing any agent command — the elevated capabilities it needs
for `nsenter` itself are never available to the code it runs. Command
output is scrubbed for AWS/Azure keys, JWTs, and generic secret-shaped
strings before it's returned (`src/boxkite/tools/bash_tool.py`). Sensitive
host paths (`~/.ssh`, `~/.aws`, `~/.kube`, the Docker socket) are outside
every mount the sandbox container can see.

See `deploy/network-policy.yaml` and `deploy/rbac.yaml` for the actual
manifests — they're written as real starting points with inline "change
this for your cluster" comments, not illustrative snippets.

## Security

boxkite executes arbitrary, agent-generated code, so its security posture is
layered defense in depth — no single control below is sufficient on its own.

- **Sidecar HTTP API authentication.** The sidecar (`sidecar/main.py`) has
  no authentication of its own beyond a per-pod shared secret
  (`SIDECAR_AUTH_TOKEN`, sent as the `X-Sidecar-Auth-Token` header on every
  route except `/health`). `SandboxManager`/`WarmPoolManager`
  (`src/boxkite/sidecar_auth.py`) generate this fresh per pod at
  pod-creation time — never a static, repo-wide value — and store it in a
  dedicated per-pod Kubernetes Secret (referenced by the pod's env var via
  `secretKeyRef`, never a literal value) so any manager process can recover
  it later via a separate `secrets: get` RBAC grant, not merely the
  `pods: get/list` the manager already needs for routine lifecycle
  management. The sidecar fails closed: if `SIDECAR_AUTH_TOKEN` isn't set,
  every protected route returns 503 rather than silently running
  unauthenticated. This exists **in addition to** NetworkPolicy, not instead
  of it — NetworkPolicy enforcement is CNI-dependent (GKE Autopilot without
  Dataplane V2, EKS's default VPC CNI, and `deploy/local-kind/` all ship
  without an enforced NetworkPolicy), and even where enforced, a broad
  egress rule on the pod also governs what can reach the sidecar's own
  ingress, since both containers in a pod share one network namespace.
- **Per-exec network isolation.** Every `/exec` call in K8s runtime mode
  runs inside a freshly created, empty network namespace (`unshare -n`
  before `nsenter` — see `build_k8s_exec_command` in `sidecar/main.py`),
  controlled by `SANDBOX_EXEC_NETWORK_ISOLATION_ENABLED` (default `true`).
  This is the *actual* network isolation boundary for agent-executed
  commands — not `deploy/network-policy.yaml` alone. If you set that flag to
  `false`, the NetworkPolicy becomes the only backstop against exec'd
  commands reaching the network, so make sure it's genuinely restrictive
  (see the next point) before doing so.
- **NetworkPolicy egress must be scoped to your actual storage endpoint,**
  not left as a blanket allow. `deploy/network-policy.yaml` ships with a
  placeholder you must fill in (in-cluster storage via pod/namespace
  selector, or your cloud provider's storage CIDR/FQDN) — read the comments
  in that file before applying it. A separate, explicitly-named
  `sandbox-network-policy-permissive` policy — kept in its own file,
  `deploy/network-policy-permissive-optin.yaml`, specifically so it can't be
  applied as a side effect of `kubectl apply -f deploy/network-policy.yaml`
  — is available as an opt-in for self-hosters who want fully open egress
  instead; it is never applied by default and must not be layered on top of
  the scoped policy (overlapping NetworkPolicy selectors are additive, so
  applying both silently reintroduces the wide-open behavior).
- **The sidecar holds CAP_SYS_ADMIN for the pod's entire lifetime.** The
  nsenter-based isolation design requires it (`setns()` needs
  `CAP_SYS_ADMIN`, not just `CAP_SYS_PTRACE`) — see the security comment on
  the sidecar container in `deploy/pod-template.yaml` and
  `src/boxkite/manager.py`. This is a near-root capability: any future
  RCE-class bug in the sidecar's own FastAPI request handling would be
  equivalent to full `CAP_SYS_ADMIN` root within the pod. This is inherent
  to the current design, not a misconfiguration, which is exactly why the
  two layers above (sidecar auth, NetworkPolicy) matter — they're what
  stands between "reachable" and "exploitable."
- **Command output redaction is a cosmetic backstop, not a security
  boundary.** `src/boxkite/tools/bash_tool.py`'s regex-based scrubbing
  catches accidentally-echoed labeled secrets (`api_key=...`,
  `password: ...`, etc.) in command output before it reaches the calling
  agent. It cannot catch a deliberately evasive agent (unlabeled values,
  encoding, splitting a secret across multiple tool calls). Do not rely on
  it to protect a secret you've decided to expose to agent-visible command
  execution — see the next point instead.
- **No credential injection into agent-visible `/exec` calls.** The
  sidecar's `/exec` endpoint does not accept caller-supplied environment
  variables. If your integration needs a credentialed operation performed
  on behalf of a sandbox session, do it as a server-side broker call the
  manager makes on the sandbox's behalf — never by handing real secret
  values to an environment that LLM-generated shell commands can read.

**Known, currently-unmitigated gaps worth knowing before you deploy**
(rather than discovering them yourself): the two container images
(`sandbox.Dockerfile`/`sidecar.Dockerfile`) download some upstream
dependencies without checksum verification; docker-compose local-dev mode
bind-mounts the host's Docker socket into the sidecar container (see the
CRITICAL warning in "Self-hosting" below — this doesn't exist in the
Kubernetes runtime at all); and command-name allowlisting is a guardrail
against accidental commands, not a sandbox-escape boundary. See
[SECURITY.md](SECURITY.md) for the full vulnerability-reporting process.
Manager-to-sidecar traffic is TLS by default now (a fresh, short-lived,
self-signed cert per pod, pinned by the manager — see
`SIDECAR_TLS_DISABLED` in `src/boxkite/tls.py` for the escape hatch).

## Self-hosting

boxkite is self-host-only — everything in this repo, including the
`control-plane/` hosted multi-tenant API (accounts, API keys, authenticated
sandbox exec), is something you deploy yourself. Everything in this section
runs entirely on infrastructure you control, whether that's docker-compose
on your laptop or a real Kubernetes cluster.

### Quickstart: docker-compose, no Kubernetes needed

> **Before you run this: docker-compose mode is single-developer local dev
> only, never production or multi-tenant, and the reason is a real,
> currently-unmitigated CRITICAL finding, not boilerplate caution.**
> `deploy/docker-compose.yml` bind-mounts the host's `/var/run/docker.sock`
> into the sidecar container so it can `docker exec` into the sandbox
> container. Anyone with a live connection to that socket can trivially
> escalate to full **host-root** compromise (e.g. `docker run --privileged
> -v /:/host ...`) — this was verified directly, including that the standard
> `docker-socket-proxy` mitigation does **not** close it. The only thing
> standing between sandboxed code and this socket is `SIDECAR_AUTH_TOKEN`
> gating the sidecar's own HTTP API; any future auth-bypass, path-traversal,
> or command-injection bug escalates straight to host compromise, not just
> container compromise. The sidecar itself logs a loud startup warning when
> it detects the socket mounted, as a last-resort reminder. **This does not
> exist in the Kubernetes runtime at all** (no docker socket, no
> docker-in-docker) — if you want the real isolation model from the start,
> or anything beyond a single local developer, skip ahead to
> [Quickstart: real Kubernetes, via kind](#quickstart-real-kubernetes-via-kind)
> instead.

The fastest path for pure local iteration is the `boxkite` CLI —
`pip install boxkite-sandbox` (published on PyPI) or `pip install -e .` from
a clone of this repo if you want to hack on it — see "The `boxkite` CLI"
below for the full command reference.

> **Note:** the PyPI package name is `boxkite-sandbox`, not `boxkite` — the
> plain `boxkite` name was already taken on PyPI. This only affects the
> `pip install` command; the Python import path is unchanged (`import
> boxkite`), and so is the `boxkite` CLI command. Same split as
> `beautifulsoup4` (PyPI name) vs. `bs4` (import name) — `pip install
> boxkite` will either fail or install an unrelated package, so make sure to
> install `boxkite-sandbox` instead.

```bash
git clone https://github.com/HarshitKmr10/boxkite.git boxkite && cd boxkite
# NOT "pip install boxkite" — that's a different, unrelated package on PyPI.
pip install -e .
boxkite up
boxkite exec "python3 -c 'print(1 + 1)'"
boxkite files create hello.txt --content "hello from boxkite\n"
boxkite files view hello.txt
```

> **First-run build time:** `boxkite up` always builds the `sandbox` image
> locally from `deploy/sandbox.Dockerfile` rather than pulling
> `ghcr.io/harshitkmr10/boxkite-sandbox` — this includes downloading a
> pinned Chrome-for-Testing build (~300MB across the browser and
> headless-shell zips) plus FFmpeg. On a fast connection with a warm Docker
> cache this typically takes several minutes, not seconds — `docker ps`
> will show no running containers until the build finishes. Subsequent runs
> reuse the cached image layers and start in seconds. Published images exist
> on GHCR (see "Published packages and images" below) if you want to
> reference them directly in your own compose override instead of building
> locally.

`boxkite up` builds and starts the `sandbox` container, the `sidecar` HTTP
API, and a local MinIO for S3-compatible storage — generating a fresh
`SIDECAR_AUTH_TOKEN` and storing it in `~/.boxkite/local.env` so `boxkite
exec`/`boxkite files` pick it up automatically. No more manually exporting
`SIDECAR_AUTH_TOKEN` yourself.

<details>
<summary>Or do it manually, without the CLI (raw HTTP contract)</summary>

```bash
git clone https://github.com/HarshitKmr10/boxkite.git boxkite && cd boxkite
cp .env.example .env
# Generate a secret for the sidecar's HTTP API and put it in .env — see the
# "Security" section above for why this is required, not optional.
echo "SIDECAR_AUTH_TOKEN=$(openssl rand -hex 32)" >> .env
docker compose -f deploy/docker-compose.yml up -d --build
```

This builds and starts the `sandbox` container, the `sidecar` HTTP API, and
a local MinIO for S3-compatible storage. Check it's healthy:

```bash
curl http://localhost:8080/health
```

Exercise it directly, before wiring up an agent framework (every route
except `/health` requires the `X-Sidecar-Auth-Token` header):

```bash
export SIDECAR_AUTH_TOKEN=$(grep ^SIDECAR_AUTH_TOKEN= .env | cut -d= -f2)

curl -X POST http://localhost:8080/exec \
  -H "Content-Type: application/json" -H "X-Sidecar-Auth-Token: $SIDECAR_AUTH_TOKEN" \
  -d '{"command": "python3 -c \"print(1 + 1)\""}'

curl -X POST http://localhost:8080/file-create \
  -H "Content-Type: application/json" -H "X-Sidecar-Auth-Token: $SIDECAR_AUTH_TOKEN" \
  -d '{"path": "hello.txt", "content": "hello from boxkite\n"}'

curl -X POST http://localhost:8080/view \
  -H "Content-Type: application/json" -H "X-Sidecar-Auth-Token: $SIDECAR_AUTH_TOKEN" \
  -d '{"path": "hello.txt"}'
```

</details>

Then, from Python, wire the sandbox tools into an agent. `SandboxManager`
picks up compose vs. Kubernetes mode from the environment, so point it at
the sidecar you just started (with the same token `boxkite up` generated,
or the one you put in `.env` manually):

```bash
export RUNTIME_MODE=compose SIDECAR_URL=http://localhost:8080
# If you used `boxkite up`, the token is in ~/.boxkite/local.env:
export SIDECAR_AUTH_TOKEN=$(grep ^SIDECAR_AUTH_TOKEN= ~/.boxkite/local.env | cut -d= -f2)
# If you started compose manually, it's in .env instead:
#   export SIDECAR_AUTH_TOKEN=$(grep ^SIDECAR_AUTH_TOKEN= .env | cut -d= -f2)
```

boxkite's tool surface (`bash_tool`, `python_interpreter`, `file_create`,
`view`, `str_replace`, `present_files`, `ls`, `glob`, `grep`,
`start_process`, `get_process_output`, `send_process_input`, `stop_process`,
`list_processes`, plus opt-in tool sets) is framework-agnostic by default —
`create_sandbox_tool_specs()` returns plain `ToolSpec`s (a name,
description, JSON-schema parameters, and a normal async callable) with no
LangChain/LangGraph dependency at all:

```python
from uuid import uuid4
from boxkite import SandboxManager
from boxkite.tools import create_sandbox_tool_specs

manager = SandboxManager()
session_id = str(uuid4())
await manager.create_session(organization_id=uuid4(), session_id=session_id)

specs = create_sandbox_tool_specs(sandbox_manager=manager, session_id=session_id)
# specs = [ToolSpec(name="bash_tool", ...), ToolSpec(name="file_create", ...), ...]

bash_tool = next(s for s in specs if s.name == "bash_tool")
result = await bash_tool.handler(command="echo hello from boxkite")
# Call handler(**kwargs) directly, wire specs into CrewAI/AutoGen/a hand-rolled
# tool-calling loop, or convert the whole list with an adapter:
#   boxkite.tools.adapters.to_openai_functions(specs) -- OpenAI-style
#   function-calling schema, stdlib only, no extra dependency.
```

Prefer LangChain or LangGraph? `boxkite.tools.adapters.to_langchain_tools`
converts the same specs into LangChain `BaseTool` objects (requires the
`langchain` extra: `pip install boxkite-sandbox[langchain]`) — or use the
backward-compatible `create_sandbox_tools()`, which does exactly that
internally:

```python
from boxkite.tools import create_sandbox_tools

tools = create_sandbox_tools(sandbox_manager=manager, session_id=session_id)
# tools = [bash_tool, python_interpreter, file_create, view, str_replace,
#          present_files, ls, glob, grep, start_process, get_process_output,
#          send_process_input, stop_process, list_processes]
# Hand these to any LangChain/LangGraph agent. Pass enable_git_tools=True
# to additionally include the opt-in git tool set.
```

Prefer LlamaIndex? `boxkite.tools.adapters.to_llamaindex_tools` converts
the same specs into LlamaIndex `FunctionTool` objects (requires the
`llamaindex` extra: `pip install boxkite-sandbox[llamaindex]`), ready to
hand to a `ReActAgent`/`FunctionAgent` — see `examples/llamaindex_agent/`.

**The full integration surface, in one place:**

| Framework/provider | How |
|---|---|
| LangChain / LangGraph | `to_langchain_tools()` (`langchain` extra) |
| LlamaIndex | `to_llamaindex_tools()` (`llamaindex` extra) — see `examples/llamaindex_agent/` |
| OpenAI Agents SDK | `to_openai_agents_tools()` (`openai-agents` extra) — see `examples/openai_agents_sdk/` |
| CrewAI, AutoGen/AG2, hand-rolled loops | Plain `ToolSpec.handler(**kwargs)` — no adapter needed |
| OpenAI function calling | `to_openai_functions()` — stdlib, no `openai` dependency — see `examples/openai_function_calling/` |
| Anthropic tool use | Same `ToolSpec.parameters`/`handler` shape as OpenAI above |
| Google Gemini | Same shape, unwrapped into Gemini's `FunctionDeclaration` — see `examples/gemini_function_calling/` |
| Mistral | Same shape, Mistral's own tool-calling API — see `examples/mistral_function_calling/` |
| Groq | Same shape, genuinely OpenAI-compatible — see `examples/groq_function_calling/` |
| Vercel AI SDK (JS) | `sdk-js`'s `createSandboxTools()` from `boxkite-client/vercel-ai` (`ai` v5 extra) |
| MCP (Claude Desktop, Claude Code, Cursor) | `mcp-server/` (`boxkite-mcp`) — a standalone MCP server over a control-plane you run, zero custom integration code |
| Claude Code CLI, headless, inside a sandbox | `examples/claude_code_sandbox/`, or `examples/claude_code_declarative_builder/` for the control-plane API path instead of a hand-maintained Dockerfile |

See `examples/` for a runnable version of every row above.

### Quickstart: real Kubernetes, via kind

```bash
./deploy/local-kind/setup.sh
kubectl proxy --context kind-boxkite-dev --reject-paths='' &
export RUNTIME_MODE=k8s SANDBOX_USE_K8S_PROXY=true \
       SANDBOX_IMAGE=boxkite-sandbox:local SIDECAR_IMAGE=boxkite-sidecar:local
```

See [`deploy/local-kind/README.md`](deploy/local-kind/README.md) for the
full walkthrough, verification steps, and teardown.

> **Known limitation — Apple Silicon / arm64:** `setup.sh` builds the
> `boxkite-sandbox` image locally, and that build intentionally fails on
> arm64 hosts (including Apple Silicon Macs). This is a deliberate security
> control, not a bug: the sandbox's bundled Chromium is replaced with a
> pinned Chrome-for-Testing build to clear known-vulnerability-scanner
> findings, and Chrome for Testing does not publish a Linux arm64 build for
> any version — so there's no pin that would fix this, and silently falling
> back to the older bundled Chromium would reintroduce the vulnerability the
> pin exists to close. See [`deploy/local-kind/README.md`'s "Known
> limitations"](deploy/local-kind/README.md#known-limitations) for the full
> explanation and workarounds (build on an amd64 CI runner/cloud host and
> push to a registry, or develop on an actual amd64 machine).

For a real (non-kind) cluster, apply `deploy/rbac.yaml`,
`deploy/network-policy.yaml`, and `deploy/pod-security-policy.yaml` (edit
the namespace and service account references first), build and push the
two images from `deploy/`, and point `SANDBOX_IMAGE`/`SIDECAR_IMAGE` at
your registry. `deploy/pod-security-policy.yaml` is the cluster-level
backstop for `deploy/rbac.yaml`'s own disclosed limitation (RBAC can't
scope pod/secret verbs to sandbox-labeled resources only) -- apply it even
if you also follow the dedicated-namespace mitigation `deploy/rbac.yaml`
recommends, since that mitigation is a deployment convention, not something
Kubernetes enforces on its own.

**Pre-built images:** as of `v0.1.0`, these are published to GHCR:

- `ghcr.io/harshitkmr10/boxkite-sandbox`
- `ghcr.io/harshitkmr10/boxkite-sidecar`
- `ghcr.io/harshitkmr10/boxkite-control-plane`

Building them yourself from `deploy/` (and `control-plane/Dockerfile` for
the control-plane image) as described above still works and stays in sync
with whatever's in your working tree, pinned images or not.

## The `boxkite` CLI

`boxkite up`/`boxkite exec` above are two of the CLI's commands (also:
`config`, `session`, `files`, `keys`, `whoami`, `log`, `watch`, `allowlist`,
`signup`, `audit`). The CLI works in two modes, auto-detected from what's configured:

- **Local mode** — nothing configured beyond `boxkite up`. Every command
  talks directly to the single docker-compose sidecar that `boxkite up`
  started, using the token it wrote to `~/.boxkite/local.env`.
- **Hosted mode** — once `boxkite config set-url`/`set-key` (or `boxkite
  signup`) has stored a control-plane URL and API key in
  `~/.boxkite/config.toml`, every command switches to calling that
  `control-plane/` API instead, authenticated as `Authorization: Bearer
  <api-key>`. That control-plane is something you deploy yourself — `boxkite
  signup` talks to whatever URL you've pointed it at.

```bash
# Local mode
boxkite up                                  # start docker-compose (sandbox + sidecar + MinIO)
boxkite exec "ls /workspace"                # runs against the local sidecar
boxkite files view hello.txt
boxkite files create notes.txt --content "hi"
boxkite files edit notes.txt --old "hi" --new "hello"

# Hosted mode (against a control-plane you've deployed)
boxkite signup                              # signup -> login token -> create API key, in one step
# or: boxkite config set-url https://your-control-plane.example.com
#     boxkite config set-key bxk_live_...
boxkite session create --label "demo"                      # defaults to size=small, one sandbox
boxkite session create --label "build" --size medium \
  --storage-gb 20 --lifetime-minutes 120 --count 3          # optional overrides, all fair-use bounded
boxkite session ls
boxkite exec "python3 -c 'print(1 + 1)'"    # auto-picks the session if exactly one is active
boxkite exec "ls /workspace" --session <id> # or pick one explicitly
boxkite session rm <id>

boxkite log                                 # paginated exec/file-op audit history for the active session
boxkite log --limit 20 --offset 0 --session <id>
boxkite watch                               # live feed of new exec/file-op entries; blocks until Ctrl-C

boxkite allowlist get                       # unrestricted by default for every account
boxkite allowlist set ./allowed-commands.json
boxkite allowlist clear                     # back to unrestricted
```

`--size` is a CPU/memory preset (`small` by default, or `medium`/`large`);
`--storage-gb` and `--lifetime-minutes` override the sandbox's volume size
and how long it stays alive before the reaper tears it down; `--count`
creates a batch of sandboxes in one call (default `1`). All four are
optional and capped by fair-use ceilings on your account, never a paid upgrade.

`boxkite allowlist` (hosted mode only) lets an account persist an opt-in
command allowlist enforced on every future `boxkite exec` call: `get` shows
the current rules (empty means unrestricted, the default for every
account), `set <path-to-json-file>` replaces them wholesale from a JSON
array of plain command-name strings or `{command, args_allow?, args_deny?}`
objects, and `clear` restores the unrestricted default. This is a guardrail
against accidental/unexpected commands, **not** a sandbox-escape boundary —
allowing a general-purpose interpreter (`python3`, `bash`, `node`) through
the allowlist still permits arbitrary code to run once it starts; the
sandbox pod's own isolation (see "The isolation model" above) is what
actually constrains what that code can do.

`boxkite log`/`boxkite watch` (hosted mode only) read the audit-trail
routes the SDKs' `get_log`/`watch` methods call. Like `exec`/`files`, both
auto-pick the active session if exactly one exists, or take an explicit
`--session`.

`boxkite audit verify --db <path-to-audit.db> [--session <id>]` recomputes
a tamper-evident hash chain over a self-hosted `HashChainedSQLiteAuditSink`
database file and reports whether it's intact, or exactly which row it
first breaks at — read-only, works against a live, in-use file. This is the
self-hosted counterpart to `control-plane/scripts/verify_exec_log_chain.py`,
which does the same thing against a hosted control-plane's Postgres/
SQLite-backed `exec_log_entries` table.

Hosted mode is session-scoped because the control-plane manages multiple
concurrent sandboxes per account; local mode is intentionally *not* — a
single `boxkite up` stack has no session concept of its own, so `boxkite
session *`/`boxkite log`/`boxkite watch` refuse to run against it with an
explanation rather than inventing session management that doesn't exist
locally. Run `boxkite --help` (or `--help` on any subcommand) for the full
reference.

## Published packages and images

Everything below is `v0.1.0`.

| Package/image | Registry | Install/pull |
|---|---|---|
| `boxkite-sandbox` (this repo's root package — `import boxkite`) | [PyPI](https://pypi.org/project/boxkite-sandbox/) | `pip install boxkite-sandbox` |
| `boxkite-client` (`sdk-python/` — Python client for a control-plane you host) | [PyPI](https://pypi.org/project/boxkite-client/) | `pip install boxkite-client` |
| `boxkite-mcp` (`mcp-server/` — MCP server for a control-plane you host) | [PyPI](https://pypi.org/project/boxkite-mcp/) | `pip install boxkite-mcp` (or `pipx install boxkite-mcp` to run it as a standalone MCP server) |
| `boxkite-client` (`sdk-js/` — TypeScript/JavaScript client for a control-plane you host) | [npm](https://www.npmjs.com/package/boxkite-client) | `npm install boxkite-client` |
| `ghcr.io/harshitkmr10/boxkite-sandbox` | GHCR | `docker pull ghcr.io/harshitkmr10/boxkite-sandbox:0.1.0` (amd64 only — see `deploy/sandbox.Dockerfile`'s Chrome-for-Testing constraint) |
| `ghcr.io/harshitkmr10/boxkite-sandbox-minimal` | GHCR | `docker pull ghcr.io/harshitkmr10/boxkite-sandbox-minimal:0.1.0` (amd64 + arm64) |
| `ghcr.io/harshitkmr10/boxkite-sidecar` | GHCR | `docker pull ghcr.io/harshitkmr10/boxkite-sidecar:0.1.0` (amd64 + arm64) |
| `ghcr.io/harshitkmr10/boxkite-control-plane` | GHCR | `docker pull ghcr.io/harshitkmr10/boxkite-control-plane:0.1.0` (amd64 + arm64) |

Two `boxkite-client` packages exist under the same name on two different
registries (PyPI and npm) — same product, same versioning, different
ecosystem, no naming collision since PyPI and npm are separate namespaces.
Note the distinction from `boxkite-sandbox`: `boxkite-sandbox` is the
self-hosted core this whole README is about (`SandboxManager`, the tool
factories, the CLI); both `boxkite-client` packages and `boxkite-mcp` are
thin HTTP clients for a control-plane you run separately — see
[Self-hosting](#self-hosting) above for that distinction.

## Cookbook / examples

[`examples/`](examples/README.md) has runnable, verified examples: a full
LangGraph agent wired to all 5 sandbox tools, a minimal single-tool
LangChain agent, native OpenAI function-calling with no agent framework at
all, a LlamaIndex `ReActAgent`, Claude Code running headlessly inside a
sandbox, plain curl/Python-requests scripts against the sidecar's raw HTTP
API, a walkthrough of the control-plane API (signup -> sandbox -> exec ->
teardown), and a side-by-side demo of `python_interpreter`'s and
`node_interpreter`'s persistent, kept-alive statefulness across calls. Start
there if you want working code to copy from rather than piecing it together
from this README. Each SDK's own `README.md` (`sdk-python/`, `sdk-js/`,
`sdk-go/`, `sdk-rust/`) documents that client's method coverage in full, and
`mcp-server/README.md` documents the MCP server itself.

## Extending it: AuditSink and SessionMetadataStore

boxkite works with zero external dependencies — every tool operates against
the sidecar's own S3/Azure storage. Two optional hooks exist for callers who
want more:

- **`boxkite.audit.AuditSink`** — mirror file writes into your own system of
  record (a database-backed file browser, an audit log, a webhook). Every
  method is best-effort; a broken sink can never fail a sandbox operation.
- **`boxkite.session_store.SessionMetadataStore`** — reconstruct session
  ownership (org/work-item IDs, storage prefix) if a pod is lost before its
  K8s labels/annotations can be read during error recovery. Most callers
  don't need this — K8s pod metadata already covers the common recovery
  path.

Both default to no-ops. Implement only what you need; see the docstrings in
`src/boxkite/audit.py` and `src/boxkite/session_store.py`.

Ready-to-use, SQLite-backed reference implementations of both ship in the
same modules — `SQLiteAuditSink` and `SQLiteSessionMetadataStore` — for
callers who want a working durable store without writing one.

**`AuditSink` vs. the control-plane's webhooks — not the same thing.**
`AuditSink` is **pull**, in-process: your own code, embedding
`SandboxManager` directly, calls its methods (you could write one that
itself POSTs to a URL, but that's your code making that call, in your
process). A self-hosted `control-plane/` additionally ships genuine
**push**, out-of-process webhooks — `POST /v1/webhooks` registers a URL,
and the control plane itself calls it (with an HMAC-signed payload, retried
with backoff) when sandbox lifecycle events fire, independent of whether
your own process is even running — this only exists for the control-plane,
not for `SandboxManager` embedded directly.

## What's not included

This is a clean extraction, not a repackaging of a larger internal system.
Deliberately left out:

- **Any specific agent-orchestration framework.** The tools are plain
  LangChain `@tool`-decorated functions — wire them into LangGraph, a custom
  agent loop, or anything else that accepts LangChain tools.
- **A "skills injection" system.** The sidecar's `/ensure-skills` endpoint
  (materializing read-only skill files under `/mnt/skills`) is included
  because it's genuinely part of the sandbox's own file model, but the
  *policy* of which skills to inject for which agent is your application's
  concern, not this package's.
- **Any database or auth layer.** Session ownership lives on Kubernetes pod
  labels/annotations, which is enough to run this standalone. If you want
  cross-restart recovery after a pod is already gone, see
  `SessionMetadataStore` above.
- **Full IDE-shaped LSP (hover, signatureHelp, live diagnostics push,
  incremental sync, IDE-attach)** — inline squiggles/hover tooltips/
  keystroke-by-keystroke incremental sync are an interactive-editor UX,
  not a fit for boxkite's batch tool-calling model. **Agent-invokable
  completion is, however, shipped**: `lsp_start`/`lsp_completion`/
  `lsp_stop` (opt-in via `enable_lsp_tools` + `BOXKITE_LSP_ENABLED`) run a
  persistent `pyright` (Python) or `typescript-language-server`
  (TypeScript/JS) server per session, request/response, full-document sync.

## License

[FSL-1.1-Apache-2.0](LICENSE) — the Sentry-style Functional Source License.
You can use, modify, and self-host boxkite for effectively any purpose
except building a competing hosted/managed version of it. Every version
converts automatically to the fully permissive Apache License 2.0 two years
after its release. See [LICENSE](LICENSE) for the exact terms.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — we use the Developer Certificate of
Origin (`git commit -s`), not a CLA. Found a security issue? Please see
[SECURITY.md](SECURITY.md) and report it privately rather than filing a
public issue — this project executes arbitrary code, and a sandbox-escape
report deserves a fast, private path.
