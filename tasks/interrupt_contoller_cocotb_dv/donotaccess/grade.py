#!/usr/bin/env python3
"""Hidden grader for the interrupt_controller_apb cocotb DV-authoring task.

Runs the SUBMITTED testbench against:
  - golden RTL          -> must PASS               (golden_pass, 0.25; HARD CAP: fail => 0)
  - each hidden mutant   -> must FAIL (be killed)    (mutant_kill,  0.45)
  - coverage.json points  written during the golden run (coverage, 0.20)
  - static hygiene of the testbench source            (testbench_hygiene, 0.10)

Agent-authored code (the testbench) is executed uid-dropped to 1000 in a staged tempdir so
it cannot read the root:700 /donotaccess answer key while the grader runs as root.
"""

import argparse
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOP = "interrupt_controller_apb"
DUT_BASENAME = "interrupt_controller.sv"
GOLDEN_NAME = "interrupt_controller_golden.sv"
TESTBENCH_REL = Path("dv") / "cocotb" / "test_interrupt_controller.py"
SOLUTION_REL = Path("solution") / "test_interrupt_controller.py"

# Privilege-drop prefix for executing AGENT-AUTHORED code (the cocotb testbench). In the
# deployed image the grader runs as root and the hidden answer key lives at /donotaccess
# (root:700); dropping to uid 1000 (`agent`) means agent code the grader executes cannot
# read the golden/mutants/rubric. Locally (non-root dev), this is a no-op.
_drop = (
    ["setpriv", "--reuid", "1000", "--regid", "1000", "--clear-groups", "--"]
    if (hasattr(os, "geteuid") and os.geteuid() == 0)
    else []
)


def _chown_tree_to_agent(path: Path) -> None:
    """chown a staged work tree to uid/gid 1000 so the dropped subprocess can use it
    (image/root only; no-op locally)."""
    if not (hasattr(os, "geteuid") and os.geteuid() == 0):
        return
    for item in [path, *path.rglob("*")]:
        try:
            os.chown(item, 1000, 1000)
        except (PermissionError, FileNotFoundError, NotADirectoryError):
            pass


REQUIRED_COVERAGE = [
    "reset",
    "line_interrupt",
    "messaged_apb",
    "pwdata_equals_isr",
    "paddr_config",
    "pslverr_sticky",
    "apb_err_w1c",
    "sw_interrupt",
    "pending_irq_during_apb",
    "apb_delayed_reset",
    "apb_no_response_reset",
    "irq_priority_order",
    "irq_masking",
    "edge_level_trigger",
    "ipr_set_ack_race",
    "apb_threshold_boundary",
]
MUTANTS = [
    "intc_line_int_dead.sv",
    "intc_msg_no_apb.sv",
    "intc_pwdata_wrong.sv",
    "intc_paddr_byteswap.sv",
    "intc_pslverr_ignored.sv",
    "intc_pending_dropped.sv",
    "intc_no_soft_reset.sv",
    "intc_no_wdt_hard_reset.sv",
    "intc_priority_swapped.sv",
    "intc_mask_bypassed.sv",
    "intc_trig_mode_stuck.sv",
    "intc_ipr_new_irq_race.sv",
    "intc_soft_reset_offbyone.sv",
]


