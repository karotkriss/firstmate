#!/usr/bin/env python3
"""Deterministic behavioral model for the stow decay policy in issue #2410."""

from dataclasses import dataclass
from datetime import date, timedelta


@dataclass
class Entry:
    entry_id: int
    tier: str
    reinforced_day: int
    unreinforced_passes: int = 0
    usage: str = "never"


PASS_HORIZON = {"aging": 10, "perishable": 3}
DAY_HORIZON = {"aging": 30, "perishable": 7}


def has_evidence(entry: Entry, pass_number: int) -> bool:
    if entry.usage == "frequent":
        return pass_number % 5 == entry.entry_id % 5
    if entry.usage == "occasional":
        return pass_number % 16 == entry.entry_id % 16
    return False


def marker(entry: Entry, with_pass_horizon: bool) -> str:
    reinforced_date = date(2026, 1, 1) + timedelta(days=entry.reinforced_day)
    suffix = ""
    if with_pass_horizon and entry.unreinforced_passes:
        suffix = f"/{entry.unreinforced_passes}"
    return f"<!--{entry.tier[0]}:{reinforced_date.isoformat()}{suffix}-->"


def usage_for(entry_id: int) -> str:
    slot = entry_id % 40
    if slot < 14:
        return "frequent"
    if slot < 26:
        return "occasional"
    return "never"


def run_population(with_pass_horizon: bool, cadence_days: int) -> tuple[list[int], list[str]]:
    entries = {
        entry_id: Entry(entry_id, "aging", 0, usage=usage_for(entry_id))
        for entry_id in range(40)
    }
    next_id = 40
    counts = [len(entries)]
    snapshots = []
    for pass_number in range(1, 61):
        day = pass_number * cadence_days
        for entry_id, entry in list(entries.items()):
            if has_evidence(entry, pass_number):
                entry.reinforced_day = day
                entry.unreinforced_passes = 0
            elif with_pass_horizon:
                entry.unreinforced_passes += 1
            stale_by_day = day - entry.reinforced_day >= DAY_HORIZON[entry.tier]
            stale_by_pass = (
                with_pass_horizon
                and entry.unreinforced_passes >= PASS_HORIZON[entry.tier]
            )
            if stale_by_day or stale_by_pass:
                del entries[entry_id]
        for _ in range(2):
            entries[next_id] = Entry(
                next_id, "aging", day, usage=usage_for(next_id)
            )
            next_id += 1
        counts.append(len(entries))
        snapshots.append(
            "\n".join(
                f"{entry_id}:{marker(entry, with_pass_horizon)}"
                for entry_id, entry in sorted(entries.items())
            )
        )
    return counts, snapshots


def advance_single(
    tier: str,
    passes: int,
    evidence_on: set[int] | None = None,
) -> tuple[Entry | None, int | None]:
    entry = Entry(1, tier, 0)
    evidence_on = evidence_on or set()
    for pass_number in range(1, passes + 1):
        if pass_number in evidence_on:
            entry.reinforced_day = pass_number
            entry.unreinforced_passes = 0
        else:
            entry.unreinforced_passes += 1
        if (
            entry.unreinforced_passes >= PASS_HORIZON[tier]
            or pass_number - entry.reinforced_day >= DAY_HORIZON[tier]
        ):
            return None, pass_number
    return entry, None


old_daily, _ = run_population(False, 1)
new_daily, _ = run_population(True, 1)
old_monthly, old_monthly_snapshots = run_population(False, 30)
new_monthly, new_monthly_snapshots = run_population(True, 30)

assert old_daily[0] == new_daily[0] == 40
assert old_daily[-1] == 132
assert new_daily[-1] == 82
assert old_monthly_snapshots == new_monthly_snapshots

legacy = Entry(1, "aging", 0)
assert marker(legacy, True) == "<!--a:2026-01-01-->"
legacy.unreinforced_passes += 1
assert marker(legacy, True) == "<!--a:2026-01-01/1-->"

aging_before, _ = advance_single("aging", 9)
aging_stale, aging_archived_on = advance_single("aging", 10)
perishable_before, _ = advance_single("perishable", 2)
perishable_stale, perishable_archived_on = advance_single("perishable", 3)
assert aging_before is not None and aging_before.unreinforced_passes == 9
assert aging_stale is None and aging_archived_on == 10
assert perishable_before is not None and perishable_before.unreinforced_passes == 2
assert perishable_stale is None and perishable_archived_on == 3

reinforced, archived_on = advance_single("aging", 10, evidence_on={9})
assert reinforced is not None and archived_on is None
assert reinforced.unreinforced_passes == 1
assert reinforced.reinforced_day == 9

grace_marker = "<!--g-->"
assert ":" not in grace_marker

print("Stow decay policy simulation")
print("============================")
print("Initial aging entries: 40; admissions: 2 per pass; passes: 60")
print("Usage cohorts: frequent every 5 passes, occasional every 16, never reinforced")
print()
print("Daily cadence")
print(f"  Wall-clock-only policy: {old_daily[0]} -> {old_daily[-1]} entries")
print(f"  Dual-horizon policy:    {new_daily[0]} -> {new_daily[-1]} entries")
print("  Result: pass decay fires in the daily-stow home and removes 50 more stale entries")
print()
print("Monthly cadence")
print(f"  Wall-clock-only policy: {old_monthly[0]} -> {old_monthly[-1]} entries")
print(f"  Dual-horizon policy:    {new_monthly[0]} -> {new_monthly[-1]} entries")
print(f"  Serialized states identical after every pass: {old_monthly_snapshots == new_monthly_snapshots}")
print()
print("Boundary and compatibility scenarios")
print("  Legacy dated marker reads as counter zero: <!--a:2026-01-01-->")
print("  First unreinforced tick serializes as:       <!--a:2026-01-01/1-->")
print(f"  Aging remains live through pass 9 and archives on pass {aging_archived_on}")
print(f"  Perishable remains live through pass 2 and archives on pass {perishable_archived_on}")
print("  Genuine evidence on pass 9 refreshes the date and clears the counter")
print(f"  One later no-evidence pass produces counter: {reinforced.unreinforced_passes}")
print("  A statement with no independent evidence follows the no-evidence tick path")
print("  Undated legacy-grace marker is skipped by the dated-entry tick")
