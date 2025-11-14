from flask import Flask, jsonify
import os
import socket
from datetime import datetime

app = Flask(__name__)

SERVICE_NAME = "Day"
VERSION = "1.0.0"

@app.route('/')
def home():
    return jsonify({
        "service": SERVICE_NAME,
        "message": "Welcome to the Day service",
        "version": VERSION
    })

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route('/info')
def info():
    return jsonify({
        "service": SERVICE_NAME,
        "version": VERSION,
        "hostname": socket.gethostname(),
        "environment": os.getenv("ENVIRONMENT", "development"),
        "timestamp": datetime.utcnow().isoformat()
    })

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8001))
    app.run(host='0.0.0.0', port=port, debug=False)
