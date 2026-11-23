import os
import tempfile
import pytest
from app.app import app, init_db

@pytest.fixture
def client():
    # Use temporary database for tests
    db_fd, db_path = tempfile.mkstemp()
    os.environ['URLSHORTENER_DB_PATH'] = db_path
    app.config['TESTING'] = True

    with app.app_context():
        init_db()

    with app.test_client() as client:
        yield client

    os.close(db_fd)
    os.unlink(db_path)

def test_health_check(client):
    """Test Nagios health check endpoint."""
    response = client.get('/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'UP'
    assert data['service'] == 'url-shortener'

def test_home_page_loads(client):
    """Test web UI rendering."""
    response = client.get('/')
    assert response.status_code == 200
    assert b"URL Shortener Microservice" in response.data

def test_api_shorten_and_redirect(client):
    """Test URL shortening API and subsequent redirect."""
    original = "https://github.com/HashiCorp"
    response = client.post('/api/shorten', json={"url": original})
    assert response.status_code == 201
    data = response.get_json()
    assert "short_code" in data
    assert data["original_url"] == original

    # Test redirection
    short_code = data["short_code"]
    redirect_response = client.get(f'/{short_code}')
    assert redirect_response.status_code == 302
    assert redirect_response.headers['Location'] == original

def test_form_shorten(client):
    """Test web form URL submission."""
    response = client.post('/', data={"url": "https://www.terraform.io"})
    assert response.status_code == 200
    assert b"Shortened Link Ready:" in response.data

def test_nonexistent_url_returns_404(client):
    """Test 404 for invalid short code."""
    response = client.get('/invalidCode123')
    assert response.status_code == 404
