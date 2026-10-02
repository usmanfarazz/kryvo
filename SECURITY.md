# Security policy

Kryvo protects private data, so security reports are taken seriously.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Email
**usmanfaraz1818@gmail.com** with:

- a description of the issue and its impact,
- steps to reproduce (app version, Android version, device),
- any proof-of-concept, if you have one.

You will get a reply as soon as possible, and credit in the release notes if you wish.

## Scope

- The Android app in this repository (vault encryption, disguise, App Lock, fake PIN, backups).
- The website and live demo in `docs/` are static pages and hold no user data.

## Design summary

- No INTERNET permission; no data leaves the phone unless the user exports a backup.
- Media: AES-256-GCM with a random media key kept in Android Keystore–backed storage.
- Passwords / notes: AES-256-GCM with a key from PBKDF2-HMAC-SHA256 (310,000 rounds) of the
  master password; the master password is never stored.
- Full backups: the media key and item list are encrypted with the vault key, so a backup opens
  only with the master password.
