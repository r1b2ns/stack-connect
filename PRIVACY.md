# StackConnect Privacy Policy

_Last updated: November 22, 2026_

StackConnect is an open-source iOS app for managing App Store Connect, Firebase and Google Play accounts from your iPhone or iPad. This policy explains what data the app handles, where it goes, and the choices you have.

**In short:** your credentials and your app data stay on your device and are sent only to Apple and Google, the services you connected. StackConnect has no servers and no accounts of its own. The only data that reaches the developer is anonymous usage analytics and crash reports, and you can turn both off in Settings.

## 1. Data that stays on your device

| Data | Where it is stored | Leaves the device? |
|------|--------------------|--------------------|
| API keys, `.p8` private keys, service-account JSON files and access tokens | iOS Keychain | Only to authenticate with Apple or Google (see section 2) |
| The App Store Connect session of an account added with "Sign in with Apple ID" (the session cookies Apple returns) | iOS Keychain, one item per Apple ID | Only to Apple, with each request of that account |
| The Apple ID password of an account added with "Sign in with Apple ID", saved after a successful sign-in | iOS Keychain, one item per Apple ID, on this device only (not synced, not backed up to other devices) | Only to Apple, when you sign in again with that Apple ID |
| Account names, apps, versions, builds, reviews, testers, users and other data loaded from the services you connect | On-device database (SwiftData), in the app's App Group container | No |
| Widget data (app names, icons, recent reviews) | The same App Group container, shared only with the StackConnect widget | No |
| Settings and preferences | On-device storage (UserDefaults) | No |

Deleting an account in the app removes its credentials from the Keychain and its data from the database. The session and the saved password of an Apple ID are removed with the last account that uses them. Deleting the app removes all of it.

### Signing in with an Apple ID

If you add an App Store Connect account with "Sign in with Apple ID" instead of an API key:

- Your Apple ID password and your two-factor code are processed on your device and sent only to Apple, to sign in. They are never logged, sent to the developer or included in analytics or crash reports. The two-factor code is never stored.
- What is kept is the session Apple returns (its cookies) and, once Apple accepted it, your Apple ID password. Both are stored in the iOS Keychain on this device only: they are not synced through iCloud Keychain, can only be read while the device is unlocked, and are never exported. The session is used only for requests to Apple's App Store Connect and Apple Developer websites; the password only to sign in to Apple again.
- When the session expires, the app asks you to sign in again. If a password is saved, it signs in with it and you only type the two-factor code; you can choose "Use a Different Password" instead. If Apple refuses the saved password (for example because you changed it), the app deletes it and asks you for the current one.

## 2. Services the app connects to on your behalf

StackConnect talks **directly** from your device to the official APIs of the services you choose to connect, using the credentials you provide. No proxy or StackConnect server sits in between.

- **Apple:** the App Store Connect API (`api.appstoreconnect.apple.com`) and the public iTunes Lookup API (`itunes.apple.com`), used for rating summaries. Accounts added with "Sign in with Apple ID" use Apple's sign-in service (`idmsa.apple.com`), App Store Connect (`appstoreconnect.apple.com`) and the Apple Developer website (`developer.apple.com`) instead of the API.
- **Google:** Google OAuth, the Firebase Management, Remote Config, Cloud Messaging and Analytics Data APIs, the Google Play Developer API, and Google Play image servers for app icons.

What these services do with your requests is governed by their own policies:

