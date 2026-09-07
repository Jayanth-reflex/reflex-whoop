#!/usr/bin/env python3
"""Convert a ReflexWhoop export's CSVs to Parquet, on the Mac — there's no
maintained pure-Swift Parquet writer worth depending on for the app itself
(docs/design.md), so this runs after the fact on an already-exported folder.

Usage:
    python tools/to_parquet.py <export_dir>

Writes <export_dir>/parquet/<table>.parquet for every *.csv in export_dir.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: to_parquet.py <export_dir>", file=sys.stderr)
        sys.exit(1)

    export_dir = Path(sys.argv[1])
    csv_paths = sorted(export_dir.glob("*.csv"))
    if not csv_paths:
        print(f"No CSVs found in {export_dir}", file=sys.stderr)
        sys.exit(1)

    out_dir = export_dir / "parquet"
    out_dir.mkdir(exist_ok=True)

    for csv_path in csv_paths:
        df = pd.read_csv(csv_path)
        out_path = out_dir / f"{csv_path.stem}.parquet"
        df.to_parquet(out_path, engine="pyarrow", index=False)
        print(f"{csv_path.name} -> {out_path.relative_to(export_dir)} ({len(df)} rows)")


if __name__ == "__main__":
    main()
