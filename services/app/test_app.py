"""Dev-only checks for the SPA routes in app.py: cd services/app && python -m pytest test_app.py -q"""

import pytest

import app as site


@pytest.fixture
def client(monkeypatch, tmp_path):
    (tmp_path / "index.html").write_text("<div id=root></div>")
    monkeypatch.setattr(site, "dist_dir", tmp_path)
    return site.app.test_client()


@pytest.mark.parametrize("path", ["/", "/games/", "/users/"])
def test_spa_routes_serve_index(client, path):
    resp = client.get(path)
    assert resp.status_code == 200
    assert b"<div id=root>" in resp.data
