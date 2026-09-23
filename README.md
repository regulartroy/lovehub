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
