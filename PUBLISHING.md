# Publishing

This repository is public and holds two things: the website (`index.html` and
`assets/`, served by GitHub Pages from `main`) and the builds, attached to its
releases. The source code lives in the private `mbn-code/whisperly` and never
comes here.

## A new release

CI in the source repository builds the installer and attaches it to a release
there. Promote that build with one command from this folder:

```powershell
./Publish-Release.ps1 -Platform windows -FromTag windows-v0.6.3
./Publish-Release.ps1 -Platform mac -FromTag v1.0.2
```

To publish a file you built yourself, pass it instead:

```powershell
./Publish-Release.ps1 -Platform windows -File .\WhisperlySetup-v0.6.3.exe -Notes .\notes.md
```

Add `-WhatIfOnly` to run every check and see the notes as they will be
published, without publishing anything.

The script:

1. downloads the build from the source release (or takes your file) and refuses
   anything that is not an installer or a disk image, or whose embedded
   version disagrees with the tag;
2. cleans the notes: GitHub's generated "What's Changed" list and any line
   linking into the private repository are dropped, because a visitor would only
   get a 404 from them; notes that quote a SHA-256 other than the file's own are
   refused;
3. creates the release here, with the file and a `.sha256` next to it (and the
   portable zip, for Windows). Windows 0.x builds are marked as pre-releases;
4. checks that the download works without a GitHub account;
5. only then commits `windows-latest.json` or `mac-latest.json` and pushes.

The website reads that manifest for the version, date, size, notes and checksum,
so `index.html` never needs editing for a release.

## What reads the manifests

| File                  | Read by                                               |
| --------------------- | ----------------------------------------------------- |
| `windows-latest.json` | the website, and the Windows app's daily update check |
| `mac-latest.json`     | the website                                           |

The Mac app checks this repository's releases through the GitHub API instead:
it takes the highest plain `vX.Y.Z` tag that is not a pre-release, and ignores
`windows-` tags. It reads the newest 20 releases, so publish a Mac release
before 20 Windows releases pile up on top of the last one.

Mac 1.0.1, the build published now, does not do this: it asks the private
source repository instead, which an anonymous request cannot see, so it never
reports an update. Until a Mac build that reads this repository ships, Mac
users learn about new versions only from the website and the releases page.

The Windows app refuses a manifest over 16 KB, a redirect, and a download URL
anywhere but this repository or its site. The script enforces the size; the
rest means two things:

- **Never put a custom domain on this site** without first shipping an app that
  expects it. Pages would redirect `mbn-code.github.io/whisperly-download/` to
  the new domain, and every installed copy would stop seeing updates.
- **Publish the manifest last.** The script does, so no installed copy is ever
  told about a version it cannot download yet.

## Changing the website

Edit `index.html` (styles and script are inline), commit and push. Pages
rebuilds within a minute or two. Images live in `assets/`; the social card
`assets/card.png` is 1200 by 630.
