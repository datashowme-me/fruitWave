"""Extract the 40 original fruit PNGs from the approved PRD DOCX export.

The semantic mapping was verified against a contact sheet from document
revision AHj4eMSBFqyUvXobDuLRyBpkCUJ2grbbT5bvx5F4cQV8NbDQS_W11xD6NAU9mj65ybmf98OXnmVWdqMOX3wlug-jE01yNfCA97T_oH0HZnE.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

from PIL import Image


DOCUMENT_ID = "1tzqIUol1BEAEpyYdKFmQUmWwURed_3voLYmmjdvpZaA"
DOCUMENT_URL = f"https://docs.google.com/document/d/{DOCUMENT_ID}"
DOCUMENT_TITLE = "Apple TV 体感切水果｜Codex 与 Claude 开发任务书 v1.0"
DOCUMENT_REVISION = "AHj4eMSBFqyUvXobDuLRyBpkCUJ2grbbT5bvx5F4cQV8NbDQS_W11xD6NAU9mj65ybmf98OXnmVWdqMOX3wlug-jE01yNfCA97T_oH0HZnE"
DOCUMENT_MODIFIED_TIME = "2026-10-19T07:33:49.063Z"

MEDIA_MAP = {
    1: ("cherry", "cut"),
    2: ("plum", "cut"),
    3: ("apple", "cut"),
    4: ("pomegranate", "whole"),
    5: ("peach", "whole"),
    6: ("persimmon", "cut"),
    7: ("blueberry", "whole"),
    8: ("cantaloupe", "cut"),
    9: ("apple", "whole"),
    10: ("orange", "whole"),
    11: ("coconut", "whole"),
    12: ("plum", "whole"),
    13: ("pineapple", "whole"),
    14: ("orange", "cut"),
    15: ("dragon_fruit", "whole"),
    16: ("lemon", "cut"),
    17: ("pear", "whole"),
    18: ("peach", "cut"),
    19: ("coconut", "cut"),
    20: ("persimmon", "whole"),
    21: ("mango", "cut"),
    22: ("dragon_fruit", "cut"),
    23: ("watermelon", "cut"),
    24: ("pomegranate", "cut"),
    25: ("grape", "whole"),
    26: ("pear", "cut"),
    27: ("kiwi", "cut"),
    28: ("grape", "cut"),
    29: ("lemon", "whole"),
    30: ("pineapple", "cut"),
    31: ("mango", "whole"),
    32: ("blueberry", "cut"),
    33: ("strawberry", "cut"),
    34: ("cantaloupe", "whole"),
    35: ("banana", "whole"),
    36: ("strawberry", "whole"),
    37: ("cherry", "whole"),
    38: ("kiwi", "whole"),
    39: ("watermelon", "whole"),
    40: ("banana", "cut"),
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    args.destination.mkdir(parents=True, exist_ok=True)
    assets = []
    with zipfile.ZipFile(args.docx) as archive:
        media_names = {name for name in archive.namelist() if name.startswith("word/media/")}
        expected_names = {f"word/media/image{index}.png" for index in MEDIA_MAP}
        if media_names != expected_names:
            missing = sorted(expected_names - media_names)
            extra = sorted(media_names - expected_names)
            raise RuntimeError(f"PRD media set changed; missing={missing}, extra={extra}")

        for index, (fruit, role) in MEDIA_MAP.items():
            source_name = f"word/media/image{index}.png"
            data = archive.read(source_name)
            target = args.destination / fruit / f"{role}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

            with Image.open(target) as image:
                if image.format != "PNG":
                    raise RuntimeError(f"Not a PNG: {source_name}")
                width, height = image.size
                mode = image.mode
            if (width, height) != (1254, 1254):
                raise RuntimeError(f"Unexpected dimensions for {source_name}: {width}x{height}")

            assets.append(
                {
                    "media_index": index,
                    "docx_path": source_name,
                    "fruit": fruit,
                    "role": role,
                    "path": target.relative_to(args.destination.parent.parent.parent).as_posix(),
                    "sha256": sha256(data),
                    "width": width,
                    "height": height,
                    "mode": mode,
                }
            )

    manifest = {
        "schema_version": 1,
        "source_kind": "google_doc_docx_export",
        "source_id": DOCUMENT_ID,
        "source_url": DOCUMENT_URL,
        "source_title": DOCUMENT_TITLE,
        "source_revision": DOCUMENT_REVISION,
        "source_modified_time": DOCUMENT_MODIFIED_TIME,
        "inline_object_count": 40,
        "original_bytes_preserved": True,
        "classification_method": "manual visual verification of a numbered contact sheet",
        "asset_count": len(assets),
        "fruit_count": len({asset["fruit"] for asset in assets}),
        "roles": ["whole", "cut"],
        "assets": assets,
    }
    (args.destination.parent / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"PRD_FRUIT_PNGS_OK assets={len(assets)} fruits={manifest['fruit_count']} destination={args.destination}")


if __name__ == "__main__":
    main()
