"""Playwright UI tests for the MyTemplate sign-up and login flows.

These walk the paths a real customer takes -- landing page to a working
dashboard -- and check the MyTemplate branding is what they see along the way.
"""

import re
import uuid

from playwright.sync_api import Page, expect

from tests.ui.conftest import UI_USER_EMAIL, UI_USER_PASSWORD

OLD_BRAND = "Ignite"


def test_visitor_can_sign_up_from_the_landing_page(page: Page, live_server):
    """Landing page -> Demo CTA -> signup -> branded dashboard."""
    page.goto(live_server, wait_until="domcontentloaded")
    expect(page).to_have_title("MyTemplate")
    expect(page.locator(".hero-description")).to_contain_text("MyTemplate")

    # The landing page's only call to action is the "Demo" button.
    page.get_by_role("link", name="Demo").first.click()
    page.wait_for_url(re.compile(r"/signup"))
    expect(page).to_have_title(re.compile(r"^MyTemplate Signup"))

    new_email = f"visitor-{uuid.uuid4().hex[:10]}@example.com"
    password = "a-good-password"
    page.fill("input[name='email']", new_email)
    page.fill("input[name='password']", password)
    page.fill("input[name='confirm']", password)
    page.get_by_role("button", name=re.compile("sign ?up", re.I)).click()

    page.wait_for_url(re.compile(r"/dashboard"))
    expect(page).to_have_title(re.compile(r"^MyTemplate Home"))
    expect(page.locator("h1.page-title")).to_contain_text("Dashboard")
    assert OLD_BRAND not in page.locator("body").inner_text()


def test_existing_user_can_log_in(page: Page, live_server):
    """Login page -> valid credentials -> branded dashboard."""
    page.goto(f"{live_server}/login", wait_until="domcontentloaded")
    expect(page).to_have_title(re.compile(r"^MyTemplate Login"))
    expect(page.get_by_text("Login to your account")).to_be_visible()

    page.fill("input[name='email']", UI_USER_EMAIL)
    page.fill("input[name='password']", UI_USER_PASSWORD)
    page.get_by_role("button", name="Login").click()

    page.wait_for_url(re.compile(r"/dashboard"))
    expect(page).to_have_title(re.compile(r"^MyTemplate Home"))
    assert OLD_BRAND not in page.locator("body").inner_text()


def test_bad_password_keeps_the_user_on_the_login_page(page: Page, live_server):
    page.goto(f"{live_server}/login", wait_until="domcontentloaded")

    page.fill("input[name='email']", UI_USER_EMAIL)
    page.fill("input[name='password']", "definitely-not-the-password")
    page.get_by_role("button", name="Login").click()

    expect(page).to_have_url(re.compile(r"/login"))
    expect(page.get_by_text("Login to your account")).to_be_visible()
