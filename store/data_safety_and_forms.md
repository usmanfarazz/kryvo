# Kryvo — Play Console forms (answers)

Play Console asks several questions before an app can be published. These are
the answers for Kryvo as it is built today. If a feature changes (for example
something starts using the internet), these answers must change too.

---

## 1. Data safety  (Policy → App content → Data safety)

This form tells users, on the Play Store page, what data an app collects.
"Collect" means **sent off the phone** (to you or anyone else). Kryvo sends
nothing, because it has no internet permission.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | *(not asked when the answer above is No)* |
| Do you provide a way for users to request that their data is deleted? | *(not asked)* — data lives only on the phone; uninstalling deletes it |

Result on the store page: **"No data collected · No data shared with third
parties"**.

> Note: Google Play Billing (paid icons) is handled by Google Play itself and
> does not count as data collected by Kryvo.

---

## 2. Privacy policy  (Policy → App content → Privacy policy)

Paste this link: **https://usmanfarazz.github.io/kryvo/privacy.html**
(hosted with GitHub Pages from `docs/privacy.html` in the repo `usmanfarazz/kryvo`;
to change the policy, edit that file; keep `store/privacy_policy.html` the same).

---

## 3. App access  (Policy → App content → App access)

Choose **"All or some functionality is restricted"** and give the reviewers
instructions, otherwise they may reject the app because it opens on a lock
screen:

```
Kryvo is a vault and opens on its own lock screen.
1. On first launch, create any master password (e.g. Review2026!).
2. Use that password to unlock.
Optional: Settings → App icon & disguise → Calculator sets a secret code;
the vault then opens by typing that code and pressing "=".
```

---

## 4. Ads  (Policy → App content → Ads)

**No, my app does not contain ads.**

---

## 5. Content rating  (Policy → App content → Content rating)

Category: **Utility, Productivity, Communication, or Other**. Answer **No** to
every question (no violence, sexual content, gambling, user-to-user chat,
location sharing, etc.). Expected rating: **Everyone / 3+**.

---

## 6. Target audience  (Policy → App content → Target audience and content)

Choose **18 and over** (or 13+). Do not select children's age groups — that
would add the strict "Families" requirements.

---

## 7. Sensitive permissions — what to declare

| Permission | Declaration needed? | What to write |
|---|---|---|
| `FOREGROUND_SERVICE_SPECIAL_USE` | **Yes** (Foreground service form) | "App Lock: keeps a watcher running, with a visible notification, so a PIN screen appears when the user opens an app they chose to lock." Attach a short screen recording of App Lock. |
| `PACKAGE_USAGE_STATS` (Usage access) | Explain in the app (done: App Lock screen) | Used only on the phone to detect when a locked app is opened. |
| `SYSTEM_ALERT_WINDOW` | No form | Shows the App Lock PIN screen over locked apps. |
| `CAMERA` | No form | Intruder selfie, optional, off by default, photo stored encrypted on the phone. |
| `READ_MEDIA_IMAGES / VIDEO / AUDIO` | Possibly the **Photo and video permissions** form | Core feature: the user picks photos/videos to move into the encrypted vault, and Kryvo removes the originals from the gallery. A one-time picker is not enough because Kryvo must delete the originals and browse albums. |
| `RECEIVE_BOOT_COMPLETED` | No | Restarts App Lock after reboot. |
| Accessibility service | Not used ✅ | — |
| `QUERY_ALL_PACKAGES` | Not used ✅ (App Lock lists apps through `<queries>`) | — |
| `INTERNET` | Not used ✅ (removed on purpose) | — |

---

## 8. "Deceptive behaviour" — the disguise feature

Google checks that apps don't pretend to be something else to trick people.
Kryvo is fine as long as the store listing **says clearly** that it is a vault
that can look like a calculator / clock / etc. The listing in
`play_listing.md` already does this. Do **not** name the app "Calculator" on
the store.

---

## 9. Before the first upload (developer checklist)

- [ ] Create the upload signing key (keep the `.jks` file and password safe,
      with a backup copy)
- [ ] Build an **App Bundle** (`flutter build appbundle`)
- [ ] Set version in `pubspec.yaml` (e.g. `1.0.0+1`)
- [x] Host the privacy policy — https://usmanfarazz.github.io/kryvo/privacy.html
- [ ] Fill in the forms above
- [ ] Upload to **Internal testing** first, then Closed testing
- [ ] Create the paid icon products, then set `enforce = true` in
      `lib/services/purchase_service.dart`
