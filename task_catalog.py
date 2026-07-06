"""Per-task TaskSpec catalog."""

from dataclasses import dataclass
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
TASK_ROOT = ROOT_DIR / "tasks"


@dataclass(frozen=True)
class TaskSpec:
    task_id: str
    slug: str
    prompt: str
    track: str
    variant: str
    language: str
    module: str
    toolchain: str


# NOTE: the task directory is spelled "interrupt_contoller_cocotb_dv" (missing an 'r');
# task_id MUST match the directory name so prompt/donotaccess/baseline resolve.
INTERRUPT_CONTROLLER_COCOTB_DV = TaskSpec(
    task_id="interrupt_contoller_cocotb_dv",
    slug="interrupt-controller-cocotb-dv",
    prompt=(TASK_ROOT / "interrupt_contoller_cocotb_dv" / "prompt.md").read_text(
        encoding="utf-8"
    ),
    track="verification",
    variant="authoring",
    language="python+cocotb",
    module="interrupt_controller_apb",
    toolchain="cocotb+verilator",
)

TASK_SPECS = [
    INTERRUPT_CONTROLLER_COCOTB_DV,
]
TASK_SPECS_BY_ID = {spec.task_id: spec for spec in TASK_SPECS}
