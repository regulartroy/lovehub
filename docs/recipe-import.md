# Recipe link import

Kitchen → Recipes → **Import link**. Paste a recipe URL. LoveHub fetches the
page, reads the recipe, and opens it for editing. Nothing is saved until
**Save to Cookbook**.

Saved recipes use the existing cookbook fields (`title`, `ingredients`,
`method`, `createdAt`) plus an optional `sourceUrl`. **Check ingredients** on
the recipe is unchanged: unticked lines are added to the Shopping list, with
the same aisle `sortIndex` the list uses when Smart Sort is off.

The example
`https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice`
works. On 10 Nov 2026 that page published schema.org **microdata**
(`itemscope itemtype="http://schema.org/Recipe"`), not JSON-LD. Most other
recipe sites publish JSON-LD. The parser tries JSON-LD first and uses
microdata when JSON-LD has no ingredients or steps.

## Pictures

Every recipe can have one picture. In **New Recipe** or **Edit Recipe**, use
**Take photo** (the phone camera), **Choose photo** (the library, or a file
chooser on the web), or **Remove picture**. The picture replaces the
cutlery placeholder on the Recipes grid and sits at the top of the recipe.
Recipes without one keep the placeholder.

When a link is imported, `importRecipePage` also returns `imageUrl`: a
suggested picture from the page. It looks for the JSON-LD Recipe `image`
(a string, an array, or an ImageObject; the widest one wins), then
microdata `itemprop="image"`, then `og:image` / `twitter:image`. Relative
links are resolved against the page. The app then calls `fetchRecipeImage`
to download it, because recipe sites don't let a browser read their images
(CORS). The suggestion shows in the preview and is kept by default. Tom can
remove it (and bring it back), or replace it with his own.

`fetchRecipeImage` (callable, `europe-west2`) uses the same SSRF guards as
the page fetch. It only returns JPEG, PNG, WebP, or GIF, checked against the
file's first bytes as well as the header, and it refuses anything over 5 MB.
It returns base64, and nothing is stored until **Save**. Same sign-in and
hub check as the import, with 30 pictures per user per minute.

The app shrinks every picture before upload: the longest side becomes 1200px,
it is saved as a JPEG at quality 80, it is turned upright, and transparent
areas become white. The upload goes to Firebase Storage at
`hubs/{hubId}/recipes/{recipeId}/{millis}.jpg`, and the recipe doc gets
`imagePath` and `imageUrl` (the download URL). Replacing or removing a
picture, or deleting the recipe, deletes the old object.

`storage.rules` (deployed with `firebase deploy --only storage`) allows
recipe pictures for signed-in users only. Uploads must be `image/jpeg`,
`png`, `webp`, or `gif`, and under 5 MB. The existing `hubs/{hubId}/photos`
gallery rule is unchanged.

## Why a Cloud Function

The app is Flutter web on `love-hub.web.app`. A browser cannot fetch
`nigella.com` (or any other recipe site) because of CORS. The import calls
the callable function `importRecipePage` in `europe-west2`. The function
downloads the HTML. The app parses it. Firebase AI Logic is not used.

Tradeoffs:

| Approach | Why it was or wasn't used |
| --- | --- |
| Parse in the browser | Blocked by CORS. |
| Public CORS proxy | Extra party sees the link, and it is a poor place to enforce auth or SSRF limits. |
| JSON-LD only | Misses Nigella, which publishes microdata. |
| Gemini / AI Logic | Turned off, and App Check is not enforced. A model is also a worse fit than the structured data the sites already publish. |
| Parse inside the function | Would mean a second parser in Node. The Dart parser is the one the tests cover, so the function only fetches. |
| Return the HTML to the app | One parser, and the preview/edit step stays in the app. The response is capped at 1.5 MB. |

The function is callable only. It requires a signed-in Firebase user who is a
member of the hub (`users/{uid}.joinedHubs.{hubId}`, or `hubs/{hubId}.members`).
App Check is left off, matching the rest of LoveHub.

SSRF limits on the function (the browser checks the same obvious cases before
the call, but the function is the boundary):

- `http` and `https` only, ports 80 and 443
- no username or password in the URL
- hostnames such as `localhost`, `.local`, `.internal`, and the GCP metadata host are refused
- DNS answers are checked, and the connection uses that address (so a name cannot switch to a private IP after the check)
- redirects are checked again, up to 4
- 8s per request, 20s overall, 1.5 MB body
- HTML, XML, JSON, or plain text only
- 20 imports per signed-in user per minute, per instance

A refused link comes back as a normal error. The sheet offers **Add by hand instead**.

## Cost and the Blaze plan

Cloud Functions need the **Blaze** (pay as you go) plan. Spark cannot deploy
them, because outbound networking and Cloud Build are not on Spark. Blaze
still includes the functions free tier: about 2 million invocations, 400,000
GB-seconds, 200,000 GHz-seconds, and 5 GB of outbound networking a month.
One import is a 256 MB function for a few seconds, plus the page download
(Nigella's page is about 140 KB). A household importing recipes is inside
that free tier. There is no Gemini charge.

Firestore adds one or two document reads per import (the user and, if needed,
the hub) via the Admin SDK. Saving the recipe is the same client write as
**New Recipe**.

`tool/deploy_hosting.sh` does **not** deploy this function. Hosting and the
function are separate so a hosting deploy does not start failing on a project
that is still on Spark.

## Deploy

Leave this to whoever deploys LoveHub. Do it from the repo root, with the
Firebase CLI logged in as someone who can deploy functions on `lovehub-26107`.
The project must be on Blaze. The first deploy enables Cloud Functions,
Cloud Build, Artifact Registry, and Cloud Run if they are not already on.

Function first, then the web app, so the button works when phones and the
tablet pick up the new build:

```bash
cd functions && npm ci && cd ..
firebase deploy --only functions:importRecipePage,functions:fetchRecipeImage,storage --project lovehub-26107
tool/deploy_hosting.sh
```

`tool/deploy_hosting.sh` builds Flutter web, deploys Hosting target `love-hub`
and the Firestore rules, then stamps `appMeta/web`. See
[web-deploy.md](web-deploy.md). The function region is `europe-west2`. The
app calls that same region.

2nd gen callable functions run on Cloud Run. The CLI grants public invoke
because Firebase Auth is checked inside the function, not by Cloud Run. If
an organisation policy blocks `allUsers`, the deploy will say it could not
set the invoker. An admin then needs:

```bash
gcloud run services add-iam-policy-binding importrecipepage \
  --region=europe-west2 \
  --member=allUsers \
  --role=roles/run.invoker \
  --project=lovehub-26107
```

The service name is lower case. Auth is still required: unsigned callers get
`unauthenticated`, and a signed-in user who is not in the hub gets
`permission-denied`.

No service-account JSON, token, or `.env` is required in the repo. The
function uses the default credentials of the Cloud Functions runtime.

## Tests

```bash
flutter test test/recipe_picture_test.dart test/recipe_page_parser_test.dart test/recipe_url_test.dart test/recipe_import_client_test.dart test/recipe_link_import_sheet_test.dart test/shopping_list_items_test.dart
cd functions && node --test
```

The Nigella fixture is the recipe `<main>` from the live page. The JSON-LD
fixture is that same recipe transcribed into schema.org JSON-LD (with a
HowToSection) because the live page does not include a JSON-LD block.
