#!/usr/bin/env python3
"""Deterministic acceptance model for issue #2410's opt-in policy."""

from dataclasses import dataclass
from datetime import date, timedelta


PASS_HORIZON = {"aging": 10, "perishable": 3}
DAY_HORIZON = {"aging": 30, "perishable": 7}


@dataclass
class Entry:
    entry_id: int
    tier: str
    reinforced_day: int
    counter: int = 0
    usage: str = "never"


def evidence(entry: Entry, pass_number: int) -> bool:
    if entry.usage == "frequent":
        return pass_number % 5 == entry.entry_id % 5
    if entry.usage == "occasional":
        return pass_number % 16 == entry.entry_id % 16
    return False


def usage(entry_id: int) -> str:
    slot = entry_id % 40
    return "frequent" if slot < 14 else "occasional" if slot < 26 else "never"


def marker(entry: Entry, opted_in: bool) -> str:
    stamp = date(2026, 1, 1) + timedelta(days=entry.reinforced_day)
    # Opt-out freezes an existing counter byte-for-byte. It is not interpreted.
    suffix = f"/{entry.counter}" if entry.counter else ""
    return f"<!--{entry.tier[0]}:{stamp.isoformat()}{suffix}-->"


def population(opted_in: bool, cadence: int) -> tuple[list[int], list[str]]:
    entries = {
        i: Entry(i, "aging", 0, usage=usage(i))
        for i in range(40)
    }
    next_id = 40
    counts = [40]
    states = []
    for pass_number in range(1, 61):
        day = pass_number * cadence
        for entry_id, entry in list(entries.items()):
            if evidence(entry, pass_number):
                entry.reinforced_day = day
                entry.counter = 0
            elif opted_in:
                entry.counter += 1
            stale_by_day = day - entry.reinforced_day >= DAY_HORIZON[entry.tier]
            stale_by_pass = opted_in and entry.counter >= PASS_HORIZON[entry.tier]
            if stale_by_day or stale_by_pass:
                del entries[entry_id]
        for _ in range(2):
            entries[next_id] = Entry(next_id, "aging", day, usage=usage(next_id))
            next_id += 1
        counts.append(len(entries))
        states.append("\n".join(f"{i}:{marker(e, opted_in)}" for i, e in sorted(entries.items())))
    return counts, states


def pre_change(cadence: int) -> tuple[list[int], list[str]]:
    entries = {
        i: Entry(i, "aging", 0, usage=usage(i))
        for i in range(40)
    }
    next_id = 40
    counts = [40]
    states = []
    for pass_number in range(1, 61):
        day = pass_number * cadence
        for entry_id, entry in list(entries.items()):
            if evidence(entry, pass_number):
                entry.reinforced_day = day
            if day - entry.reinforced_day >= DAY_HORIZON[entry.tier]:
                del entries[entry_id]
        for _ in range(2):
            entries[next_id] = Entry(next_id, "aging", day, usage=usage(next_id))
            next_id += 1
        counts.append(len(entries))
        states.append("\n".join(f"{i}:{marker(e, False)}" for i, e in sorted(entries.items())))
    return counts, states


def advance(
    tier: str,
    passes: int,
    opted_in: bool,
    evidence_on: set[int] | None = None,
    opt_out_after: int | None = None,
) -> tuple[Entry | None, int | None, str | None]:
    entry = Entry(1, tier, 0)
    evidence_on = evidence_on or set()
    for pass_number in range(1, passes + 1):
        enabled = opted_in and (opt_out_after is None or pass_number <= opt_out_after)
        if pass_number in evidence_on:
            entry.reinforced_day = pass_number
            entry.counter = 0
        elif enabled:
            entry.counter += 1
        by_day = pass_number - entry.reinforced_day >= DAY_HORIZON[tier]
        by_pass = enabled and entry.counter >= PASS_HORIZON[tier]
        if by_day or by_pass:
            reason = f"unreinforced {entry.counter}p" if by_pass and not by_day else f"unreinforced {pass_number - entry.reinforced_day}d"
            return None, pass_number, reason
    return entry, None, None


old_daily, old_daily_states = pre_change(1)
default_daily, default_daily_states = population(False, 1)
optin_daily, _ = population(True, 1)
default_monthly, default_monthly_states = population(False, 30)
optin_monthly, optin_monthly_states = population(True, 30)

assert default_daily_states == old_daily_states
assert default_daily == old_daily and default_daily[-1] == 132
assert optin_daily[-1] == 82
assert default_monthly_states == optin_monthly_states

aging_9, _, _ = advance("aging", 9, True)
_, aging_fire, aging_reason = advance("aging", 10, True)
perishable_2, _, _ = advance("perishable", 2, True)
_, perishable_fire, perishable_reason = advance("perishable", 3, True)
assert aging_9 and aging_9.counter == 9 and aging_fire == 10
assert perishable_2 and perishable_2.counter == 2 and perishable_fire == 3
assert aging_reason == "unreinforced 10p"
assert perishable_reason == "unreinforced 3p"

day_29, _, _ = advance("aging", 29, False)
_, day_30, day_reason = advance("aging", 30, False)
assert day_29 and day_29.counter == 0 and day_30 == 30
assert day_reason == "unreinforced 30d"

reinforced, _, _ = advance("aging", 9, True, evidence_on={9})
assert reinforced and reinforced.reinforced_day == 9 and reinforced.counter == 0

legacy = Entry(1, "aging", 0)
assert marker(legacy, True) == "<!--a:2026-01-01-->"

frozen, _, _ = advance("aging", 12, True, opt_out_after=5)
assert frozen and frozen.counter == 5
before_opt_out = marker(frozen, True)
after_opt_out = marker(frozen, False)
assert before_opt_out == after_opt_out == "<!--a:2026-01-01/5-->"

print("Stow decay policy simulation (amended opt-in acceptance)")
print("========================================================")
print(f"1. Defaults unchanged for all 60 daily passes: {default_daily_states == old_daily_states}; 40 -> {default_daily[-1]}")
print(f"2. Daily home with opt-in is bounded: 40 -> {optin_daily[-1]}")
print(f"3. Monthly serialization identical either way: {default_monthly_states == optin_monthly_states}; 40 -> {default_monthly[-1]}")
print(f"4. Exact thresholds: aging {aging_fire} ({aging_reason}); perishable {perishable_fire} ({perishable_reason})")
print(f"5. Default aging entry survives 29 passes with counter {day_29.counter}, then archives on day {day_30} ({day_reason})")
print(f"6. Evidence on pass 9 refreshes day to {reinforced.reinforced_day} and clears counter to {reinforced.counter}")
print(f"7. Legacy marker has implicit zero and default serialization: {marker(legacy, False)}")
print(f"8. Removing opt-in freezes and byte-preserves the unread counter: {before_opt_out} == {after_opt_out}")
print("Provenance: pass reasons carry exact counter spelling; wall-clock reasons omit the counter")
