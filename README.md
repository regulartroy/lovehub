# lovehub

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web deploy

Hosting deploys stamp Firestore `appMeta/web` so an open browser can pick up
the new build. The wall tablet reloads once on its own; a phone shows an
**Update ready** chip. The script, the `BUILD_ID` dart-define, and the loop
guards are in [docs/web-deploy.md](docs/web-deploy.md).

```bash
tool/deploy_hosting.sh
```

## Work calendar import

Roger can upsert C2 rota, Sophie Ellis-Bextor, and ROT90s events without the
Flutter UI. The JSON schema, hub id, and hub-member auth are in
[docs/event-import.md](docs/event-import.md).

```bash
export HUB_ID='activeHubId from users/{uid}'
export FIREBASE_REFRESH_TOKEN='hub member refresh token'
dart run tool/import_hub_events.dart --tentative --file rota.json
dart run tool/import_hub_events.dart --confirm c2-rota:2026-09-20
```

Tom can also confirm a tentative shift in the app: tap the muted **?** chip on Calendar, or open that day in LOOK AHEAD and tap **Confirm I'm working this**. That sets the same `status: confirmed` field.

The reverse is in the app too. On create or edit, the **Tentative** switch writes `status: tentative` when on and `status: confirmed` when off. To flip a booked plan back, tap its chip on Calendar or in a LOOK AHEAD day, then **Mark tentative**. That sets only `status: tentative`, and the chip goes pale with **?**. **Keep confirmed** dismisses without writing.
