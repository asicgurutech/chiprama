#!/usr/bin/env python3
"""Trusted (grader-authored) cocotb runner. Split into two independent stages so the DUT
source (golden or mutant) is never visible to the stage that runs the agent-authored
testbench:

  --stage build : compiles --rtl with verilator into --build-dir. Needs source access;
                  run this stage in a directory the agent's uid cannot read.
  --stage test  : runs --tests against the simulation executable already sitting in
                  --build-dir (no RTL source needed - verilator's compiled binary is
                  self-contained). Exposes the coverage-file path via INTC_COVERAGE_FILE.
                  Returns 0 iff every test passed and at least one test ran.

grade.py runs the two stages in separate temp directories: the build directory stays
root-owned (or whatever uid the grader runs as) and is torn down before the test stage
starts, so the submitted testbench - which runs uid-dropped inside the test-stage
directory - only ever has read access to the compiled simulator, never the .sv text.
"""

import argparse
import os
import platform
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner


def read_filelist(path: Path) -> tuple[list[Path], list[Path]]:
    base = path.parent
    sources: list[Path] = []
    include_dirs: list[Path] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            for include_dir in line[len("+incdir+") :].split("+"):
                if include_dir:
                    include_dirs.append((base / include_dir).resolve())
            continue
        if line.startswith("-I"):
            include_dirs.append((base / line[2:].strip()).resolve())
            continue
        sources.append((base / line).resolve())
    return sources, include_dirs


def configure_tool_environment() -> None:
    os.environ.pop("LC_ALL", None)
    os.environ["LANG"] = "en_US.UTF-8"
    os.environ["LC_CTYPE"] = "en_US.UTF-8"
    if platform.system() == "Darwin":
        path_parts = []
        for candidate in [
            Path("/opt/homebrew/bin"),
            Path.home() / "utils" / "oss-cad-suite" / "bin",
        ]:
            if candidate.is_dir():
                path_parts.append(str(candidate))
        path_parts.extend(["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        path_parts.append(os.environ.get("PATH", ""))
        os.environ["PATH"] = ":".join(part for part in path_parts if part)
        os.environ["AR"] = "/usr/bin/ar"
        os.environ["RANLIB"] = "/usr/bin/ranlib"
    else:
        for candidate in (
            Path("/opt/oss-cad-suite/bin"),
            Path.home() / "utils" / "oss-cad-suite" / "bin",
        ):
            if candidate.is_dir():
                os.environ["PATH"] = f"{candidate}:{os.environ.get('PATH', '')}"
                break


def do_build(args: argparse.Namespace) -> int:
    if not args.rtl:
        raise SystemExit("--rtl is required for --stage build")
    rtl = Path(args.rtl).resolve()
    filelist = Path(args.filelist).resolve() if args.filelist else None
    include_dirs = [Path(item).resolve() for item in args.include_dir]
    build_dir = Path(args.build_dir).resolve()

    sources: list[Path] = []
    if filelist:
        sources, filelist_include_dirs = read_filelist(filelist)
        include_dirs.extend(filelist_include_dirs)
    if rtl not in sources:
        sources.append(rtl)

    runner = get_runner("verilator")
    runner.build(
        sources=sources,
        includes=include_dirs,
        hdl_toplevel=args.top,
        build_args=["--timing", "-Wno-fatal", "-Wno-WIDTHEXPAND"],
        build_dir=build_dir,
        always=True,
        clean=True,
    )
    return 0 if (build_dir / args.top).exists() else 1


def do_test(args: argparse.Namespace) -> int:
    if not args.tests:
        raise SystemExit("--tests is required for --stage test")
    tests = Path(args.tests).resolve()
    build_dir = Path(args.build_dir).resolve()
    coverage_file = Path(args.coverage_file).resolve()
    results_xml = Path(args.results_xml).resolve()

    coverage_file.parent.mkdir(parents=True, exist_ok=True)
    results_xml.parent.mkdir(parents=True, exist_ok=True)
    if coverage_file.exists():
        coverage_file.unlink()

    runner = get_runner("verilator")
    runner.test(
        hdl_toplevel=args.top,
        # Explicit: this Runner instance never had .build() called on it (the build step
        # ran in a separate, source-visible process - see grade.py), so the auto-detection
        # in _check_hdl_toplevel_lang, which inspects sources set by .build(), would crash.
        hdl_toplevel_lang="verilog",
        test_module=tests.stem,
        test_dir=tests.parent,
        build_dir=build_dir,
        results_xml=str(results_xml),
        extra_env={
            **os.environ,
            "INTC_COVERAGE_FILE": str(coverage_file),
        },
    )
    tree = ET.parse(results_xml)
    root = tree.getroot()
    suites = root.findall(".//testsuite")
    if root.tag == "testsuite":
        suites.append(root)
    failures = sum(int(suite.attrib.get("failures", "0")) for suite in suites)
    errors = sum(int(suite.attrib.get("errors", "0")) for suite in suites)
    tests_run = sum(
        int(suite.attrib.get("tests", str(len(suite.findall("testcase")))))
        for suite in suites
    )
    failures += len(root.findall(".//failure"))
    errors += len(root.findall(".//error"))
    if tests_run == 0 or failures or errors:
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True, choices=("build", "test"))
    parser.add_argument("--rtl", default=None, help="Path to the DUT SystemVerilog file (stage=build)")
    parser.add_argument("--tests", default=None, help="Path to cocotb test module (stage=test)")
    parser.add_argument("--filelist", default=None, help="Optional Verilog source filelist (stage=build)")
    parser.add_argument(
        "--include-dir",
        action="append",
        default=[],
        help="Verilog include directory. May be passed multiple times (stage=build).",
    )
    parser.add_argument("--build-dir", default="build/cocotb")
    parser.add_argument("--coverage-file", default="reports/coverage.json")
    parser.add_argument("--results-xml", default="reports/results.xml")
    parser.add_argument("--top", default="interrupt_controller_apb")
    args = parser.parse_args()

    configure_tool_environment()
    if args.stage == "build":
        return do_build(args)
    return do_test(args)


if __name__ == "__main__":
    raise SystemExit(main())
