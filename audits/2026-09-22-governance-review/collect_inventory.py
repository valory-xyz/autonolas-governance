#!/usr/bin/env python3
"""Read-only Git inventory. Writes deterministic evidence beside this script."""
import csv
import io
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "data"
# Only selects the baseline tag (the last one before this instant); no commit is filtered by date.
TAG_CUTOFF = datetime.fromisoformat("2026-05-01T00:00:00+02:00")
# Proposal-review window (area 0); independent of source baseline and raw collection coverage.
COLLECTION_DATE = "2026-09-22"
TARGET = "93901ec315eb2b1d4683aab5615ef38b071228f8"
BASE_TAG = "v1.2.5-post-external-audit"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def write_csv(name, rows, fields):
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
    (OUT / name).write_text(buf.getvalue())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Filter explicitly by committer date; do not rely on git --since traversal pruning.
    history = []
    for line in git("log", "--first-parent", "--format=%H%x09%cI%x09%s", TARGET).splitlines():
        sha, date, subject = line.split("\t", 2)
        history.append(dict(sha=sha, date=date, subject=subject))
    base = git("rev-parse", BASE_TAG + "^{commit}").strip()
    range_commits = set(git("rev-list", base + ".." + TARGET).splitlines())
    events = [r for r in history if r["sha"] in range_commits]
    assert events and events[0]["sha"] == TARGET
    assert datetime.fromisoformat(git("show", "-s", "--format=%cI", base).strip()) < TAG_CUTOFF
    touched = set()
    for row in events:
        row["pr"] = (re.search(r"Merge pull request #(\d+)", row["subject"]) or [None, ""])[1]
        row["paths"] = git("diff", "--name-only", row["sha"] + "^1", row["sha"]).splitlines()
        touched.update(row["paths"])
    changes = []
    for line in git("diff", "--numstat", "--no-renames", base, TARGET).splitlines():
        added, deleted, path = line.split("\t", 2)
        changes.append(dict(path=path, added=added, deleted=deleted))
    all_commits = git("rev-list", "--count", base + ".." + TARGET).strip()
    # PRs merged into feature branches, not into main directly: invisible to --first-parent.
    first_parent = {e["sha"] for e in events}
    nested = []
    for line in git("log", "--merges", "--format=%H%x09%cI%x09%s", base + ".." + TARGET).splitlines():
        sha, date, subject = line.split("\t", 2)
        pr = re.search(r"Merge pull request #(\d+)", subject)
        if pr and sha not in first_parent:
            nested.append(dict(sha=sha, date=date, pr=pr[1], subject=subject))
    base_date = git("show", "-s", "--format=%cI", base).strip()
    manifest = dict(tag_selection_cutoff=TAG_CUTOFF.isoformat(),
                    target=TARGET, baseline=base, baseline_tag=BASE_TAG,
                    onchain_window=dict(start=TAG_CUTOFF.isoformat(), end_inclusive=COLLECTION_DATE,
                                        selection="proposals created in this window; related actions and earlier state as context only",
                                        timezone="Europe/Rome"),
                    selection="all changes after the last tag before May, through all subsequent tags to target; no commit-date exclusion",
                    first_parent_events=len(events), merged_prs=sum(bool(e["pr"]) for e in events),
                    nested_merged_prs=sorted((n["pr"] for n in nested), key=int),
                    reachable_commits_in_range=int(all_commits), net_changed_paths=len(changes),
                    touched_paths=len(touched),
                    production_solidity_net_changes=[r["path"] for r in changes
                        if r["path"].startswith("contracts/") and r["path"].endswith(".sol")
                        and not r["path"].startswith("contracts/test/")],
                    limitations=["Local Git evidence only; no independent on-chain verification.",
                                  "PR numbers from merge subjects; remote discussions not collected.",
                                  "merged_prs counts first-parent merges only; nested_merged_prs lists PRs merged into feature branches.",
                                  "Net source diff does not measure deployment or compiler changes."])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (OUT / "integration_events.json").write_text(json.dumps(events, indent=2) + "\n")
    write_csv("changed_files.csv", changes, ["path", "added", "deleted"])
    write_csv("integrations.csv", [{k: r[k] for k in ["sha", "date", "pr", "subject"]} for r in events],
              ["sha", "date", "pr", "subject"])
    write_csv("nested_merges.csv", nested, ["sha", "date", "pr", "subject"])
    (OUT / "production_contracts.diff").write_text(git("diff", base, TARGET, "--", "contracts", ":(exclude)contracts/test"))
    (OUT / "build_config.diff").write_text(git("diff", base, TARGET, "--", "foundry.toml", "hardhat.config.js", "package.json", ".github/workflows/workflow.yaml"))
    sections = []
    for version, ref in [("baseline", base), ("target", TARGET)]:
        if not git("ls-tree", "--name-only", ref, "docs/Vulnerabilities_list_governance.md"):
            sections.append(dict(version=version, heading="Markdown register absent at this ref; older PDF not extracted, not evidence of zero findings"))
            continue
        for line in git("show", ref + ":docs/Vulnerabilities_list_governance.md").splitlines():
            if re.match(r"^### \d+\.", line):
                sections.append(dict(version=version, heading=line[4:]))
    write_csv("vulnerability_headings.csv", sections, ["version", "heading"])
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
