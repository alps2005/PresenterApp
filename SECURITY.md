# Security policy

## Supported versions

Presenter is in beta. Only the latest release on the [Releases](https://github.com/alps2005/PresenterApp/releases)
page gets fixes.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately instead:
1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.

Include what's affected, how to reproduce it, and what an attacker could do with it. You'll get a reply within a
week. Once a fix is released, the report can be made public with credit to you, if you'd like.

## Scope

Presenter is a local macOS app with no network features: no accounts, servers or telemetry. The most relevant
areas are:
- **Project files:** opening a crafted project or exported archive (`ProjectArchive` only writes media into the
  app's media folder, by plain file name).
- **Media files:** importing crafted images and videos.
- **The app sandbox:** anything that reaches outside it.
