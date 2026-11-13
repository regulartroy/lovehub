# Work event import (Roger)

Roger emits JSON. LoveHub upserts it into `{kHubsCollection}/{hubId}/events`.

Since the live cutover (13 Nov 2026), this tool reads and writes
`sharedHubs/{hubId}/…` (the `kHubsCollection` constant in
`lib/services/hub_collection.dart`). Document ids are unchanged. The old
`hubs` collection is kept as a read-only backup; do not write to it. Cloud
Functions use the matching switch in `functions/hubs_collection.js`, which
now defaults to `sharedHubs`.

The same `source` + `externalId` always writes the **same document**, so a
retry updates that shift instead of creating a second one.

There is no public URL. A **hub member** runs the importer with a Firebase
ID token. The script refuses to write unless that uid is in
`{kHubsCollection}/{hubId}.members`.

## Payload

One event, a JSON array, or `{"events":[...]}`.

```json
{
  "source": "c2-rota",
  "externalId": "2026-09-20",
  "summary": "C2 Show — Artist",
  "start": "2026-09-20T15:00:00+01:00",
  "end": "2026-09-20T23:30:00+01:00",
  "allDay": false,
  "category": "work",
  "assignedTo": "tom",
  "status": "tentative",
  "notes": "optional"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `source` | yes | `c2-rota`, `seb`, `rot90s`, or any other non-empty string |
| `externalId` | yes | Stable id inside that source. A show date is enough. |
| `summary` | yes | Calendar title. Do not put notes here. |
| `start` | yes | ISO-8601 **with offset** (Europe/London), e.g. `+01:00` or `Z` |
| `end` | no | Defaults to `start`. Must not be before `start`. |
| `allDay` | no | Default `false`. A date-only `2026-09-20` is also accepted. |
| `category` | no | Use `work` so the chip is stone grey. Default `general`. |
| `assignedTo` | no | `tom`, `maria`, `shared`, or a Firebase uid. Default `shared`. |
| `status` | no | `tentative` or `confirmed`. Omit it to leave the stored value alone. A new event with no status displays as confirmed. |
| `notes` | no | Stored on the `notes` field, not appended to `summary`. |

A whole rota dump can be tentative without editing every row. Either pass
`--tentative`, or wrap the array:

```json
{ "status": "tentative", "events": [ /* rows that omit status */ ] }
```

A status on an individual event wins over the envelope and over `--tentative`.
Re-posting a payload that says `tentative` marks that show tentative again.
Re-posting a payload that omits `status` does not change a confirm.

`tentative` shows on the calendar, LOOK AHEAD, and dashboard as a paler chip
with a **?** . Confirmed work stays Tom blue and work grey.

![Confirmed work next to a muted tentative chip](tentative-vs-confirmed.png)

Document id is `source:externalId` (for example `c2-rota:2026-09-20`).
`/` and control characters are replaced so the id is legal in Firestore.

`assignedTo: "tom"` is matched to the hub member whose name contains “tom”
and stored as that uid. The calendar still paints an unresolved `tom` token
Tom blue, with a work-grey category chip.

Import does **not** set `gcalId`. A merge leaves any existing Google Calendar
id in place. Hand-made and Google-synced events keep the ids
`batchAddEvents` already minted; this path does not rewrite them.

A copy of the sample array is `tool/event_import_example.json`.

## Hub id

Firestore → `users/{tomUid}` → `activeHubId`.

That value is the hub document id (same id in `sharedHubs` and `hubs`). The same id is in Tom's
`joinedHubs` map. The hub's `members` array must include the uid that runs
the import.

## Auth

Put the credential in the environment of the machine that runs the script.
Do not commit it, and do not commit a service-account JSON file.

Either:

- `FIREBASE_ID_TOKEN` — a Firebase ID token for a hub member (about an hour), or
- `FIREBASE_REFRESH_TOKEN` — a refresh token for that same user. The script
  exchanges it with the public web API key already in the app.

Email/password sign-in (only if that provider is enabled) prints an ID token
and a refresh token. `LOVEHUB_EMAIL` and `LOVEHUB_PASSWORD` stay in the
environment too:

```bash
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIzaSyCaL0oQdTrw2yk-0fAlyBgirOxwQC-G8NU" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$LOVEHUB_EMAIL\",\"password\":\"$LOVEHUB_PASSWORD\",\"returnSecureToken\":true}"
```

Use `idToken` as `FIREBASE_ID_TOKEN`, or store `refreshToken` as
`FIREBASE_REFRESH_TOKEN`. The uid in the response must be on the hub.

If the account is Google-only, sign in once in a context that can mint a
Firebase refresh token and export that. The importer never takes a
service-account file.

## Run

From the repo root, with Flutter/Dart on the path:

```bash
export HUB_ID='paste-activeHubId'
export FIREBASE_REFRESH_TOKEN='paste-refresh-token'

dart run tool/import_hub_events.dart --dry-run --file tool/event_import_example.json
dart run tool/import_hub_events.dart --tentative --file rota.json
dart run tool/import_hub_events.dart --file rota.json
```

Confirm one show after Tom decides he is working it. This does not repost the
shift; it only sets `status` to `confirmed` on that document. The document
must already exist.

```bash
dart run tool/import_hub_events.dart --confirm c2-rota:2026-09-20
dart run tool/import_hub_events.dart --confirm c2-rota:2026-09-21 --confirm seb:2026-10-03-london
```

Tom can confirm the same way in the app, without the CLI. On the Calendar tab, tap the muted chip (it has a **?**). On the kitchen tablet, open LOOK AHEAD, tap the day, and use **Confirm I'm working this**. **Keep tentative** dismisses the prompt and leaves the event in place.

Either path sets `status` to `confirmed` on `{kHubsCollection}/{hubId}/events/{eventId}` and does not rewrite the rest of the document. For an import that id is `source:externalId` (for example `c2-rota:2026-09-20`). A later import that omits `status` still leaves the confirm alone.

Tom can mark a plan tentative from the app as well. On the Calendar tab, create or edit an event and turn **Tentative** on before saving — that writes `status: tentative` with the rest of the document. Off writes explicit `status: confirmed`. For a plan that is already booked, tap its chip (Calendar, or the day card in LOOK AHEAD) and choose **Mark tentative**. That updates only `status` to `tentative`, the same single-field write as confirm, in the other direction. **Keep confirmed** closes the sheet and leaves the document alone. CLI `--tentative` and `--confirm` are unchanged.

`--hub` overrides `HUB_ID`. With no `--file`, the script reads JSON from a
pipe.

```bash
cat rota.json | dart run tool/import_hub_events.dart --hub "$HUB_ID"
```

Dry-run with no token only checks the JSON. It does not resolve `tom` to a
uid and it does not write.

A second run of the same file overwrites those documents in place.

## Automatic C2 reconciliation

`tool/reconcile_c2_rota.dart` is a separate job. It does not import new shows.
It reads the Concorde feed and updates **existing** `c2-rota:{externalId}`
documents only: confirm a tentative show when Tom is working, leave an
undecided show tentative, and delete a tentative show when that show is
cancelled or `tom` is `not_working`. Confirmed documents stay as they are.
Personal, `seb`, and `rot90s` events are not read for changes.

A later `--tentative` import can mark a show tentative again. The next
reconcile confirms it if the feed still says Tom is working, or removes it
if the feed says that show is cancelled or not working. Details, the dry-run,
and the 15-minute activation are in [c2-rota-reconcile.md](c2-rota-reconcile.md).
