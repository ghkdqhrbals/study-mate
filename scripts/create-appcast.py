#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import html
import re


def parse_signature_attributes(raw: str) -> tuple[str, str]:
    signature_match = re.search(r'sparkle:edSignature="([^"]+)"', raw)
    length_match = re.search(r'length="([^"]+)"', raw)
    if not signature_match or not length_match:
        raise SystemExit(f"Could not parse Sparkle signature attributes: {raw}")

    return signature_match.group(1), length_match.group(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create StudyMate Sparkle appcast.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--dmg-url", required=True)
    parser.add_argument("--release-url", required=True)
    parser.add_argument("--signature-attributes", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    signature, length = parse_signature_attributes(args.signature_attributes)
    pub_date = format_datetime(datetime.now(timezone.utc), usegmt=True)

    appcast = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>StudyMate Updates</title>
    <link>https://ghkdqhrbals.github.io/study-mate/</link>
    <description>StudyMate release feed</description>
    <language>en</language>
    <item>
      <title>StudyMate {html.escape(args.version)}</title>
      <sparkle:version>{html.escape(args.build_number)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <pubDate>{pub_date}</pubDate>
      <link>{html.escape(args.release_url)}</link>
      <enclosure
        url="{html.escape(args.dmg_url)}"
        sparkle:edSignature="{html.escape(signature)}"
        length="{html.escape(length)}"
        type="application/x-apple-diskimage" />
    </item>
  </channel>
</rss>
'''

    with open(args.output, "w", encoding="utf-8") as file:
        file.write(appcast)


if __name__ == "__main__":
    main()
