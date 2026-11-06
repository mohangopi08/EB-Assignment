import os
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler
import json


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self._respond(200, {"status": "ok"})
        elif self.path == "/":
            self._respond(200, {
                "app": os.environ.get("APP_NAME", "unknown"),
                "version": os.environ.get("VERSION", "unknown"),
                "pod": socket.gethostname(),
            })
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    # Suppress per-request log lines
    def log_message(self, format, *args):
        return


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Listening on :{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
