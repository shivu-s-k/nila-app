# MyTemplate build pipeline
#
# Every target writes its report into ./reports so the same commands produce the
# same artifacts locally and in CI. `make ci` is the whole gate in one command.

.PHONY: help setup deps browsers clean run resetdb \
        test test-backend test-ui lint security coverage reports ci

PYTHON      ?= env/bin/python
PIP         := $(PYTHON) -m pip
REPORTS     := reports
export APPNAME_ENV ?= test

# Fail early with a useful message instead of "No such file or directory".
define REQUIRE_ENV
@if [ ! -x "$(PYTHON)" ]; then \
	echo "==> Python env not found at $(PYTHON). Run 'make setup' first."; exit 1; \
fi
endef

help:
	@echo "MyTemplate -- available targets"
	@echo ""
	@echo "  setup         create ./env and install all dependencies"
	@echo "  browsers      install the Playwright Chromium browser"
	@echo "  resetdb       drop, recreate and seed the local dev database"
	@echo "  run           run the app locally on http://localhost:5000"
	@echo ""
	@echo "  ci            run the full gate: lint + security + tests + coverage"
	@echo "  test          run backend and UI tests"
	@echo "  test-backend  pytest + JUnit XML + coverage (XML & HTML)"
	@echo "  test-ui       Playwright UI tests + JUnit XML"
	@echo "  lint          Ruff static analysis (text + JSON report)"
	@echo "  security      Bandit security scan (text + JSON report)"
	@echo ""
	@echo "  reports       list the generated artifacts in ./$(REPORTS)"
	@echo "  clean         remove caches and generated reports"

# ---------------------------------------------------------------- environment

setup:
	python3 -m venv env
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	$(MAKE) browsers

deps:
	$(PIP) install -r requirements.txt

browsers:
	$(REQUIRE_ENV)
	$(PYTHON) -m playwright install chromium
	-$(PYTHON) -m playwright install-deps chromium

resetdb:
	$(REQUIRE_ENV)
	APPNAME_ENV=dev $(PYTHON) manage.py resetdb

run:
	$(REQUIRE_ENV)
	APPNAME_ENV=dev $(PYTHON) -m flask --app manage run --debug

# ---------------------------------------------------------------------- gates
# Each gate is independent so a failure points at one thing, and each writes a
# machine-readable report next to a human-readable one.

lint:
	@mkdir -p $(REPORTS)
	$(REQUIRE_ENV)
	@echo "==> Ruff"
	@$(PYTHON) -m ruff check . --output-format=json > $(REPORTS)/ruff.json || true
	@$(PYTHON) -m ruff check . --output-format=concise | tee $(REPORTS)/ruff.txt
	@$(PYTHON) -m ruff check . --quiet

security:
	@mkdir -p $(REPORTS)
	$(REQUIRE_ENV)
	@echo "==> Bandit"
	@$(PYTHON) -m bandit -c pyproject.toml -r appname manage.py wsgi.py \
		-f json -o $(REPORTS)/bandit.json || true
	@$(PYTHON) -m bandit -c pyproject.toml -r appname manage.py wsgi.py \
		-f txt -o $(REPORTS)/bandit.txt || true
	@$(PYTHON) -m bandit -c pyproject.toml -r appname manage.py wsgi.py \
		--severity-level medium --quiet
	@echo "    no medium-or-higher findings"

test-backend:
	@mkdir -p $(REPORTS)
	$(REQUIRE_ENV)
	@echo "==> Backend tests (pytest)"
	$(PYTHON) -m pytest tests --ignore=tests/ui \
		--junitxml=$(REPORTS)/junit-backend.xml \
		--cov=appname --cov-report=term-missing \
		--cov-report=xml:$(REPORTS)/coverage.xml \
		--cov-report=html:$(REPORTS)/coverage-html

test-ui:
	@mkdir -p $(REPORTS)
	$(REQUIRE_ENV)
	@echo "==> UI tests (Playwright)"
	$(PYTHON) -m pytest tests/ui \
		--junitxml=$(REPORTS)/junit-ui.xml \
		--browser chromium \
		--screenshot=only-on-failure \
		--video=retain-on-failure \
		--output=$(REPORTS)/ui-artifacts

test: test-backend test-ui

coverage: test-backend
	@echo "==> Coverage HTML: $(REPORTS)/coverage-html/index.html"

# ------------------------------------------------------------------------ ci
# The one command CI and humans both run. Lint and security run first because
# they are fast -- no reason to wait on a browser to learn about a syntax error.

ci:
	@mkdir -p $(REPORTS)
	@echo "=============================================="
	@echo " MyTemplate CI pipeline"
	@echo "=============================================="
	$(MAKE) lint
	$(MAKE) security
	$(MAKE) test-backend
	$(MAKE) test-ui
	@$(MAKE) reports
	@echo ""
	@echo "==> CI passed."

reports:
	@echo ""
	@echo "==> Build artifacts in ./$(REPORTS):"
	@echo "    junit-backend.xml         backend unit test results (JUnit XML)"
	@echo "    junit-ui.xml              Playwright UI test results (JUnit XML)"
	@echo "    coverage.xml              coverage, machine-readable"
	@echo "    coverage-html/index.html  coverage, browsable"
	@echo "    ruff.json / ruff.txt      static analysis"
	@echo "    bandit.json / bandit.txt  security scan"
	@echo "    ui-artifacts/             screenshots + video for failed UI tests"
	@echo ""
	@ls -la $(REPORTS) 2>/dev/null || true

# --------------------------------------------------------------------- chores

clean:
	rm -rf $(REPORTS) .pytest_cache .coverage .ruff_cache
	find . -path ./env -prune -o -name '__pycache__' -print0 | xargs -0 rm -rf
	find . -path ./env -prune -o -name '*.pyc' -print0 | xargs -0 rm -f