- [Apple Privacy Policy](https://www.apple.com/legal/privacy/)
- [Google Privacy Policy](https://policies.google.com/privacy)

## 3. Usage analytics and crash reports

To learn which features are used and where the app fails, StackConnect sends **anonymous** usage events through Google Analytics for Firebase, and crash reports through Firebase Crashlytics.

### What is collected

- **Screens and buttons:** fixed screen and button names, for example `home` or `submit_for_review`.
- **Action outcomes:** a fixed action name, its result (`success`, `failure`, `cancelled`) and, on failure, an error *category* such as `network`, `server` or `invalid_credentials`. Error messages are never sent.
- **Coarse, bucketed values:**
  - how many items an action affected;
  - how long a sync took (for example `5_15s`);
  - how many search results were found (for example `2_5`);
  - the kind of release track;
  - whether the app was opened from a notification, a widget or a link, and the kind of screen it opened.
  - on iPad and Mac, the kind of sidebar section opened (for example `recent_reviews` or `account_apps`, never which account) and whether it was opened from the sidebar, a menu command or a dashboard tile.
- **Segment properties:**
  - the number of connected accounts, in buckets (`0`, `1`, `2`, `3+`);
  - which kinds of store are connected (Apple, Firebase, Google Play);
  - whether notifications are allowed.
  - whether the compact (iPhone) or the regular (iPad and Mac split view) layout is on screen.
- **Standard device information:** app version and build, iOS version, device model, language, approximate country (from the IP address, which Google does not store), and the automatic Firebase events `first_open`, `session_start` and `user_engagement`.
- **Crash reports:** the stack trace and device and OS state at the time of a crash. A few handled errors are also recorded, keeping only their error domain, code and category. Messages, URLs and response bodies are removed.

### What is never collected

- Account names, API keys, private keys, tokens, Apple ID passwords, two-factor codes, session cookies or any other credential.
- App names, bundle identifiers, review text, tester or user names, email addresses, or any other content from your App Store Connect, Firebase or Google Play accounts.
- Anything you type, including search queries.
- The advertising identifier (IDFA) or the identifier for vendor (IDFV). StackConnect does not use App Tracking Transparency and does not track you across apps or websites.

Firebase gives each installation a random identifier to tell installations apart. StackConnect never links it to you, your accounts or any other identifier. Analytics data is not used for advertising and is not sold or shared with third parties for their own purposes.

See [Firebase privacy and security](https://firebase.google.com/support/privacy) for how Google processes this data.

### Turning it off

Analytics and crash reports are on by default and can be turned off at any time in **Settings → Privacy → Share usage analytics**.

- Collection starts disabled at every launch and is switched on only while that setting is on, so an opted-out device sends nothing, not even a first-open event or a crash report.
- When you turn it off, one final `analytics_disabled` event is sent so the developer can count opt-outs. Nothing is sent after that.

Builds of the open-source code without a Firebase configuration file send no analytics or crash data at all.

## 4. Purchases

The optional tip jar uses Apple's In-App Purchase. Payment is handled entirely by Apple: StackConnect never sees your payment details. Only the outcome and the fixed product identifier of a tip are recorded in analytics, never the price, the receipt or a transaction identifier.

## 5. Exported account files

You can export an account to a file, for example to move it to another device. The file is encrypted with a password you choose. It is shared only where you send it, and it is never uploaded by the app. Accounts added with "Sign in with Google" or "Sign in with Apple ID" can't be exported.

## 6. Notifications

Notifications are generated locally on your device (for example when a review status changes) after a background sync. StackConnect does not use a push notification server.

## 7. Data retention

- **Data on your device:** kept until you delete the account in the app or delete the app.
- **Analytics events:** kept by Google Analytics for the retention period configured for the project, at most 14 months.
- **Crash reports:** kept by Firebase Crashlytics for 90 days.

## 8. Children

StackConnect is a developer tool and is not directed at children under 13. It does not knowingly collect data from children.

## 9. Your rights

Because analytics data is anonymous and cannot be linked to you, the developer cannot look it up or delete it for a specific person. You can stop future collection at any time with the setting in section 3, and remove everything stored on your device by deleting the app. Depending on where you live (for example under the GDPR or the LGPD), you may have further rights. Contact the developer to exercise them.

## 10. Changes to this policy

Changes to this policy are published in this file, and the date at the top is updated. Its full history is in this repository's commit log.

## 11. Contact

For questions about this policy, please [open an issue](https://github.com/r1b2ns/stack-connect/issues) on the project's GitHub repository.