def tool_env() -> dict[str, str]:
    env = os.environ.copy()
    env.pop("LC_ALL", None)
    env["LANG"] = "en_US.UTF-8"
    env["LC_CTYPE"] = "en_US.UTF-8"
    # When the grader is root (deployed image), subprocesses are dropped to uid 1000; give
    # them an accessible HOME so child Path.home() lookups don't hit /root (mode 700).
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        env["HOME"] = "/home/agent"
    if platform.system() == "Darwin":
        path_parts = []
        for candidate in [
            Path("/opt/homebrew/bin"),
            Path.home() / "utils" / "oss-cad-suite" / "bin",
        ]:
            if candidate.is_dir():
                path_parts.append(str(candidate))
        path_parts.extend(["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        path_parts.append(env.get("PATH", ""))
        env["PATH"] = ":".join(part for part in path_parts if part)
        env["AR"] = "/usr/bin/ar"
        env["RANLIB"] = "/usr/bin/ranlib"
    else:
        for candidate in (
            Path("/opt/oss-cad-suite/bin"),
            Path.home() / "utils" / "oss-cad-suite" / "bin",
        ):
            if candidate.is_dir():
                env["PATH"] = f"{candidate}:{env.get('PATH', '')}"
                break
    return env


def run(args: list[str], *, cwd: Path, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    """Fail-closed runner for agent-authored code: a timeout SIGKILLs the whole process
    group (start_new_session=True) and returns a non-zero CompletedProcess rather than
    letting TimeoutExpired propagate out of grade(). A hung/timed-out grader therefore
    scores as not-passed (reward 0) and leaves no orphaned verilator/cocotb children."""
    proc = subprocess.Popen(
        args,
        cwd=cwd,
        env=tool_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        stdout, _ = proc.communicate(timeout=timeout)
        return subprocess.CompletedProcess(args, proc.returncode, stdout, None)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            stdout, _ = proc.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            stdout = ""
        return subprocess.CompletedProcess(
            args,
            proc.returncode if proc.returncode is not None else -signal.SIGKILL,
            (stdout or "") + f"\n[grader] timed out after {timeout}s; process group killed\n",
            None,
        )


def run_cocotb(hidden_root: Path, rtl: Path, tests: Path, label: str) -> dict[str, object]:
    """Run the submitted testbench against `rtl`.

    Split into two isolated stages so the testbench never gets read access to the DUT
    source (golden or mutant), and so nothing about the working directories differs
    between a golden run and a mutant run:

      1. build (trusted): compiles `rtl` with verilator in a directory that is never
         chowned to the agent uid and is torn down at the end of this function. Runs at
         the grader's own privilege (root in the deployed image), NOT uid-dropped, since
         the compiler needs to read the DUT source.
      2. test (agent-visible): only the compiled simulation executable - not the .sv
         source, not the generated C++ - is copied into a second, generically-named
         directory, which is then chowned to the agent uid and used to run the submitted
         testbench uid-dropped. The executable is self-contained (verilator's `test()`
         step just execs it - see cocotb_tools.runner.Verilator._test_command), so no
         DUT source or transpiled logic is ever reachable from this stage.

    Directory prefixes deliberately carry no DUT-identity information (never `label`), so
    a golden run and a mutant run are structurally indistinguishable to code running
    inside them (cwd, INTC_COVERAGE_FILE, results/coverage paths, permissions all match).
    """
    with tempfile.TemporaryDirectory(prefix="intc-dv-build-") as build_td:
        build_root = Path(build_td)
        rtl_copy = build_root / DUT_BASENAME
        shutil.copy2(rtl, rtl_copy)
        build_runner = build_root / "run_cocotb_hidden.py"
        shutil.copy2(hidden_root / "run_cocotb_hidden.py", build_runner)
        sim_build_dir = build_root / "sim_build"

        build_result = run(
            [
                sys.executable,
                str(build_runner),
                "--stage", "build",
                "--rtl", str(rtl_copy),
                "--top", TOP,
                "--build-dir", str(sim_build_dir),
            ],
            cwd=build_root,
            timeout=180,
        )
        compiled_sim = sim_build_dir / TOP
        if build_result.returncode != 0 or not compiled_sim.exists():
            return {
                "label": label,
                "passed": False,
                "returncode": build_result.returncode or 1,
                "coverage": {},
                "log": build_result.stdout[-6000:],
            }

        with tempfile.TemporaryDirectory(prefix="intc-dv-run-") as run_td:
            run_root = Path(run_td)
            test_dir = run_root / "tests"
            test_dir.mkdir()
            shutil.copy2(tests, test_dir / "test_interrupt_controller.py")
            run_build_dir = run_root / "build"
            run_build_dir.mkdir()
            # Only the compiled binary crosses into the agent-visible tree - no .sv source,
            # no verilator-generated C++.
            shutil.copy2(compiled_sim, run_build_dir / TOP)
            (run_build_dir / TOP).chmod(0o755)
            coverage = run_root / "coverage.json"
            results = run_root / "results.xml"
            # The trusted hidden runner lives in /donotaccess (root:700) which uid 1000
            # cannot read; stage a copy into the run dir so the dropped interpreter can
            # load it. The runner is grader-authored (trusted); only the testbench it
            # imports is agent code.
            test_runner = run_root / "run_cocotb_hidden.py"
            shutil.copy2(hidden_root / "run_cocotb_hidden.py", test_runner)

            # Hand the staged run dir to uid 1000 so the dropped subprocess can read the
            # compiled sim + runner and write coverage/results, while walled out of the
            # build dir (which holds the DUT source and is about to be torn down anyway).
            _chown_tree_to_agent(run_root)
            result = run(
                [
                    *_drop,
                    sys.executable,
                    str(test_runner),
                    "--stage", "test",
                    "--tests", str(test_dir / "test_interrupt_controller.py"),
                    "--top", TOP,
                    "--build-dir", str(run_build_dir),
                    "--coverage-file", str(coverage),
                    "--results-xml", str(results),
                ],
                cwd=run_root,
                timeout=180,
            )
            coverage_data: dict[str, bool] = {}
            if coverage.exists():
                try:
                    coverage_data = json.loads(coverage.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    coverage_data = {}
            return {
                "label": label,
                "passed": result.returncode == 0,
                "returncode": result.returncode,
                "coverage": coverage_data,
                "log": result.stdout[-6000:],
            }


def hygiene_score(testbench: Path) -> dict[str, object]:
    text = testbench.read_text(encoding="utf-8")
    suspicious = []
    for pattern in ["/donotaccess", "donotaccess", "interrupt_controller_golden", "run_cocotb_hidden"]:
        if pattern in text:
            suspicious.append(pattern)
    has_cocotb_test = "@cocotb.test" in text
    uses_clock_edges = "RisingEdge" in text or "FallingEdge" in text
    uses_coverage_helper = len(re.findall(r"\bmark_coverage\s*\(", text)) > 1
    score = 1.0 if not suspicious and has_cocotb_test and uses_clock_edges and uses_coverage_helper else 0.0
    return {
        "score": score,
        "suspicious_patterns": suspicious,
        "has_cocotb_test": has_cocotb_test,
        "uses_clock_edges": uses_clock_edges,
        "uses_coverage_helper": uses_coverage_helper,
    }


def grade(
    root: Path,
    rtl_override: Path | None = None,
    hidden_root: Path | None = None,
    test_override: Path | None = None,
) -> dict[str, object]:
    hidden_root = hidden_root or root / "donotaccess"
    testbench = test_override or root / TESTBENCH_REL
    golden_rtl = rtl_override or hidden_root / GOLDEN_NAME

    golden = run_cocotb(hidden_root, golden_rtl, testbench, "golden")
    golden_raw = 1.0 if golden["passed"] else 0.0

    mutant_results = []
    killed = 0
    if golden["passed"]:
        for mutant_name in MUTANTS:
            mutant_result = run_cocotb(
                hidden_root,
                hidden_root / "mutants" / mutant_name,
                testbench,
                mutant_name.removesuffix(".sv"),
            )
            mutant_result["killed"] = not mutant_result["passed"]
            killed += 1 if mutant_result["killed"] else 0
            mutant_results.append(mutant_result)
    mutant_raw = killed / len(MUTANTS)

    coverage_data = golden.get("coverage", {}) if isinstance(golden.get("coverage"), dict) else {}
    covered = [point for point in REQUIRED_COVERAGE if coverage_data.get(point)]
    coverage_raw = len(covered) / len(REQUIRED_COVERAGE)
    hygiene = hygiene_score(testbench)
    hygiene_raw = float(hygiene["score"])

    reward = round(
        0.25 * golden_raw
        + 0.45 * mutant_raw
        + 0.20 * coverage_raw
        + 0.10 * hygiene_raw,
        6,
    )
    hard_caps = []
    if not golden["passed"]:
        reward = 0.0
        hard_caps.append("golden_dut_failed")

    return {
        "reward": reward,
        "hard_caps": hard_caps,
        "subscores": {
            "golden_pass": {
                "weight": 0.25,
                "raw_score": golden_raw,
                "weighted_score": 0.25 * golden_raw,
                "result": golden,
            },
            "mutant_kill": {
                "weight": 0.45,
                "raw_score": mutant_raw,
                "weighted_score": 0.45 * mutant_raw,
                "result": {
                    "killed": killed,
                    "total": len(MUTANTS),
                    "mutants": mutant_results,
                },
            },
            "coverage": {
                "weight": 0.20,
                "raw_score": coverage_raw,
                "weighted_score": 0.20 * coverage_raw,
                "result": {
                    "covered": covered,
                    "required": REQUIRED_COVERAGE,
                    "coverage_data": coverage_data,
                },
            },
            "testbench_hygiene": {
                "weight": 0.10,
                "raw_score": hygiene_raw,
                "weighted_score": 0.10 * hygiene_raw,
                "result": hygiene,
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--tests", default=None, help="Alternate cocotb testbench")
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args()

    result = grade(
        Path(args.root).resolve(),
        test_override=Path(args.tests).resolve() if args.tests else None,
    )
    if args.pretty:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(json.dumps(result, sort_keys=True))
    return 0 if result["reward"] == 1.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
