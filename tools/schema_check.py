#!/usr/bin/env python3
"""从 Dart 源码里抽出 DDL，在真 SQLite 上跑一遍。

沙箱没有 Dart/Flutter SDK，所以拿 python3 + sqlite3 做**语法与约束**验收：
真正执行的是 `lib/data/db/schema.dart` 里的字符串，不是另抄一份。

用法：python3 tools/schema_check.py
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "lib" / "data" / "db" / "schema.dart"

SQL_BLOCK = re.compile(r"'''(.*?)'''", re.S)


def load_statements() -> list[str]:
    text = SCHEMA.read_text(encoding="utf-8")
    blocks = [b.strip() for b in SQL_BLOCK.findall(text)]
    return [b for b in blocks if b.upper().startswith(("CREATE", "ALTER", "INSERT"))]


def expect_error(label: str, fn) -> None:
    try:
        fn()
    except sqlite3.Error as exc:
        print(f"  ✓ {label} 被拒绝（{type(exc).__name__}）")
        return
    raise SystemExit(f"  ✗ {label} 本应被拒绝，却成功了")


def main() -> int:
    statements = load_statements()
    print(f"从 schema.dart 抽到 {len(statements)} 条语句")

    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys = ON")
    for stmt in statements:
        try:
            con.execute(stmt)
        except sqlite3.Error as exc:
            print(f"  ✗ 语法错误：{exc}\n{stmt}")
            return 1
    print("  ✓ 全部语句执行通过")

    # ---- 表与索引 ----
    tables = {
        r[0]
        for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }
    expected_tables = {
        "user_profile", "calibration_record", "capture_session", "daily_log",
        "daily_log_history", "valence_event", "negative_event", "energy_ledger",
        "load_index", "day_settlement", "ability_snapshot", "forecast_point",
        "memory_item", "confirmation_task", "badge", "config_override",
        "app_setting", "dirty_day",
        # 第 8 步：刻度标定层（纯增量，不动上面任何一张）
        "user_anchor", "anchor_revision", "declared_impact", "anchor_evidence",
        # 第 11 步：自建项目
        "custom_behavior",
        # v1.2.0：量化形状层（纯增量，17 张老表一条未改）
        "behavior_quant_spec", "axis_definition",
    }
    missing = expected_tables - tables
    if missing:
        print(f"  ✗ 缺表：{sorted(missing)}")
        return 1
    print(f"  ✓ 表齐全（{len(expected_tables)} 张）")

    indexes = {
        r[0]
        for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        )
    }
    for name in (
        "ux_daily_log_idem", "ux_valence_slot", "ux_negative_primary",
        "ix_history_key", "ix_memory_due", "ix_forecast_day",
        "ix_anchor_revision_time", "ix_anchor_evidence_behavior",
        "ix_custom_behavior_enabled",
        "ix_axis_definition_kind",
    ):
        if name not in indexes:
            print(f"  ✗ 缺索引：{name}")
            return 1
    print("  ✓ 关键索引齐全")

    # ---- 幂等：唯一索引必须由库拒绝 ----
    row = {
        "day_key": "2025-06-01", "behavior_code": "strength_training",
        "category": "positive", "valence": "positive", "axis": "strength",
        "plan_status": "planned", "confidence": "selfReport", "slot_key": "main",
        "idempotency_key": "2025-06-01|strength_training|main",
        "created_at": "2025-06-01T19:00:00", "updated_at": "2025-06-01T19:00:00",
    }
    cols = ", ".join(row)
    marks = ", ".join("?" * len(row))
    con.execute(f"INSERT INTO daily_log ({cols}) VALUES ({marks})", list(row.values()))
    expect_error(
        "重复幂等键",
        lambda: con.execute(f"INSERT INTO daily_log ({cols}) VALUES ({marks})", list(row.values())),
    )
    con.execute(
        f"INSERT OR REPLACE INTO daily_log ({cols}, dose_fraction, revision) "
        f"VALUES ({marks}, 0.5, 1)",
        list(row.values()),
    )
    n = con.execute("SELECT COUNT(*) FROM daily_log").fetchone()[0]
    assert n == 1, f"OR REPLACE 后应只剩一行，实际 {n}"
    print("  ✓ INSERT OR REPLACE 覆盖同一幂等键（仍一行）")

    # ---- 部分唯一索引：只挡主因 ----
    def neg(code: str, primary: int):
        con.execute(
            "INSERT INTO negative_event (day_key, behavior_code, behavior_name,"
            " dose_minutes, penalty_units, exp, root_cause_key, is_primary)"
            " VALUES (?,?,?,?,?,?,?,?)",
            ("2025-06-01", code, code, 90.0, 0.5, -1.5, "sleep@2025-06-01", primary),
        )

    neg("sleep", 1)
    expect_error("同根因的第二条主因", lambda: neg("sleep_again", 1))
    neg("absence", 0)
    neg("absence_2", 0)
    total = con.execute("SELECT COUNT(*) FROM negative_event").fetchone()[0]
    assert total == 3, total
    print("  ✓ 后果记录（is_primary=0）可以多条")

    # ---- 预测点主键 ----
    con.execute(
        "INSERT INTO forecast_point (day_key, axis, horizon_days, maintain, correct,"
        " low, high, confidence, is_projection) VALUES (?,?,?,?,?,?,?,?,?)",
        ("2025-06-03", "strength", 3, 41.0, 42.0, 39.0, 43.0, 0.9, 1),
    )
    con.execute(
        "INSERT OR REPLACE INTO forecast_point (day_key, axis, horizon_days, maintain,"
        " correct, low, high, confidence, is_projection) VALUES (?,?,?,?,?,?,?,?,?)",
        ("2025-06-03", "strength", 3, 41.5, 42.5, 39.5, 43.5, 0.9, 1),
    )
    n = con.execute("SELECT COUNT(*) FROM forecast_point").fetchone()[0]
    assert n == 1, n
    print("  ✓ 预测点主键 (生成日, 轴, horizon) 生效")

    # ---- 刻度标定层：一个行为一张卡（主键即幂等） ----
    con.execute(
        "INSERT INTO user_anchor (behavior_id, unit_label, definition_text,"
        " measurement_class, reference_range_id, calibrated_at, created_at, updated_at)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("strength_training", "一次有效组", "接近力竭且动作达标", "formula",
         "strength_sets", "2026-03-01T20:00:00", "2026-03-01T20:00:00",
         "2026-03-01T20:00:00"),
    )
    con.execute(
        "INSERT OR REPLACE INTO user_anchor (behavior_id, unit_label, definition_text,"
        " measurement_class, reference_range_id, calibrated_at, created_at, updated_at)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("strength_training", "一次有效组", "接近力竭且动作达标（第二次标定）",
         "formula", "strength_sets", "2026-03-01T20:00:00", "2026-03-01T20:00:00",
         "2026-04-01T20:00:00"),
    )
    n = con.execute("SELECT COUNT(*) FROM user_anchor").fetchone()[0]
    assert n == 1, f"同一行为应只有一张刻度卡片，实际 {n}"
    print("  ✓ 一个行为一张刻度卡片（behavior_id 主键覆盖）")

    # 证据只追加：先验的 replaced_by 指向它
    con.execute(
        "INSERT INTO anchor_evidence (id, behavior_id, kind, measured_value, unit,"
        " derived_tier, performed_at, note, confidence, created_at)"
        " VALUES (?,?,?,?,?,?,?,?,?,?)",
        ("ev-1", "strength_training", "measuredTest", 10.0, "一次有效组",
         "medium", "2026-03-05T20:00:00", "", "calibrated", "2026-03-05T20:00:00"),
    )
    con.execute(
        "INSERT INTO declared_impact (behavior_id, tier, source, weight, declared_at,"
        " replaced_by, note, updated_at) VALUES (?,?,?,?,?,?,?,?)",
        ("strength_training", "mediumHigh", "userPrior", 0.45,
         "2026-03-01T20:00:00", "ev-1", "", "2026-03-05T20:00:00"),
    )
    row = con.execute(
        "SELECT tier, replaced_by FROM declared_impact WHERE behavior_id = ?",
        ("strength_training",),
    ).fetchone()
    assert row == ("mediumHigh", "ev-1"), row
    print("  ✓ 先验被实测覆盖（replaced_by 指向证据）")

    # ---- 量化形状层：CHECK 是库层的硬约束，不是文档 ----
    spec_cols = (
        "behavior_code, measure_kind, measure_unit, shape_kind, shape_k,"
        " shape_theta_fraction, target_dose, impact_json, citation, source,"
        " note, revision, created_at, updated_at"
    )

    def quant_row(code: str, shape: str, target: float):
        return {
            "behavior_code": code, "measure_kind": "episode",
            "measure_unit": "次", "shape_kind": shape, "shape_k": None,
            "shape_theta_fraction": 1.0, "target_dose": target,
            "impact_json": '[{"axis":"relation","axis_label":"关系",'
                           '"dim_kind":"experience","share":1.0}]',
            "citation": "事件型行为按发生/未发生二值计", "source": "userPrior",
            "note": "", "revision": 1,
            "created_at": "2026-03-01T20:00:00",
            "updated_at": "2026-03-01T20:00:00",
        }

    def insert_quant(row: dict):
        cols = ", ".join(row)
        marks = ", ".join("?" * len(row))
        con.execute(
            f"INSERT INTO behavior_quant_spec ({cols}) VALUES ({marks})",
            list(row.values()),
        )

    insert_quant(quant_row("custom_film", "threshold", 1.0))
    expect_error(
        "target_dose = 0 的口径",
        lambda: insert_quant(quant_row("bad_zero", "linear", 0.0)),
    )
    expect_error(
        "白名单之外的 shape_kind",
        lambda: insert_quant(quant_row("bad_shape", "biphasic", 1.0)),
    )
    # 一个行为一条口径：主键覆盖而不是新增
    row = quant_row("custom_film", "saturating", 90.0)
    row["measure_kind"] = "duration_min"
    cols = ", ".join(row)
    marks = ", ".join("?" * len(row))
    con.execute(
        f"INSERT OR REPLACE INTO behavior_quant_spec ({cols}) VALUES ({marks})",
        list(row.values()),
    )
    n = con.execute("SELECT COUNT(*) FROM behavior_quant_spec").fetchone()[0]
    assert n == 1, f"同一行为应只有一条口径，实际 {n}"
    shape = con.execute(
        "SELECT shape_kind FROM behavior_quant_spec WHERE behavior_code = ?",
        ("custom_film",),
    ).fetchone()[0]
    assert shape == "saturating", shape
    print("  \u2713 一个行为一条口径（behavior_code 主键覆盖）")

    # 自定义维度：ability 必须带衰减常数
    con.execute(
        "INSERT INTO axis_definition (axis_key, label, dim_kind, decay_tau_days,"
        " decay_citation, enabled, created_at, updated_at)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("ua_1", "关系", "experience", 0.0, "", 1,
         "2026-03-01T20:00:00", "2026-03-01T20:00:00"),
    )
    expect_error(
        "ability 维度没有衰减常数",
        lambda: con.execute(
            "INSERT INTO axis_definition (axis_key, label, dim_kind,"
            " decay_tau_days, decay_citation, enabled,"
            " created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
            ("ua_bad", "关系", "ability", 0.0, "", 1,
             "2026-03-01T20:00:00", "2026-03-01T20:00:00"),
        ),
    )
    con.execute(
        "INSERT INTO axis_definition (axis_key, label, dim_kind, decay_tau_days,"
        " decay_citation, enabled, created_at, updated_at)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("ua_2", "关系", "ability", 45.0, "去训练经验近似", 1,
         "2026-03-01T20:00:00", "2026-03-01T20:00:00"),
    )
    print("  \u2713 ability 维度必须带衰减常数（CHECK 生效）")

    # ---- 各表列数（防止建表语句被截断） ----
    print("\n表 / 列数：")
    for table in sorted(expected_tables):
        count = len(con.execute(f"PRAGMA table_info({table})").fetchall())
        print(f"  {table:20s} {count:>2d} 列")

    print("\nDDL 验收通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
