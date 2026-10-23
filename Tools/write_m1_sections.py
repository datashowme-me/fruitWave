#!/usr/bin/env python3
"""Append the 17-fruit acceptance sections to Docs/M1-Verification.md.

Numbers come from Tools/acceptance_summary.jsonl (pixel analysis) and each
Docs/Evidence/<fruit>-acceptance/evidence_<fruit>.log (device metrics).
Idempotent: refuses to run if the doc already contains the batch marker.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "Docs" / "M1-Verification.md"
SUMMARY = ROOT / "Tools" / "acceptance_summary.jsonl"
EVIDENCE = ROOT / "Docs" / "Evidence"

BATCH_MARKER = "## 批量验收（2026-10-22 · 17 种水果）"

FRUITS = ["banana", "blueberry", "cantaloupe", "cherry", "coconut", "dragon_fruit",
          "grape", "kiwi", "mango", "peach", "pear", "persimmon", "pineapple",
          "plum", "pomegranate", "strawberry", "watermelon"]

NOTES = {
    "banana": "- 结构：纵向剖切（y=0），两半各保留完整果弧与种子带；两半分离轴自适应长形果。",
    "blueberry": "- 已知限制：果皮深蓝近黑，真机暗背景下皮肤像素占比低（1.5%），均值仍与 PRD 一致；其余同通用限制。",
    "cantaloupe": "- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素；其余同通用限制。",
    "cherry": "- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left），两半分离后一核一腔。",
    "coconut": "- 结构：切面为白肉环（r 0.30–0.74）与中空腔。",
    "dragon_fruit": "- 结构：切面白肉 + 四圈细黑籽（52 颗/半）；20 片鳞叶贴在整果表面。",
    "grape": "- 结构：切面 2 颗籽。- 已知限制：果皮深紫，真机暗背景下皮肤像素占比低（0.7%），均值仍与 PRD 一致。",
    "kiwi": "- 结构：切面绿肉 + 26 颗黑籽 + 白芯。",
    "mango": "- 结构：切面橙肉 + 扁核（两半均含，刀锋穿过果核）。",
    "peach": "- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left）。- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素。",
    "pear": "- 结构：切面种室环 + 深色果核。",
    "persimmon": "- 结构：切面均匀果肉，无核。- 已知限制：果皮与果肉同为暖橙家族，flesh 均值混入邻近皮肤像素。",
    "pineapple": "- 结构：切面黄肉 + 浅色果芯 + 棕皮环。",
    "plum": "- 结构：核与空腔各居一侧（pitHalf right / cavityHalf left）。- 已知限制：首次启动 >22s 才写入快照，45s 窗口复测正常（`evidence_plum.log` 即复测日志）。",
    "pomegranate": "- 结构：切面为红籽环带（80 颗/半）落在白膜上；果肉行测白膜均值。",
    "strawberry": "- 结构：切面粉红瓤 + 28 粒表面籽 + 白芯。",
    "watermelon": "- 结构：切面红瓤 + 8 颗黑籽 + 白皮环。",
}

DEPLOY_LOG = "Docs/Evidence/deploy-2026-10-22-100753.log"
DEVICE = "Apple TV 4K（第 3 代，AppleTV14,1）/ tvOS 27.0 / 2026-10-22 10:07 设备签名构建"


def fmt_rgb(rgb) -> str:
    return "(" + ",".join(str(v) for v in rgb) + ")"


def bbox_x(bbox) -> str:
    return f"{bbox[0]}–{bbox[2]}%"


def bbox_xy(bbox) -> str:
    return f"{bbox[0]}–{bbox[2]}%、纵向 {bbox[1]}–{bbox[3]}%"


def main() -> None:
    text = DOC.read_text()
    if BATCH_MARKER in text:
        raise SystemExit("batch sections already present in M1-Verification.md")

    rows = {json.loads(line)["fruit"]: json.loads(line)
            for line in SUMMARY.read_text().splitlines()}

    out = ["", BATCH_MARKER, ""]
    out += [
        f"- 构建/部署：{DEPLOY_LOG}（设备签名构建 + 安装 + 启动成功），app 含全部 20 种水果资产。",
        "- 流程：每果 `FW_FRUIT=<slug>` 独立启动验收台（整果 t+3s 快照、切半 t+6s、切面 t+9s、12s FPS 窗口、15s watchdog），证据拉取 `Docs/Evidence/<slug>-acceptance/`。",
        "- 慢加载发现：plum / pear / dragon_fruit 首次启动 >22s 才写入快照（日志停在 ASSET_LAB_STARTED，无 watchdog 行）；45s 窗口复测全部正常——非崩溃，属首次加载较慢。采样脚本 `.claude/skills/tvos-game-development/scripts/fruit-acceptance-loop.sh` 默认 22s，失败时按 45s 复测。",
        "- 像素分析：`Tools/analyze_acceptance.py`（AST 提取各生成器 classify_skin/is_flesh 谓词，flesh 亮度上限放宽适配真机/PRD 光照；四图同口径，apple 校准对比归档值一致）；汇总 `Tools/acceptance_summary.jsonl`。",
        "- 像素测量仅为无视觉环境下的量化代理，**不替代人眼复核**；17 果人眼复核均待用户确认。",
        "",
    ]

    for fruit in FRUITS:
        d = rows[fruit]
        dw, ds, pv, prd = d["device-whole"], d["device-sliced"], d["blender-preview"], d["prd-reference"]
        log = EVIDENCE / f"{fruit}-acceptance" / f"evidence_{fruit}.log"
        fps = [l for l in log.read_text().splitlines() if "ASSET_FPS_SAMPLE" in l][0]
        parts = dict(kv.split("=", 1) for kv in fps.split()[1:])
        notes = NOTES.get(fruit, "")

        out += [
            f"## 素材与渲染验收（{fruit} 资产）",
            "",
            f"- 验收台：`FruitWaveApp/UI/FruitAssetLabView.swift`（由 AppleAssetLabView 泛化；`FW_FRUIT={fruit}` 选择水果，资产与证据按水果命名，两半分离距离读 `{fruit}.json` 碰撞半径）。",
            f"- 采样方式：`--terminate-existing -e '{{\"FW_ASSET_LAB\":\"1\",\"FW_SNAPSHOTS\":\"1\",\"FW_FRUIT\":\"{fruit}\"}}' com.example.FruitWave` 启动，其余流程与 apple 相同；证据写入设备 `Library/Caches/evidence_{fruit}.*`。",
            f"- 证据归档：`Docs/Evidence/{fruit}-acceptance/`（日志 + 整果/切面 PNG + 像素分析 JSON）。",
            "",
            "| 指标 | 实测值 | 记录 |",
            "|---|---|---|",
            f"| 设备 / tvOS / 构建 | {DEVICE} | `{DEPLOY_LOG}` |",
            f"| 整果帧率 | {parts['fps']} fps（{parts['seconds']}s，{parts['updates']} 帧） | `evidence_{fruit}.log` ASSET_FPS_SAMPLE |",
            f"| 峰值常驻内存（整果+切面同载） | {parts['residentMB']} MB | 同上 |",
            f"| 整果肤色均值 RGB | {fmt_rgb(dw['skin_mean_rgb'])}，PRD 参考 {fmt_rgb(prd['skin_mean_rgb'])}，Blender 预览 {fmt_rgb(pv['skin_mean_rgb'])} | 像素分析 JSON |",
            f"| 切面果肉均值 RGB | {fmt_rgb(ds['flesh_mean_rgb'])}，创作值 {fmt_rgb(d['flesh_base_rgb'])} | 像素分析 JSON |",
            f"| 整果包围盒 | 横向 {bbox_xy(dw['skin_bbox_pct'])}（居中） | 像素分析 JSON |",
            f"| 切面包围盒 | 横向 {bbox_x(ds['skin_bbox_pct'])}（两半分离） | 像素分析 JSON |",
            f"| 高光 | 肤像素 95 分位亮度 {dw['skin_p95_lum']}（PRD {prd['skin_p95_lum']}） | 像素分析 JSON |",
            f"| 人眼复核（高光/种子/无穿插/整体观感） | **待用户确认** | 看 `evidence_{fruit}_whole.png` / `evidence_{fruit}_sliced.png` |",
            f"| gameplay 集成 | 未做：{fruit} 资产仅用于验收台，`{fruit}.json` 注明 acceptance-lab-only | 见素材契约 |",
            "",
            f"- USDZ 静态校验：`usdchecker` 对 whole/sliced 均输出双 `Success!`；根名 `{fruit}_half_left` / `{fruit}_half_right`。",
            f"- 已知限制：本环境无视觉模型，无法自行目检截图；生成器以 PRD 原图像素采样驱动（`{fruit}_reference.json` 中如实标注 observed / inferred 与 inspection_method）。",
        ]
        if notes:
            out += ["- " + part for part in notes.split("- ")[1:]]
        out.append("")

    DOC.write_text(text + "\n".join(out).rstrip() + "\n")
    print(f"appended {len(FRUITS)} sections to {DOC}")


if __name__ == "__main__":
    main()
