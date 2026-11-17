# Interview-setup

Makes a Claude Code cloud session ready for an Ostorlab-style live interview
project (Python services on Docker Compose with Postgres and Redis, or plain
Python with SQLite). Examples of the format:
<https://github.com/Ostorlab/interview-project-examples>.

## Use

| When | Command |
|---|---|
| Start of a session | `scripts/bootstrap.sh` |
| Project received | `scripts/start-project.sh <zip \| folder \| git-url> [name]` |
| A Docker build fails with `CERTIFICATE_VERIFY_FAILED` | `scripts/trust-image.sh <image:tag>` |
| Hand-in | `scripts/package.sh work/<name>` |
| Prove the session can run their projects | `scripts/verify-examples.sh` |

`CLAUDE.md` is the playbook Claude follows during the interview: environment
facts, how to spend the hour, what the retired examples have in common.
`templates/CHOICES.md` is the skeleton for the required write-up.

`examples/` (clone of Ostorlab's examples) and `work/` (the interview project)
are git-ignored and never pushed.
