#!/usr/bin/env python3
"""Writes the Sparkle update feed (appcast.xml) for one release, for .github/workflows/release.yml.

The feed has a single item: the release's DMG with its EdDSA signature, and the release notes as Markdown (the
"## Install" section is left out: the update window installs it). Sign the written file afterwards with
`sign_update --ed-key-file - appcast.xml`, because the app requires a signed feed.

Usage: make-appcast.py --tag v1.2.0 --version 1.2.0 --build 57 --dmg Presenter-v1.2.0.dmg \
           --signature "<sparkle:edSignature value>" --notes docs/release-notes/v1.2.0.md --out appcast.xml
"""
import argparse
import email.utils
import os
import re
from xml.sax.saxutils import escape, quoteattr

REPOSITORY = "https://github.com/alps2005/PresenterApp"
MINIMUM_SYSTEM_VERSION = "14.0.0"


def release_notes(path):
    """The notes without their "## Install" section, or a pointer to GitHub when there are none."""
    if not path or not os.path.exists(path):
        return "See the release notes on GitHub."
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"(?ms)^## Install\b.*?(?=^## |\Z)", "", text).strip()
    if "]]>" in text:
        raise SystemExit("The release notes can't contain ']]>'")
    return text


def main():
    parser = argparse.ArgumentParser()
    for name in ("tag", "version", "build", "dmg", "signature", "notes", "out"):
        parser.add_argument(f"--{name}", required=name != "notes")
    args = parser.parse_args()

    url = f"{REPOSITORY}/releases/download/{args.tag}/{os.path.basename(args.dmg)}"
    length = os.path.getsize(args.dmg)
    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Presenter</title>
    <link>{escape(REPOSITORY)}</link>
    <item>
      <title>{escape(f"Presenter {args.version}")}</title>
      <link>{escape(f"{REPOSITORY}/releases/tag/{args.tag}")}</link>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
{release_notes(args.notes)}
]]></description>
      <enclosure url={quoteattr(url)} length="{length}" type="application/x-apple-diskimage"
                 sparkle:edSignature={quoteattr(args.signature)}/>
    </item>
  </channel>
</rss>
"""
    with open(args.out, "w", encoding="utf-8") as file:
        file.write(feed)


if __name__ == "__main__":
    main()
