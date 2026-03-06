import os
import time
from flask import Flask, jsonify
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)
START = time.time()

DB_CONFIG = {
    'host':             os.getenv('DB_HOST',     'localhost'),
    'port':             int(os.getenv('DB_PORT', '3306')),
    'database':         os.getenv('DB_NAME',     'healthdb'),
    'user':             os.getenv('DB_USER',     'root'),
    'password':         os.getenv('DB_PASSWORD', 'secret'),
    'connect_timeout':  3,
}

def db_ping():
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute('SELECT 1')
    cursor.fetchone()
    cursor.close()
    conn.close()

# Liveness: is the process alive?
@app.get('/health')
def health():
    return jsonify({
        'status':  'ok',
        'service': 'python-app',
        'uptime':  f'{round(time.time() - START, 1)}s',
    }), 200

# Readiness: is the app + database ready to serve traffic?
@app.get('/ready')
def ready():
    try:
        db_ping()
        return jsonify({'status': 'ready', 'db': 'connected'}), 200
    except Error as e:
        return jsonify({'status': 'not_ready', 'db': 'disconnected', 'error': str(e)}), 503

@app.get('/')
def index():
    return jsonify({'service': 'python-app', 'endpoints': ['/health', '/ready']})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5000)))
