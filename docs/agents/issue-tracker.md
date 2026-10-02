# Decision tracker: Local Markdown

For this map the local fallback provided by wayfinder is used; no issues are published on GitHub. To configure the toolkit on another tracker later, run `/setup-matt-pocock-skills`.

## Wayfinding operations

- Canonical map: `.scratch/cascade-product/map.md`, with the label `wayfinder:map`.
- Children: one file per ticket in `.scratch/cascade-product/issues/NN-name.md`; `ID` is the identity and `Parent` identifies the map.
- Type and label: `Type: research|prototype|grilling|task` and `Labels: wayfinder:<type>`.
- States: `open`, `claimed`, `resolved`, `closed-out-of-scope`. The last two are closed.
- Claim: set `Assignee` and `Status: claimed` **before** the work. Release both if the work is abandoned. Do not take a ticket that is already assigned.
- Dependencies: `Blocked by: NN, NN`, or `none`. This is the textual fallback for a tracker without native relations.
- Frontier: children with state open, assignee none and all blockers closed; sort by ID. `docs/wayfinder/frontier.md` is a derived view, not a second source of the decisions.
- Resolution: add `## Answer` with outcome, evidence and assets; set resolved and add to the map only the linked title and the gist. Do not put the answer in the Question.
- Out of scope: state closed-out-of-scope, a rationale and a link in the map's Out of scope, without adding it to the decisions reached.
- New tickets: first create all the files, then link the dependencies in a second pass. Nonexistent references and cycles are forbidden.
- Cite tickets by linked title in all text meant for people; bare IDs are reserved for metadata.

Adapted from the [original local-markdown template](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/issue-tracker-local.md). This file is configuration for the current map; the global setup of the skills has not been run.
