# Interview session playbook

This repository prepares a Claude cloud session for a **live one-hour Ostorlab
Software Engineering Intern interview**. The candidate (the user) works on a
project Ostorlab hands over at the start of the call, with AI tools allowed and
expected. The call is recorded and Ostorlab looks at *how the candidate directs
the AI and checks its output*. The user decides; you execute, verify and report.

Reference material: `examples/` is a clone of
`github.com/Ostorlab/interview-project-examples` (retired exercises; the real
one will be different but shaped the same). Relevant folder:
`examples/02-interview_projects/software-engineer/`.

## 1. Start of every session

```bash
scripts/bootstrap.sh
```

Idempotent. Starts the Docker daemon (it is installed but not running in a
fresh container), pulls the base images, makes them trust this session's
egress-proxy CA, clones `examples/`, prints the toolchain. Must end in `READY`.

## 2. When the project arrives

```bash
scripts/start-project.sh <zip | folder | git-url> [name]
```

Puts it in `work/<name>` (git-ignored here), makes a baseline commit inside the
project's `workspace/`, prepares its Docker images. Then read the brief's
**Setup** line and run exactly that (usually `make setup`, then `make test`)
**before the 60-minute clock starts**. Report the passing test count as the
baseline.

Practice on a retired example:
`scripts/start-project.sh examples/02-interview_projects/software-engineer/005-blocked-despite-waiver practice-005`

## 3. Environment facts that differ from a laptop

- **Docker builds**: containers reach the internet but do not trust the
  session's TLS-inspecting proxy, so `pip install`/`npm ci`/`apk add` fail with
  `CERTIFICATE_VERIFY_FAILED` on an unprepared base image. Fix:
  `scripts/trust-image.sh <image:tag>` (rebuilds the same tag with the CA
  added), then rebuild. Never edit the project's Dockerfile for this, and never
  disable TLS verification.
- **Docker Hub rate limit (429)**: `trust-image.sh` retries and falls back to
  `mirror.gcr.io/library/...` and `public.ecr.aws/docker/library/...`.
- **Host ports** (`127.0.0.1:8080` and the like) are inside this container, not
  on the user's machine. Check APIs with `curl`, the project's in-process test
  client or benchmark script; for a dashboard, take a Playwright screenshot and
  show it, or report the port for the app's preview pane.
- **Compose services do not reload code** unless the brief says so. After code
  changes restart the services the brief names (`docker compose restart ...`);
  after a new migration run `make migrate`.
- **Pinned demo clocks** (`ATLAS_NOW`, `GATE_NOW`, ...): the seeded "today" is
  the date in the brief, not the real date. Never use the wall clock in
  reasoning about demo data.
- Host Python is 3.13 (3.12 and 3.11 also installed as `python3.12`,
  `python3.11`); `psql`, `redis-cli`, `sqlite3`, `jq`, `rg`, `ruff` are on the
  host. Projects that say "everything runs in Docker" should be run through
  their Makefile, not on the host.
- **Never push the interview project to GitHub** and never commit `work/` to
  this repository: the rules say not to publish anything. Hand-in is a zip:
  `scripts/package.sh work/<name>`, then send the zip to the user as a file.

## 4. How the hour should go

The material is deliberately larger than anyone can read in an hour. Read
selectively, in this order, and say what you skipped.

| Minutes | What |
|---|---|
| before clock | bootstrap, start-project, `make setup`, `make test` baseline |
| 0-8 | Brief (`README.md` next to `workspace/`): mission, **"At minimum"** list, deliverables. The main ticket in `docs/requests/` **including every comment**. Only the sections of `docs/architecture.md` / `docs/api.md` that the ticket touches. |
| 8-12 | Give the user a plan of at most 10 lines: the minimum items as a checklist, where each lands in the code, what is out of scope, open questions with a proposed assumption. **Wait for the user's go.** |
| 12-45 | Work the checklist top-down. Failing test or exact reproduction first, then the fix. Small commits. Run the narrow test often, the full suite before each commit. |
| 45-55 | Full `make test`, measure/reproduce the result end to end on the seeded stack, answer every question the ticket asks with real numbers. |
| 55-60 | `CHOICES.md` (at most 250 words), final commit, `scripts/package.sh`. |

Stop adding scope at minute 45. Unfinished work is acceptable if `CHOICES.md`
says what is missing and what would come next; a broken test suite is not.

## 5. What the retired examples have in common

- **The brief's "At minimum" sentence is the checklist.** Every clause is
  something they will check. Do those first, in full, before anything optional.
- **Ticket comments carry the real spec.** A senior person's comment usually
  pins exact field names, boundaries (for example "exactly N days is stale, N-1
  is not"), job and command names, and constraints such as "do not change other
  tools' fingerprints" or "must stay backwards compatible". Follow them
  literally; they are written so reviewers can test against them.
- **Later comments can overrule the ticket body** ("that line is not decided",
  "this file was cut off when the runner timed out"). The newest authoritative
  statement wins; say so in `CHOICES.md`.
- **Stakeholders ask questions with a wrong premise or that need a number**
  ("will each team get an e-mail?" when delivery is webhooks only; "how many
  are stale today?"). Answer each one explicitly: which expectation holds,
  which does not, what they must decide, and the measured number.
- **Other tickets in `docs/requests/` are distractors**, though they sometimes
  explain data oddities. Do not fix them.
- **Inputs contain traps**: truncated or malformed files that must be rejected
  with no writes, duplicate or overlapping ids, timezones and DST, tenant
  isolation, 0- versus 1-based values, idempotent replays, AI-written code
  whose tests are green but wrong.
- **Existing consumers must keep working**: add parameters, do not change
  defaults, response shapes, fingerprints or stored keys.
- **Evidence over claims**: before/after numbers measured here, a failing test
  that now passes, the exact command to reproduce.
- Stacks seen: Python 3.12 with FastAPI, Django 5.1 + DRF, or Flask; SQLAlchemy
  + Alembic; Postgres 16; Redis 7; a job worker and scheduler; signed webhooks
  with a mock receiver; pytest (about 300 tests); one stdlib-only + SQLite +
  unittest project. Task types: performance at scale, reviewing an AI-written
  PR, integrating a new input format, a new feature across layers, incident
  root cause with production logs and exports.

## 6. Working rules during the interview

- Facts come from `workspace/` only. Quote file and line for every claim about
  behaviour; never invent an API, field or number. If something is unclear,
  make a reasonable assumption and record it for `CHOICES.md`.
- Keep answers short enough to read aloud: what you found, what you propose,
  what you need decided. The user is narrating to an interviewer.
- Keep a running list of **AI outputs the user corrected or rejected** (and
  your own first attempts that verification proved wrong). `CHOICES.md` must
  cite one, and it must be true.
- Do not weaken, skip or delete existing tests to get green. Do not reformat
  files you are not changing. Match the code base's conventions (its README
  usually has a "Conventions" section).
- New migrations follow the project's numbering; data that must exist "from a
  fresh `make setup`" also needs the seed updated, not only a migration.
- Measure performance with the project's own benchmark script on the seed size
  the brief names; record baseline numbers **before** changing anything.
- `CHOICES.md` goes in the workspace root, starts from `templates/CHOICES.md`,
  and covers: what was built and why, what was left out, how it was checked,
  one AI output corrected or rejected. Count the words.

## 7. Scoring (from the briefs)

Result 35 (does it work and help the named requester), accuracy 25 (correct
against the material), judgment 20 (scope and trade-offs), process 20 (how the
work was done, as seen in the recording). Not scored: typing speed, tool
choice, polish, volume.
