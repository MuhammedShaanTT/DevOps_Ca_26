from contextlib import contextmanager
import os
import random
import socket
import sqlite3
import string
from flask import Flask, jsonify, redirect, render_template_string, request

app = Flask(__name__)
DEFAULT_DB_PATH = '/opt/urlshortener/urls.db'


def get_db_path():
    """Return configured SQLite database path dynamically."""
    return os.environ.get('URLSHORTENER_DB_PATH', DEFAULT_DB_PATH)


@contextmanager
def get_db():
    """Open and reliably close a SQLite database connection."""
    db_path = get_db_path()
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    """Create the URLs table if it does not already exist."""
    with get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS urls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                short_code TEXT UNIQUE NOT NULL,
                original_url TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                clicks INTEGER DEFAULT 0
            )
        ''')
        conn.commit()


def generate_short_code(length=6):
    """Generate a random alphanumeric short code."""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=length))


def normalize_url(raw_url):
    """Ensure URL has an explicit http:// or https:// scheme."""
    cleaned = raw_url.strip()
    if cleaned and not (cleaned.startswith('http://') or cleaned.startswith('https://')):
        return 'https://' + cleaned
    return cleaned


def create_short_url(original_url, max_attempts=5):
    """Insert a unique short code for original_url, retrying on rare collision."""
    with get_db() as conn:
        for _ in range(max_attempts):
            code = generate_short_code()
            try:
                conn.execute(
                    'INSERT INTO urls (short_code, original_url) VALUES (?, ?)',
                    (code, original_url),
                )
                conn.commit()
                return code
            except sqlite3.IntegrityError:
                continue
    raise RuntimeError('Failed to allocate unique short code')


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevOps URL Shortener | INT333</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #4f46e5;
            --primary-hover: #4338ca;
            --bg: #f8fafc;
            --card-bg: #ffffff;
            --border: #e2e8f0;
            --text-dark: #0f172a;
            --text-muted: #64748b;
            --success: #16a34a;
        }
        * { box-sizing: border-box; }
        body {
            font-family: 'Inter', -apple-system, sans-serif;
            background: linear-gradient(135deg, #f0f4ff 0%, #e0e7ff 100%);
            min-height: 100vh;
            margin: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1.5rem;
            color: var(--text-dark);
        }
        .container {
            width: 100%;
            max-width: 720px;
            background: var(--card-bg);
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.08), 0 8px 10px -6px rgba(0, 0, 0, 0.04);
            padding: 2.5rem;
        }
        .header {
            text-align: center;
            margin-bottom: 2rem;
        }
        .badge {
            display: inline-block;
            background: #ede9fe;
            color: #6366f1;
            font-size: 0.75rem;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            padding: 0.35rem 0.85rem;
            border-radius: 9999px;
            margin-bottom: 0.75rem;
        }
        h1 {
            font-size: 1.85rem;
            font-weight: 700;
            margin: 0.25rem 0 0.5rem 0;
            color: var(--text-dark);
        }
        .subtitle {
            color: var(--text-muted);
            font-size: 0.95rem;
            margin: 0;
        }
        .form-group {
            display: flex;
            gap: 0.75rem;
            margin-bottom: 2rem;
        }
        input[type="url"] {
            flex: 1;
            padding: 0.85rem 1.15rem;
            border: 2px solid var(--border);
            border-radius: 10px;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s;
        }
        input[type="url"]:focus {
            border-color: var(--primary);
        }
        button {
            background: var(--primary);
            color: white;
            border: none;
            padding: 0.85rem 1.75rem;
            font-weight: 600;
            font-size: 1rem;
            border-radius: 10px;
            cursor: pointer;
            transition: background 0.2s, transform 0.1s;
        }
        button:hover { background: var(--primary-hover); }
        button:active { transform: scale(0.98); }
        .alert-success {
            background: #ecfdf5;
            border: 1px solid #a7f3d0;
            border-radius: 10px;
            padding: 1rem 1.25rem;
            margin-bottom: 2rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .alert-success a {
            color: var(--success);
            font-weight: 600;
            font-size: 1.05rem;
            text-decoration: none;
            word-break: break-all;
        }
        .alert-success a:hover { text-decoration: underline; }
        .table-container {
            border: 1px solid var(--border);
            border-radius: 10px;
            overflow: hidden;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }
        th, td {
            text-align: left;
            padding: 0.85rem 1rem;
            border-bottom: 1px solid var(--border);
        }
        th {
            background: #f8fafc;
            font-weight: 600;
            color: var(--text-muted);
        }
        tr:last-child td { border-bottom: none; }
        .code-link {
            font-family: monospace;
            font-weight: 600;
            color: var(--primary);
            text-decoration: none;
        }
        .clicks-badge {
            background: #f1f5f9;
            color: #475569;
            padding: 0.2rem 0.5rem;
            border-radius: 6px;
            font-weight: 600;
        }
        .footer {
            margin-top: 2rem;
            padding-top: 1.25rem;
            border-top: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 0.8rem;
            color: var(--text-muted);
        }
        .status-dot {
            height: 8px;
            width: 8px;
            background-color: var(--success);
            border-radius: 50%;
            display: inline-block;
            margin-right: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <span class="badge">INT333 DevOps Final Project</span>
            <h1>URL Shortener Microservice</h1>
            <p class="subtitle">Automated via <strong>Terraform</strong> &bull; Managed by <strong>Puppet</strong> &bull; Monitored by <strong>Nagios</strong></p>
        </div>

        {% if short_url %}
        <div class="alert-success">
            <div>
                <div style="font-size: 0.8rem; color: #047857; margin-bottom: 2px;">Shortened Link Ready:</div>
                <a href="{{ short_url }}" target="_blank">{{ short_url }}</a>
            </div>
            <button type="button" data-url="{{ short_url }}" onclick="copyShortUrl(this)" style="padding: 0.4rem 0.75rem; font-size: 0.8rem; background: var(--success);">Copy</button>
        </div>
        {% endif %}

        <form method="POST" action="/" class="form-group">
            <input type="url" name="url" placeholder="https://example.com/my-long-link" required>
            <button type="submit">Shorten</button>
        </form>

        <h3 style="font-size: 1rem; margin: 0 0 0.75rem 0;">Recent Shortened Links</h3>
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>Short Code</th>
                        <th>Original Destination</th>
                        <th>Visits</th>
                    </tr>
                </thead>
                <tbody>
                    {% for item in items %}
                    <tr>
                        <td><a href="/{{ item['short_code'] }}" target="_blank" class="code-link">/{{ item['short_code'] }}</a></td>
                        <td style="max-width: 320px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                            <a href="{{ item['original_url'] }}" target="_blank" style="color: var(--text-muted); text-decoration: none;">{{ item['original_url'] }}</a>
                        </td>
                        <td><span class="clicks-badge">{{ item['clicks'] }}</span></td>
                    </tr>
                    {% else %}
                    <tr>
                        <td colspan="3" style="text-align: center; color: var(--text-muted); padding: 1.5rem;">No shortened links yet. Create one above!</td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>

        <div class="footer">
            <div><span class="status-dot"></span> Node: <code>{{ hostname }}</code></div>
            <div>CI/CD: <strong>GitHub Actions</strong></div>
        </div>
    </div>
    <script>
        function copyShortUrl(btn) {
            var text = btn.getAttribute('data-url');
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(text).then(function() {
                    btn.innerText = 'Copied!';
                });
                return;
            }
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.focus();
            ta.select();
            try {
                document.execCommand('copy');
                btn.innerText = 'Copied!';
            } finally {
                document.body.removeChild(ta);
            }
        }
    </script>
</body>
</html>
"""


@app.route('/health', methods=['GET'])
def health():
    """Nagios Core Health Check endpoint."""
    try:
        with get_db() as conn:
            conn.execute('SELECT 1')
        return jsonify({
            "status": "UP",
            "service": "url-shortener",
            "database": "connected"
        }), 200
    except Exception as e:
        return jsonify({
            "status": "DOWN",
            "error": str(e)
        }), 500


@app.route('/api/shorten', methods=['POST'])
def api_shorten():
    """REST API endpoint for programmatic URL shortening."""
    data = request.get_json(silent=True) or {}
    original_url = normalize_url(data.get('url', ''))
    if not original_url:
        return jsonify({"error": "Missing 'url' parameter"}), 400

    code = create_short_url(original_url)
    return jsonify({
        "short_code": code,
        "short_url": request.host_url + code,
        "original_url": original_url
    }), 201


@app.route('/', methods=['GET', 'POST'])
def home():
    """Render home page UI and process form submissions."""
    short_url = None
    if request.method == 'POST':
        original_url = normalize_url(request.form.get('url', ''))
        if original_url:
            code = create_short_url(original_url)
            short_url = request.host_url + code

    with get_db() as conn:
        cursor = conn.execute(
            'SELECT short_code, original_url, clicks FROM urls ORDER BY id DESC LIMIT 10'
        )
        items = cursor.fetchall()

    hostname = socket.gethostname()
    return render_template_string(HTML_TEMPLATE, short_url=short_url, items=items, hostname=hostname)


@app.route('/<short_code>', methods=['GET'])
def redirect_to_url(short_code):
    """Resolve short code and increment click counter."""
    with get_db() as conn:
        cursor = conn.execute(
            'SELECT original_url, clicks FROM urls WHERE short_code = ?',
            (short_code,),
        )
        row = cursor.fetchone()
        if row:
            conn.execute(
                'UPDATE urls SET clicks = clicks + 1 WHERE short_code = ?',
                (short_code,),
            )
            conn.commit()
            return redirect(row['original_url'])
        return "<h3>404 - Short URL Not Found</h3><p>The requested link does not exist.</p>", 404


if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
