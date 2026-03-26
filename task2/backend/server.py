#!/usr/bin/env python3
"""
Simple HTTP backend server for the SSL offloading proxy.

This lightweight server simulates a backend application that sits behind
the Nginx SSL proxy. It returns simple responses to demonstrate the
proxy functionality and provide measurable throughput.

Listens on port 8080 (plain HTTP — SSL is terminated at Nginx).
"""

import http.server
import json
import time
import os
import socket

PORT = 8080
HOSTNAME = socket.gethostname()


class BackendHandler(http.server.BaseHTTPRequestHandler):
    """Handle HTTP requests from the Nginx proxy."""

    # Suppress default access logging (Nginx handles this)
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        """Handle GET requests."""
        if self.path == "/health":
            # Health check endpoint
            self._send_json(200, {
                "status": "healthy",
                "hostname": HOSTNAME,
                "timestamp": time.time()
            })
        elif self.path == "/status":
            # Detailed status endpoint
            self._send_json(200, {
                "status": "running",
                "hostname": HOSTNAME,
                "pid": os.getpid(),
                "timestamp": time.time(),
                "ssl_offloaded": True,
                "ssl_protocol": self.headers.get("X-SSL-Protocol", "unknown"),
                "ssl_cipher": self.headers.get("X-SSL-Cipher", "unknown"),
                "client_ip": self.headers.get("X-Real-IP", self.client_address[0])
            })
        else:
            # Default response — lightweight for max throughput
            self._send_json(200, {
                "message": "OK",
                "server": HOSTNAME,
                "time": time.time()
            })

    def do_POST(self):
        """Handle POST requests."""
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 0:
            self.rfile.read(content_length)

        self._send_json(200, {
            "message": "received",
            "server": HOSTNAME,
            "time": time.time()
        })

    def _send_json(self, status_code, data):
        """Send a JSON response."""
        response = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)


def main():
    """Start the backend HTTP server."""
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), BackendHandler)
    print(f"Backend server running on port {PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down backend server.")
        server.shutdown()


if __name__ == "__main__":
    main()
