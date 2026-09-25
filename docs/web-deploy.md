# Web deploy

Open phones and the wall tablet pick up a new Hosting build without a hard
refresh. The build id baked into the app is compared with Firestore
`appMeta/web`.

| Layout | What happens |
| --- | --- |
| Wall tablet / width ≥ 700 | Reloads once, quietly, when a newer id is stamped |
| Phone / width < 700 | Shows an **Update ready** chip. Reloads only when tapped |
| Sheet or dialog open | Chip, even on the tablet, so an edit is not thrown away |

The 700px split is the same one the dashboard uses for compact layout.

## Deploy

From the repo root, with `flutter` and the Firebase CLI logged in:

```bash
tool/deploy_hosting.sh
```

That script:

1. Sets `BUILD_ID` to `<git short sha>-<UTC timestamp>` when you did not export one.
2. Runs `flutter build web --release --dart-define=BUILD_ID="$BUILD_ID"`.
3. Runs `firebase deploy --only hosting:love-hub,firestore:rules --project lovehub-26107`.
4. Writes `{ buildId, updatedAt }` to `appMeta/web` with the same id.

Stamp **after** Hosting is deployed. An earlier stamp would reload the tablet
onto the old files, and the loop guard would then skip the real build.

To run the steps yourself:

```bash
export BUILD_ID="$(git rev-parse --short HEAD)-$(date -u +%Y%m%dT%H%M%SZ)"
flutter build web --release --dart-define=BUILD_ID="$BUILD_ID"
firebase deploy --only hosting:love-hub,firestore:rules --project lovehub-26107
dart run tool/stamp_web_build.dart --build-id "$BUILD_ID"
```

`BUILD_ID` has to be the value compiled into that upload. A dev
`flutter run` leaves it empty and does not prompt or reload.

## Stamp auth

`appMeta/web` is readable by any signed-in member. Client writes are denied
in `firestore.rules`. The stamp script uses a Google credential, which
bypasses security rules:

- `GOOGLE_ACCESS_TOKEN`, or
- `FIREBASE_TOKEN` from `firebase login:ci`, or
- the existing `firebase login` on this machine, or
- `gcloud auth print-access-token` if none of those are set.

Those rules ship with the Hosting deploy (`firestore:rules` in
`tool/deploy_hosting.sh`). Until that deploy, the old catch-all still lets any
signed-in client write the stamp.

Do not commit tokens, service-account JSON, or `.env` files. A Firebase Auth
ID token cannot write the stamp.

`--dry-run` prints the id and does not call Firestore.

## What the open app does

On web, once someone is signed in, the app listens to `appMeta/web` and also
re-reads it when the window gains focus, when the tab resumes, and about
every 10 minutes (the wall tablet). It does not check on ordinary taps.

A reload is skipped when:

- the remote `buildId` is missing or blank
- this build was not given a `BUILD_ID`
- this browser already tried to reload that remote id (stored in
  `sessionStorage`, so a bad stamp cannot loop)
- a dialog or bottom sheet is open (the chip is shown instead)

Only one automatic reload is attempted per remote id. If that reload already
happened and the page is still on the old build, the tablet shows the same
**Update ready** chip as the phone.

## Hosting cache

`firebase.json` marks `/`, `index.html`, the Flutter bootstrap, `main.dart.js`,
the service worker, `version.json`, and `manifest.json` as `no-cache`. Files
whose names contain a long hex hash are cached for a year. Header rules are
last-match-wins, so the no-cache entries come after the hashed-asset rule.
