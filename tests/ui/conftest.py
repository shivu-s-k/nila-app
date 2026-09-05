"""Fixtures for the Playwright UI tests.

Runs the real MyTemplate WSGI app on a background thread so Playwright drives
the same stack a customer would hit, then tears it down after the session.
"""

import os
import socket
import threading

import pytest
from werkzeug.serving import make_server

# ProdConfig reads DATABASE_URL at import time; keep imports safe.
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from appname import create_app  # noqa: E402
from appname.models import db  # noqa: E402
from appname.models.user import User  # noqa: E402

UI_USER_EMAIL = "ui-user@example.com"
UI_USER_PASSWORD = "ui-safe-password"


def _free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@pytest.fixture(scope="session")
def live_server():
    """Start the app on a real port and seed a user to log in with."""
    app = create_app("appname.settings.UiTestConfig")
    app.config["SERVER_NAME"] = None

    with app.app_context():
        db.create_all()
        if User.lookup(UI_USER_EMAIL) is None:
            db.session.add(User(UI_USER_EMAIL, UI_USER_PASSWORD))
            db.session.commit()

    port = _free_port()
    server = make_server("127.0.0.1", port, app, threaded=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    yield f"http://127.0.0.1:{port}"

    server.shutdown()
    thread.join(timeout=5)

    with app.app_context():
        db.session.remove()
        db.drop_all()


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args):
    return {**browser_context_args, "viewport": {"width": 1280, "height": 900}}
