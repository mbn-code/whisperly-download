# Security policy

## Supported versions

Only the newest Windows build and the newest Mac build on the
[releases page](https://github.com/mbn-code/whisperly-download/releases) are
supported. Older versions receive no fixes.

## Reporting a vulnerability

Please do not open a public issue. Report it privately instead, either through
a [private security advisory](https://github.com/mbn-code/whisperly-download/security/advisories/new)
or by email to [malthe@mbn-code.dk](mailto:malthe@mbn-code.dk).

Include what the problem is and what it lets an attacker do, the steps to
reproduce it, and the Whisperly version and platform. You will get an
acknowledgement within a few days.

## What Whisperly does

- It records from the microphone and transcribes on the same computer, with a
  whisper.cpp server bound to `127.0.0.1` that is never reachable from the
  network.
- It pastes the text into the focused app. On Windows this needs no special
  permission; on a Mac it needs Accessibility and Microphone access, both
  granted by you.
- It verifies every downloaded speech model against a known SHA-256 and
  rejects a mismatch.
- Its update check asks for a version number, once a day on Windows and, on a
  Mac, at each start and from Check for Updates… in the menu bar. It sends
  nothing identifying beyond the user agent. On Windows it refuses redirects
  and ignores any download link that is not on the address it expects.

Out of scope: attacks that already need code running on your computer, bugs in
whisper.cpp itself (please report those upstream), and text that merely looks
confusing because of a dictionary or voice-command entry you made yourself.
