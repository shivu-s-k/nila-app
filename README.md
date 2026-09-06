# MyTemplate

MyTemplate is a Flask SaaS starter — user authentication, OAuth, teams, billing,
an admin dashboard and file uploads — wrapped in a repeatable quality pipeline
that runs the same way locally and in CI.

Derived from the [Ignite](https://github.com/Sumukh/Ignite) starter project. See
[Credits and licence](#credits-and-licence).

---

## Quickstart

Requires Python 3.11+.

```bash
make setup        # create ./env, install dependencies, install the Chromium browser
make resetdb      # create and seed the local dev database
make run          # http://localhost:5000
```

Log in with the seeded account:

| Email               | Password | Role  |
| ------------------- | -------- | ----- |
| `user@example.com`  | `test`   | user  |
| `admin@example.com` | `admin`  | admin |

## Running the checks

The whole gate is one command:

```bash
make ci
```

That runs, in order — fast checks first, so a syntax error doesn't wait on a browser:

| Step           | Tool               | What it does                                  |
| -------------- | ------------------ | --------------------------------------------- |
| `lint`         | Ruff               | Static analysis; fails on any finding          |
| `security`     | Bandit             | Security scan; fails on medium-or-higher       |
| `test-backend` | pytest + pytest-cov| Backend tests, JUnit XML, coverage XML + HTML  |
| `test-ui`      | Playwright         | Browser tests against a real running app       |

Each step also runs on its own — `make lint`, `make security`, `make test-backend`,
`make test-ui` — so a failure points at exactly one thing. `make help` lists
every target.

### Simulating the CI run after a commit

```bash
git commit -m "your change"
./scripts/simulate-ci.sh
```

The script prints the commit under test and runs `make ci`. The GitHub Actions
workflow ([.github/workflows/ci.yml](.github/workflows/ci.yml)) calls the same
`make` targets in the same order, so a green run here means the same thing as a
green run on a pull request. There is no CI-only build logic.

## Build artifacts

Everything lands in `reports/`, regenerated on each run:

| Artifact                          | Contents                                     |
| --------------------------------- | -------------------------------------------- |
| `junit-backend.xml`               | Backend test results (JUnit XML)             |
| `junit-ui.xml`                    | Playwright UI test results (JUnit XML)       |
| `coverage.xml`                    | Coverage, machine-readable (Cobertura)       |
| `coverage-html/index.html`        | Coverage, browsable per-file with highlights |
| `ruff.json` / `ruff.txt`          | Static analysis, machine- and human-readable |
| `bandit.json` / `bandit.txt`      | Security scan, machine- and human-readable   |
| `ui-artifacts/`                   | Screenshots and video, **failed UI tests only** |

`make reports` prints this list with the current contents of the directory. In
CI the whole directory is uploaded as an artifact, including on failure — a red
build is exactly when you want the failure screenshots.

Current state: **115 tests passing, 86% backend coverage**, Ruff and Bandit clean.

## Tests

```
tests/
├── test_branding.py       # the rename + login flow, via the Flask test client
├── test_urls.py, ...      # the starter suite (auth, teams, billing, API, models)
└── ui/
    ├── conftest.py        # runs the real WSGI app on a background thread
    └── test_login_flow.py # Playwright: landing page -> signup/login -> dashboard
```

The tests are deliberately small. They cover the flows a customer actually
walks — landing on the marketing page, signing up, logging in, reaching the
dashboard — and assert the MyTemplate branding is what they see, rather than
exhaustively exercising every model method.

The UI suite starts the app itself on a free port, so `make test-ui` needs no
separately running server. It uses `UiTestConfig`, which is `TestConfig` with the
Flask debug toolbar switched off — the toolbar's overlay sits on top of the page
and swallows clicks meant for the app.

## Configuration

Environment is selected by `APPNAME_ENV` (`dev`, `test`, `prod`), which maps to a
config class in [appname/settings.py](appname/settings.py). The `make` targets
set it for you.

To configure OAuth login and Stripe billing in development:

```bash
cp .env.local.sample .env.local
# add your Stripe & Google test keys
source .env.local
make run
```

The application name and logo live in
[appname/services/branding.py](appname/services/branding.py) — templates read
`branding.name` rather than hardcoding a product name, so a future rename is one
file.

## Notes on this build

Changes made on top of the upstream starter:

- **Renamed Ignite → MyTemplate** across page titles, headers, email subjects,
  logo assets (`static/public/mytemplate/`), metadata and README. The Python
  package stays `appname` — that is the upstream package name, not branding, and
  renaming it would churn every import for no user-visible gain.
- **Fixed a baseline break**: `CACHE_TYPE` used the pre-2.0 Flask-Caching values
  (`'null'`, `'simple'`, `'redis'`). Against the pinned Flask-Caching 2.x these
  raise `ImportStringError` and the app would not boot. Now `NullCache`,
  `SimpleCache`, `RedisCache`.
- **Replaced flake8 with Ruff** and cleared the findings it surfaced: ~20 dead
  imports, a shadowed `stripe` import, a `.format()` call with an argument that
  went nowhere, an exception re-raised without its cause.
- **Two Bandit findings, both addressed**: MD5 used to derive a token salt now
  passes `usedforsecurity=False` (it namespaces tokens, it is not the security
  boundary — `SECRET_KEY` is); and the `manage.py server` debug helper carries a
  `# nosec B201` with the reason, since production serves via gunicorn.

The Ruff rule set is deliberately narrow — `E`, `F`, `B`. Enabling the
import-sorting and pyupgrade families produced ~110 further findings on
inherited code that were pure restyling; a gate that noisy trains people to
ignore it. See [pyproject.toml](pyproject.toml), where the reasoning is recorded
next to the config.

## Deployment

**Live on AWS free tier: http://3.84.66.220/**

Deployed to an EC2 `t3.micro` (Amazon Linux 2023) running gunicorn behind nginx,
managed by systemd. One command from a checkout:

```bash
EC2_HOST=<ip> EC2_KEY=<path-to.pem> ./deploy/aws/deploy.sh
```

That ships the tracked tree, installs Python 3.11 and nginx, builds the
virtualenv, creates the database, and starts the services. It is safe to re-run:
the first deploy and every later one take the same path, so there is no separate
update script to drift out of sync. Secrets in `/etc/mytemplate.env` are
generated once and preserved across redeploys, so sessions survive an update.

`deploy/aws/` holds the systemd unit, the nginx site and the bootstrap script.

**No seed accounts exist on the deployed instance** — the box is reachable from
the internet, and shipping a known `user@example.com` / `test` login to it would
be careless. Sign up through `/signup` to get in; that exercises the real flow
anyway.

Known gaps, deliberate and documented in `DeployConfig`:

- **Plain HTTP, no TLS.** The `Secure` cookie flags are therefore off, since a
  Secure cookie is never sent over HTTP and login would fail silently. Put a
  certificate in front (ALB, CloudFront or certbot) and turn them back on.
- **SQLite, not Postgres**, and an in-process cache instead of Redis. Fine for a
  single box; replace both before this takes real traffic.
- **Background jobs run inline** rather than through an RQ worker.

The project is not tied to AWS — it also runs on Heroku and Dokku; see
[documentation/](documentation/).

## Credits and licence

MyTemplate is built on [Ignite](https://github.com/Sumukh/Ignite) by Sumukh
Sridhara, which is a **commercial product**. The upstream licence terms in
[LICENSE.md](LICENSE.md) continue to apply to this derivative: private
non-commercial use is free, and commercial use requires purchasing a licence
from the [Ignite store](https://gumroad.com/l/xFvLo) or via the
[Fullstack Flask course](https://www.newline.co/fullstack-flask/).

Design elements from [tabler](https://github.com/tabler/tabler) and Bootstrap 4.
