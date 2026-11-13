# Concorde rota reconciliation

LoveHub already stores imported Concorde shifts as `{kHubsCollection}/{hubId}/events/c2-rota:{externalId}`. This job keeps those documents aligned with Tom's rota. It does not create events.

Since the live cutover (13 Nov 2026), this tool reads and writes
`sharedHubs/{hubId}/…` (the `kHubsCollection` constant in
`lib/services/hub_collection.dart`). Document ids are unchanged. The old
`hubs` collection is kept as a read-only backup; do not write to it. Cloud
Functions use the matching switch in `functions/hubs_collection.js`, which
now defaults to `sharedHubs`.

| Feed row | Imported event is `tentative` | Imported event is confirmed, or has no status |
| --- | --- | --- |
| `tom=working` and `status=on` | Set `status` to `confirmed` | Leave it |
| `tom=undecided` and `status=on` | Leave it tentative | Leave it |
| `status=cancelled` or `postponed`, or `tom=not_working` | Delete that document (today or future only) | Leave it |

`cancelled` and `postponed` remove a tentative show even when `tom` is `working` or `undecided`. A confirmed show is never deleted and never moved back to tentative. Deletes never apply to events dated before today (Europe/London); past history is left as stored. Confirming a past tentative show Tom worked is still allowed.

## What it will not touch

A document is in scope only when both are true:

- `source` is `c2-rota`
- the document id is the stable import id `c2-rota:{externalId}` (`c2-rota:2026-11-09`, `c2-rota:2026-11-13-junebabies-bar`)

Hand-made events, Google-synced events, `seb`, and `rot90s` are out of scope. So is a document whose id is not that stable id, even if someone set `source` to `c2-rota`.

Matching is per show, on the Europe/London civil date:

- The date in the id (`2026-11-13` or `2026-11-13-…`) must be the London date of `start`. If they disagree, the event is skipped.
- A suffixed id matches the feed show slug (`Junebabies (Bar)` matches `…-junebabies-bar`). If the title is present it has to agree. `C2 — Junebabies (Bar)` agrees. A title for a different show does not, and the event is skipped.
- A date-only id (`c2-rota:2026-11-13`) matches only when the title is that show (`C2 — John Digweed`). The date by itself is not a match.
- `The Allergies` and `Allergies` are the same show. Other title differences are not guessed.
- Two events that fit one show, or one event that fits two shows, are skipped. Nothing is written for them.
- A feed row with no imported event is logged and not created.
- An imported event with no matching feed row is left in place. Absence is not a cancellation.

The feed has to be a JSON object with `generatedAt` and a non-empty `days` array. Each kept day needs `date` (`YYYY-MM-DD`), a non-empty `show`, `status` (`on`, `cancelled`, or `postponed`), and `tom` (`working`, `not_working`, or `undecided`). Empty `show` rows (off-days) and unknown `status` values are skipped with a warning rather than failing the feed. An empty list after skips, a duplicate show on the same date, a structurally invalid row, or more than 500 rows rejects the whole feed. Nothing is written.

`generatedAt` must be within 6 hours of the clock, and not more than 5 minutes ahead. A stale feed still prints the plan. `--apply` refuses it.

Days are acted on only inside the London window of 14 days back through 90 days ahead. That is the span the feed covers. Rows outside it are ignored. Within that window, deletes still refuse any show dated before today in Europe/London.

One run confirms at most 12 events and deletes at most 8 (raise with `--max-confirms` / `--max-deletes`, hard ceiling 40). Over the cap, the run writes nothing: it does not apply the first few. More than 500 imported `c2-rota` documents also writes nothing.

Writes are one Firestore commit. Each confirm or delete is conditional on the `updateTime` read in that run, so a document Tom edited in between is not overwritten. The commit also writes the rollback record. A 429 or 5xx is retried up to three times. A precondition failure writes nothing (the commit is atomic) and the next run reads again.

## Credential-free review

From the repo root, with Dart on the path. This uses the checked-in 8 Nov 2026 snapshot. It does not read a token and does not contact Firebase.

