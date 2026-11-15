#!/usr/bin/env python3
"""Copy the core RTL for simulation, removing `synopsys translate_off` regions.

Vivado honours `// synopsys translate_off` / `translate_on`, but Verilator does
not. Several upstream 3DO files use those pragmas to `define SIM`, which would
make Verilator compile behavioural stand-ins instead of the logic that is
actually synthesised. Stripping the regions makes the simulation see exactly
the same source as Vivado.

Usage: prep_rtl.py <rtl_dir> <out_dir>
"""
import os
import re
import sys

OFF = re.compile(r"//\s*(synopsys|synthesis|pragma)\s+translate_off")
ON = re.compile(r"//\s*(synopsys|synthesis|pragma)\s+translate_on")


def strip(text: str) -> str:
    out = []
    skipping = False
    for line in text.splitlines(keepends=True):
        if not skipping and OFF.search(line):
            skipping = True
            out.append("\n")
            continue
        if skipping:
            if ON.search(line):
                skipping = False
            out.append("\n")  # keep line numbers stable
            continue
        out.append(line)
    if skipping:
        raise SystemExit("unterminated translate_off region")
    return "".join(out)


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    for root, _, files in os.walk(src):
        for name in files:
            if not name.endswith((".sv", ".v", ".svh", ".vh")):
                continue
            sp = os.path.join(root, name)
            dp = os.path.join(dst, os.path.relpath(sp, src))
            os.makedirs(os.path.dirname(dp), exist_ok=True)
            with open(sp, encoding="latin-1") as f:
                text = f.read()
            new = strip(text)
            # Only rewrite when changed so make-style dependencies stay quiet.
            if os.path.exists(dp):
                with open(dp, encoding="latin-1") as f:
                    if f.read() == new:
                        continue
            with open(dp, "w", encoding="latin-1") as f:
                f.write(new)


if __name__ == "__main__":
    main()
