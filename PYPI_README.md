# boxkite-sandbox

**The missing batteries-included, self-hostable sandbox for agent code execution.**

Most "agent sandbox" projects give you raw isolation — a pod, a VM, a
container — and leave you to build the tool surface an LLM agent needs on
top of it. boxkite is the other half: a complete `bash`/`python`/file/
search/process tool surface (15 framework-agnostic tools — LangChain,
LangGraph, CrewAI, AutoGen, LlamaIndex, or plain OpenAI-style function
calling) running inside real Kubernetes pod isolation, hardened with
non-root execution, dropped Linux capabilities, a read-only root
filesystem, default-deny network egress, and secret-scrubbed command
output.

**Who this is for:** teams *building their own agent products* that need
isolated, multi-tenant code execution at scale — one Kubernetes pod per
session, many sessions, many tenants. If you just want your own coding
assistant to run shell commands on your own machine, this is the wrong
layer.

## Install

```bash
pip install boxkite-sandbox
```

Note the PyPI name is `boxkite-sandbox`, not `boxkite` (already taken) —
the import path is unaffected: `import boxkite`.

## Quickstart

```bash
git clone https://github.com/HarshitKmr10/boxkite.git boxkite && cd boxkite
pip install -e .
boxkite up
boxkite exec "python3 -c 'print(1 + 1)'"
```

```python
from uuid import uuid4
from boxkite import SandboxManager
from boxkite.tools import create_sandbox_tool_specs

manager = SandboxManager()
session_id = str(uuid4())
await manager.create_session(organization_id=uuid4(), session_id=session_id)

specs = create_sandbox_tool_specs(sandbox_manager=manager, session_id=session_id)
bash_tool = next(s for s in specs if s.name == "bash_tool")
result = await bash_tool.handler(command="echo hello from boxkite")
```

`boxkite.tools.adapters` converts the same tool specs for LangChain,
LlamaIndex, the OpenAI Agents SDK, or plain OpenAI/Anthropic/Gemini/Mistral
function-calling schemas — see the full integration table and every other
runtime mode (real Kubernetes, docker-compose, the `boxkite` CLI) in the
[full README](https://github.com/HarshitKmr10/boxkite#readme).

## Security

boxkite executes arbitrary, agent-generated code — its security posture is
layered defense in depth (non-root, dropped capabilities, read-only
filesystem, per-exec network isolation, no credential injection into
`/exec`). See [SECURITY.md](https://github.com/HarshitKmr10/boxkite/blob/main/SECURITY.md)
for the full model and known follow-ups before deploying this beyond local dev.

## License

[FSL-1.1-Apache-2.0](https://github.com/HarshitKmr10/boxkite/blob/main/LICENSE)
— free to self-host for effectively any purpose except building a competing
hosted/managed version. Converts to Apache-2.0 two years after each release.

## Links

[GitHub](https://github.com/HarshitKmr10/boxkite) ·
[Full README](https://github.com/HarshitKmr10/boxkite#readme) ·
[Docs](https://github.com/HarshitKmr10/boxkite/tree/main/docs) ·
[Issues](https://github.com/HarshitKmr10/boxkite/issues)
