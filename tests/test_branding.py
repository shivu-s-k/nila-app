"""Backend tests for the MyTemplate rebrand and the core login -> dashboard flow.

These cover what a customer actually sees: the product name on the pages they
land on, and that logging in still delivers them to a branded dashboard.
"""

import pytest

from appname.extensions import branding

create_user = True

BRAND = "MyTemplate"
OLD_BRAND = "Ignite"

# The Tabler stylesheet is still pulled from the upstream project's CDN path.
# It is a build asset, not user-facing branding, so it is excluded from the
# stale-branding sweep below.
UPSTREAM_ASSET_URL = "sumukh/ignite"


def stripped_body(response):
    return response.get_data(as_text=True).lower().replace(UPSTREAM_ASSET_URL, "")


@pytest.mark.usefixtures("testapp")
class TestBranding:
    def test_branding_service_reports_new_name(self, testapp):
        assert branding.name.startswith(BRAND)
        assert "appname" not in branding.name
        assert branding.icon_path == "public/mytemplate/mytemplate-logo@2x.png"
        assert branding.svg_icon == "public/mytemplate/mytemplate-icon.svg"

    def test_landing_page_is_branded(self, testapp):
        response = testapp.get("/")

        assert response.status_code == 200
        assert "<title>MyTemplate</title>" in response.get_data(as_text=True)

    @pytest.mark.parametrize("path", ["/", "/login", "/signup", "/terms", "/store"])
    def test_public_pages_carry_no_stale_branding(self, testapp, path):
        response = testapp.get(path)

        assert response.status_code == 200
        assert OLD_BRAND.lower() not in stripped_body(response)

    def test_login_page_title_uses_brand(self, testapp):
        assert "MyTemplate Login" in testapp.get("/login").get_data(as_text=True)


@pytest.mark.usefixtures("testapp")
class TestLoginFlow:
    def test_valid_login_reaches_branded_dashboard(self, testapp):
        response = testapp.post(
            "/login",
            data={"email": "user@example.com", "password": "safepassword"},
            follow_redirects=True,
        )

        assert response.status_code == 200
        assert "MyTemplate Home" in response.get_data(as_text=True)
        assert OLD_BRAND.lower() not in stripped_body(response)

    def test_invalid_login_is_rejected(self, testapp):
        response = testapp.post(
            "/login",
            data={"email": "user@example.com", "password": "wrong-password"},
            follow_redirects=True,
        )

        assert response.status_code == 200
        assert "MyTemplate Home" not in response.get_data(as_text=True)
