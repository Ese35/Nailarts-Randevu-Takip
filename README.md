# CEREN Nail & Beauty Studio

Flutter appointment app for Android, iOS, and web. Customer and appointment
records remain in the existing device/browser storage keys
`nailarts_customers` and `nailarts_appointments`.

## Firebase setup

The app stays in local-only mode when Firebase build settings are omitted. To
enable account login, cloud sync, and WhatsApp sending:

1. Create a Firebase project, enable Email/Password Authentication, create
   Firestore, and select the Blaze plan for Cloud Functions. Add the published
   web host (`ese35.github.io`) to Authentication's authorized domains. Create
   the owner's email/password user in Firebase Authentication; the app does not
   offer public account registration.
2. Install Node.js 22 and the Firebase CLI (`npm install -g firebase-tools`),
   sign in with `firebase login`, select the project with `firebase use --add`,
   and create a Firebase web app plus Android/iOS apps as needed.
3. Copy `functions/.env.example` to `functions/.env.<PROJECT_ID>` and set
   `ADMIN_EMAIL` to the verified owner account. Set the WhatsApp phone number
   ID and the approved template name/language there.
4. Save the Meta permanent access token as a Firebase secret:

   ```powershell
   firebase functions:secrets:set WHATSAPP_ACCESS_TOKEN
   ```

   Cloud Functions require Node.js 22 and the Firebase CLI.

5. Deploy the server and its deny-by-default Firestore rules:

   ```powershell
   npm --prefix functions install
   firebase deploy --only firestore:rules,functions
   ```

6. Pass Firebase's public app identifiers and the owner's email when building.
   App identifiers and the email are not credentials. For web, provide
   `FIREBASE_API_KEY`, `FIREBASE_ADMIN_EMAIL`, `FIREBASE_PROJECT_ID`,
   `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_AUTH_DOMAIN`, and
   `FIREBASE_WEB_APP_ID`. For Android provide the first four plus
   `FIREBASE_ANDROID_APP_ID`; for iOS provide the first four plus
   `FIREBASE_IOS_APP_ID` and `FIREBASE_IOS_BUNDLE_ID`.

   Example web build (replace each value with the Firebase console value):

   ```powershell
   flutter build web --base-href /Nailarts-Randevu-Takip/ `
     --dart-define=FIREBASE_API_KEY=<api-key> `
     --dart-define=FIREBASE_ADMIN_EMAIL=<owner-email> `
     --dart-define=FIREBASE_PROJECT_ID=<project-id> `
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender-id> `
     --dart-define=FIREBASE_AUTH_DOMAIN=<project-id>.firebaseapp.com `
     --dart-define=FIREBASE_WEB_APP_ID=<web-app-id>
   ```

On the first Firebase-enabled login, local records are merged with that
account's cloud records; local records take precedence for matching IDs.
Existing local records are never cleared. Deletions are synced as tombstones
after a successful server sync. Keep the published web origin unchanged so its
browser storage remains available.

## WhatsApp message template

`sendAppointmentReminder` is a manual, authenticated Cloud Function. The
recipient must have opted in, and Meta must have approved the configured
template. Its body must contain four text placeholders in this order:

1. Customer name
2. Appointment date
3. Appointment time (24-hour)
4. Service

The access token is read only from Firebase Secret Manager and is never placed
in the Flutter app or web build. The configured `ADMIN_EMAIL` must match the
verified Firebase account allowed to send.

The web/PWA cannot open the device contacts picker. Direct contact selection is
available in the Android/iOS app; use the existing PWA contact-entry flow
instead.
