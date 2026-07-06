"""chiprama interrupt-controller: HUD v6 chip-design environment.

One cocotb DV-authoring track on the ``interrupt_controller_apb`` module: the agent writes a
cocotb testbench, graded by golden-RTL pass + mutant-kill + coverage + hygiene.

Isolation (uid wall): the env serves and grades as root, but every agent shell command is
demoted to the unprivileged ``agent`` uid via ``setpriv`` (see ``_AgentWorkspace``), so the
agent can't read the root:700 answer key at ``/donotaccess/<id>`` while the grader can.
"""

# NOTE: this file deliberately omits ``from __future__ import annotations``. Do NOT add it
# back: under it, an @env.template parameter typed with Literal/Optional/an alias/a Pydantic
# model crashes at deploy/start (the server runs ``TypeAdapter`` on a string forward-ref ->
# PydanticUserError, surfaced as ``-32000``). Without it, annotations resolve to real objects
# and any param type works. Known SDK bug, leave the future-import out.
import os
import sys

from hud import Environment
from hud.environment import Mount, Workspace

from grader import evaluate_task
from scenario_helpers import WORKSPACE_ROOT, setup_task
from task_catalog import TASK_SPECS_BY_ID

AGENT_UID = int(os.environ.get("AGENT_UID", "1000"))
AGENT_GID = int(os.environ.get("AGENT_GID", "1000"))


class _AgentWorkspace(Workspace):
    """A Workspace whose interactive shell runs as the unprivileged ``agent`` uid.

    The env serves as root so the grader can read the root:700 answer key, but every agent
    command is wrapped in ``setpriv --reuid agent`` so the agent's shell cannot. No-op when
    not running as root (e.g. local dev), where the shell already has no elevated access.
    """

    def shell_argv(self, command=None, *, cwd=None, env=None):
        argv = super().shell_argv(command, cwd=cwd, env=env)
        if sys.platform != "win32" and hasattr(os, "geteuid") and os.geteuid() == 0:
            argv = [
                "setpriv",
                "--reuid", str(AGENT_UID),
                "--regid", str(AGENT_GID),
                "--clear-groups",
                "--",
                *argv,
            ]
        return argv


# The env name MUST be a string literal: `hud deploy` resolves it by statically parsing
# this call, so a variable (env-var lookup) fails with "constructed without an explicit name".
env = Environment(name="chiprama-interrupt-controller-v6")

# network=False air-gaps the workspace. HOME points at the agent's home so tools that write
# there don't hit the root-owned /root. The EDA toolchain (verilator) lives under
# /opt/oss-cad-suite locally; optional=True makes the mount a no-op when the path is absent.
_ws = _AgentWorkspace(
    WORKSPACE_ROOT,
    network=False,
    env={"HOME": "/home/agent", "USER": "agent", "LOGNAME": "agent"},
    mounts=(
        Mount("ro", src="/opt/oss-cad-suite", dst="/opt/oss-cad-suite", optional=True),
    ),
)


@env.initialize
async def _up() -> None:
    await _ws.start()
    env.add_capability(_ws.capability("shell"))


@env.shutdown
async def _down() -> None:
    await _ws.stop()


@env.template(id="verilog_task")
async def verilog_task(task_id: str, validate_mode: str | None = None):
    """Reset the workspace to the task baseline, prompt the agent, then grade with the
    hidden grader (verilator + cocotb + mutant-kill + coverage + hygiene)."""
    setup_meta = setup_task(task_id, validate_mode=validate_mode)
    answer = yield TASK_SPECS_BY_ID[task_id].prompt

    evaluation = evaluate_task(task_id)
    info = dict(evaluation.info or {})
    info["setup"] = setup_meta
    info["final_answer"] = None if answer is None else str(answer)
    evaluation.info = info
    yield evaluation