```bash
dart run tool/reconcile_c2_rota.dart \
  --hub pobIb3qupVJudoQGMJjl \
  --feed-file tool/c2_rota_feed_example.json \
  --events-file tool/c2_rota_events_example.json \
  --now 2026-11-08T12:00:00Z
```

That snapshot is Cardinals 9 Nov working, Mykki Blanco 10 Nov undecided, Allergies 12 Nov undecided, John Digweed and Junebabies (Bar) 13 Nov not working, MNEK 15 Nov cancelled. The example events are all tentative, plus a personal dinner and a Sophie Ellis-Bextor event on 9 Nov. The dry-run should show:

- `CONFIRM` `c2-rota:2026-11-09`
- `KEEP` `c2-rota:2026-11-10` and `c2-rota:2026-11-12`
- `DELETE` `c2-rota:2026-11-13`, `c2-rota:2026-11-13-junebabies-bar`, and `c2-rota:2026-11-15`
- the dinner and the SEB event ignored
- `nothing written`

The fixture has no Firestore `updateTime`, so the last line says a live dry-run reads that before `--apply`. A dry-run against the hub does not print that line.

`--now` and `--events-file` cannot be combined with `--apply`.

## Live dry-run

The production hub is `pobIb3qupVJudoQGMJjl` in project `lovehub-26107`. `HUB_ID` can replace `--hub`.

1. The feed token is the raw bearer token in `/home/box/secrets/tom_rota_feed_token` (mode `0600`, owner the user who will run the job). A leading `Bearer ` is accepted. The file must not be a JSON key or a private key. Override the path with `--token-file` or `TOM_ROTA_FEED_TOKEN_FILE`. Do not pass the token as an argument.
2. Application Default Credentials for the Google account that can read and write Cloud Firestore on `lovehub-26107`. This is separate from `firebase login`. The job uses `package:googleapis_auth` `clientViaApplicationDefaultCredentials` and the scope `https://www.googleapis.com/auth/cloud-platform`. It does not read the Firebase CLI credential cache, does not exchange a stored refresh token, and does not run a command that prints an access token. Do not create a service-account key.

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project lovehub-26107
```

If that has not been done, a live run exits 4 and prints those two commands. It does not start the login itself.

```bash
dart run tool/reconcile_c2_rota.dart --hub pobIb3qupVJudoQGMJjl
```

This GETs `https://us-central1-concorde2-e8b96.cloudfunctions.net/tomRotaFeed` with the bearer token and queries `{kHubsCollection}/{hubId}/events` where `source == c2-rota`. Redirects are not followed. The token is not printed, not put in the audit, and not sent to Firestore.

Compare the plan with the calendar before the first apply. If a line is `SKIP` because the title and the id disagree, fix the import rather than raising the caps. Exit code 2 means the run would refuse `--apply` (bad feed, stale feed, or over the cap). Exit code 0 on a dry-run means the plan is allowed.

`--json-out plan.json` writes the same plan. It does not contain the token.

## First apply, then every 15 minutes

Apply once, in the foreground, after the dry-run looks right:

```bash
dart run tool/reconcile_c2_rota.dart --hub pobIb3qupVJudoQGMJjl --apply
```

A no-op apply writes nothing. A real apply prints `Applied audit {kHubsCollection}/pobIb3qupVJudoQGMJjl/c2RotaSyncAudit/c2sync-…`. Run it again. The second run should report no changes: confirms stay confirmed, deletes are already gone, undecided stays tentative.

Schedule it only after that. Cron must be the Unix user who ran `gcloud auth application-default login`, so `HOME` is that user's home. Do not wrap this script in another `flock` on the same lock file; the script already holds one.

```cron
PATH=/home/box/flutter/bin:/usr/bin:/bin
*/15 * * * * /home/box/lovehub/tool/reconcile_c2_rota.sh --hub pobIb3qupVJudoQGMJjl --apply >> /home/box/lovehub-c2-rota.log 2>&1
```

