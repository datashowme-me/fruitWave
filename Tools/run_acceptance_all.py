#!/usr/bin/env python3
"""Run analyze_acceptance.run() for all pending fruits, 4 workers."""
from __future__ import annotations

import concurrent.futures
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from analyze_acceptance import run  # noqa: E402

FRUITS = ["cherry", "plum", "peach", "blueberry", "grape", "strawberry", "watermelon",
          "cantaloupe", "kiwi", "coconut", "banana", "pear", "persimmon", "pineapple",
          "pomegranate", "dragon_fruit", "mango"]


def main() -> None:
    out = Path(__file__).resolve().parent / "acceptance_summary.jsonl"
    err = Path(__file__).resolve().parent / "acceptance_errors.log"
    with open(out, "w") as results, open(err, "w") as errors:
        with concurrent.futures.ProcessPoolExecutor(max_workers=4) as ex:
            futures = {ex.submit(run, f): f for f in FRUITS}
            for future in concurrent.futures.as_completed(futures):
                fruit = futures[future]
                try:
                    results.write(future.result() + "\n")
                    results.flush()
                except Exception as exc:  # noqa: BLE001 - evidence must record failures
                    errors.write(f"{fruit}: {exc!r}\n")
                    errors.flush()
    print(f"done: {len(FRUITS)} fruits")


if __name__ == "__main__":
    main()
