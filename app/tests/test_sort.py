import pytest

from app import create_app

ITEMS = {
    1: {"id": 1, "name": "Server", "category": "compute", "quantity": 4, "location": "A"},
    2: {"id": 2, "name": "Optic", "category": "network", "quantity": 30, "location": "B"},
    3: {"id": 3, "name": "Cable", "category": "network", "quantity": 120, "location": "B"},
}


@pytest.fixture
def client():
    app = create_app(items=ITEMS, release={"release": "test"})
    app.config["TESTING"] = True
    return app.test_client()


def test_sort_by_name(client):
    names = [i["name"] for i in client.get("/api/items?sort=name").get_json()["items"]]
    assert names == ["Cable", "Optic", "Server"]


def test_sort_by_quantity(client):
    ids = [i["id"] for i in client.get("/api/items?sort=quantity").get_json()["items"]]
    assert ids == [1, 2, 3]


def test_unknown_sort_field_is_rejected(client):
    resp = client.get("/api/items?sort=__class__")
    assert resp.status_code == 400
    assert "sort must be one of" in resp.get_json()["message"]