`tool/reconcile_c2_rota.sh` `cd`s to the repo, takes the lock, and runs `dart`. Set `DART` if `dart` is not on `PATH`. Overlapping runs exit 0 and leave the in-flight one alone.

There is no `firebase deploy` for this job. `firebase.json` is unchanged. A Cloud Function is not a fit for the current project: there is no `functions` codebase, a function would have to store the feed token in the cloud, and Cloud Scheduler needs the Blaze plan. This job keeps the feed token on the shared computer.

Firestore MCP is not used for the write. `npx firebase-tools mcp` proxies Firestore tools from `https://firestore.googleapis.com/mcp`. A `tools/list` against that endpoint (no project, no document call) shows `update_document` and `delete_document`, each with a `currentDocument` precondition (`updateTime` or `exists`), plus `add_document`, `get_document`, and `list_documents`. There is no commit, batch, or begin-transaction tool. The local `firestore_query_collection` tool is read-only and defaults to 10 documents. Confirming one show, deleting others, and writing the audit has to be one `documents:commit`, so this job calls that REST method with the ADC client. The requests send `x-goog-user-project: lovehub-26107`.

## Rollback

Rollback never deletes. It sets a confirm back to `tentative` only while that document is still a confirmed imported `c2-rota` event, and it recreates a deleted document only while that id is still missing. The recreate uses the field snapshot from the audit, including the original id.

```bash
dart run tool/reconcile_c2_rota.dart \
  --hub pobIb3qupVJudoQGMJjl \
  --rollback c2sync-20261108T120000000Z-0123abcd

dart run tool/reconcile_c2_rota.dart \
  --hub pobIb3qupVJudoQGMJjl \
  --rollback c2sync-20261108T120000000Z-0123abcd \
  --apply
```

The id is the one printed by `--apply`. Dry-run is the default. `--audit-dir c2-rota-audit` also writes a local `plan.json` and, on apply, `pending-<id>.json`. That directory is gitignored. The Firestore audit is the record rollback reads. Local `pending-` files are not applied by themselves.

## Permissions

The Google account from `gcloud auth application-default login` needs Firestore read and write on `lovehub-26107`: get, list, create, update, and delete (`roles/datastore.user`, or Editor). That can be the same person who deploys Hosting, but this job does not reuse the Firebase CLI login. User ADC bypasses security rules the same way other IAM credentials do.

This change does not edit `firestore.rules`, indexes, or IAM. A hub member's ID token is not required.

Audit documents live at `{kHubsCollection}/{hubId}/c2RotaSyncAudit/{id}`. Existing rules let any signed-in user read hub data, so members can read show names, statuses, and the event snapshot. They cannot read the feed token; it is not stored there. The calendar listens to `events` only, so audit documents do not show up as shifts.

The token file should stay mode `0600`. The process reads it and sends it only on the feed request.

## Cost

No Cloud Functions, Cloud Scheduler, or Secret Manager, and no Blaze requirement for this job. The feed request runs on the shared computer.

Each run is one Firestore query for `source == c2-rota`. A query is billed per document returned (one read if it returns nothing). At 30 imported shifts and every 15 minutes that is about 2,900 reads a day. At 100 shifts, about 9,600. The free tier is 50,000 reads a day. The job refuses the run above 500 imported documents; 500 every 15 minutes would sit on that free-tier line, which this hub is not near.

Writes happen only when a show changes: one write per confirm, one delete per removal, and one audit document in the same commit. A steady rota writes nothing. A handful of changes a day is inside the free tier (20,000 writes and 20,000 deletes a day).

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Dry-run plan is allowed, apply succeeded, or there was nothing to change |
| 1 | Bad arguments or a local file could not be read |
| 2 | Feed missing, empty, stale, invalid, or over a cap. Nothing written |
| 3 | A document changed since it was read. Nothing written; the next run reads again |
| 4 | Application Default Credentials are missing or Firestore refused them. Nothing written |

## Tests

```bash
flutter test test/c2_rota_reconcile_test.dart
```

The tests do not call the feed or Firestore.
