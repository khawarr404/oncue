# Security

oncue runs on your computer and handles private meeting audio and transcripts, so security reports are
taken seriously.

## Reporting a problem

Please **do not open a public issue**. Report it privately through
[GitHub's private vulnerability reporting](https://github.com/khawarr404/oncue/security/advisories/new).
Include what you found, how to reproduce it, and what an attacker could do with it. You should get a reply
within a week.

## In scope

- The local dashboard (`127.0.0.1`), its API and its token check
- Anything that could send audio, transcripts, notes or API keys off the machine without the user choosing it
- Command injection through transcript text, file names or settings
- The install and setup scripts

## Supported versions

Only the latest release on `main` gets fixes.
