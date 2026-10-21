# Security policy

## Supported versions

Only the latest release on the [Releases](https://github.com/alps2005/PresenterApp/releases)
page gets fixes.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately instead:
1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.

Include what's affected, how to reproduce it, and what an attacker could do with it. You'll get a reply within a
week. Once a fix is released, the report can be made public with credit to you, if you'd like.

## Scope

Presenter is a local macOS app: no accounts, servers or telemetry. Its only network use is Sparkle checking
GitHub for updates, through Sparkle's own downloader (the app itself has no network entitlement). The most relevant
areas are:
- **Project files:** opening a crafted project or exported archive (`ProjectArchive` only writes media into the
  app's media folder, by plain file name).
- **Media files:** importing crafted images and videos.
- **The app sandbox:** anything that reaches outside it.
- **Updates:** the feed (`appcast.xml` on the latest GitHub release) and each DMG are signed with an EdDSA key.
  The app holds the public key and refuses an unsigned or wrongly signed feed or update. The private key is the
  maintainer's, kept in their keychain and a password manager, and in the repository secret
  `SPARKLE_ED_PRIVATE_KEY` for the release workflow. Report anything that could get an update past these checks,
  or a release that looks tampered with.
