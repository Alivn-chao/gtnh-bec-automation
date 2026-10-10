"""Receive bounded BEC diagnostic snapshots; never execute uploaded content."""
import argparse
import hashlib
import json
import re
import secrets
import threading
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

MAX_FILE = 512 * 1024
MAX_SESSION = 64 * 1024 * 1024
MAX_FILES = 300
MAX_SESSIONS = 100


def allowed_name(name):
    return bool(re.fullmatch(
        r"(?:home/bec_[A-Za-z0-9_.-]+|home/bec/recipes/[A-Za-z0-9_.-]+\.dat|runtime\.txt|upload_report\.txt)",
        name) and ".." not in name)


def save_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


class Receiver(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, root, token, uploader, public_url_file):
        super().__init__(address, Handler)
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.token = token
        self.uploader = Path(uploader)
        self.public_url_file = Path(public_url_file)
        self.lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, fmt, *args):
        # Do not write the capability token from the request path into logs.
        print(datetime.now(timezone.utc).isoformat(), self.command, args[1] if len(args) > 1 else "", flush=True)

    def reply(self, code, text, content_type="text/plain; charset=utf-8"):
        data = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def route(self):
        parts = urlsplit(self.path)
        segments = parts.path.strip("/").split("/")
        if not segments or not secrets.compare_digest(segments[0], self.server.token):
            return None, parts
        return segments[1:], parts

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, "BEC diagnostic receiver ready\n")
        if self.path == "/process-reset/patch.lua":
            try:
                path = Path(__file__).resolve().parent.parent / "fixes" / "process_reset" / "patch_v1.lua"
                return self.reply(200, path.read_text(encoding="utf-8"))
            except OSError:
                return self.reply(503, "V1 reset patch is unavailable\n")
        if self.path == "/nanites-io/test.lua":
            # One fixed public test script, never a caller-selected file.
            try:
                path = Path(__file__).resolve().parent.parent / "fixes" / "nanites_io" / "bec_nanites_io_test.lua"
                return self.reply(200, path.read_text(encoding="utf-8"))
            except OSError:
                return self.reply(503, "Nanite IO test is unavailable\n")
        if self.path in ("/nanites-io/install.lua", "/nanites-io/bec_nanites.lua"):
            try:
                folder = Path(__file__).resolve().parent.parent / "fixes" / "nanites_io"
                module = (folder / "bec_nanites.lua").read_text(encoding="utf-8")
                if hashlib.sha256(module.encode()).hexdigest() != "ad53c28bb3a4bd6b6eff7a784c9a7d0950d67e6b11d56ddf4168ef9c200eb942":
                    raise ValueError("Module checksum changed")
                if self.path == "/nanites-io/bec_nanites.lua":
                    return self.reply(200, module)
                public_url = self.server.public_url_file.read_text(encoding="utf-8").strip()
                if not re.fullmatch(r"https?://[A-Za-z0-9.:-]+", public_url):
                    raise ValueError("Invalid endpoint")
                script = (folder / "install.lua").read_text(encoding="utf-8")
                github_url = "https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_io/bec_nanites.lua"
                if script.count(github_url) != 1:
                    raise ValueError("Installer changed")
                return self.reply(200, script.replace(github_url, public_url + "/nanites-io/bec_nanites.lua", 1))
            except (OSError, ValueError):
                return self.reply(503, "Nanite IO module is unavailable\n")
        # Only these two public repository scripts are mirrored. No uploaded
        # snapshot, arbitrary local file, or remote command is exposed here.
        if self.path in ("/sidefix/install.lua", "/sidefix/bec_nanites.lua"):
            try:
                folder = Path(__file__).resolve().parent.parent / "fixes" / "nanites_topup"
                module = (folder / "bec_nanites.lua").read_text(encoding="utf-8")
                if hashlib.sha256(module.encode("utf-8")).hexdigest() != "55686269c941015d2c39f394d20ff57fb5a78dca265ff5f015f381ffb389abec":
                    raise ValueError("Pinned module changed")
                if self.path == "/sidefix/bec_nanites.lua":
                    return self.reply(200, module)
                public_url = self.server.public_url_file.read_text(encoding="utf-8").strip()
                if not re.fullmatch(r"https?://[A-Za-z0-9.:-]+", public_url):
                    raise ValueError("Invalid endpoint")
                script = (folder / "install_sidefix.lua").read_text(encoding="utf-8")
                pinned = "https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/a2c8c9a/fixes/nanites_topup/bec_nanites.lua"
                if script.count(pinned) != 1:
                    raise ValueError("Installer source changed")
                return self.reply(200, script.replace(pinned, public_url + "/sidefix/bec_nanites.lua", 1))
            except (OSError, ValueError):
                return self.reply(503, "Side fix is unavailable\n")
        route, _ = self.route()
        if route != ["bootstrap.lua"]:
            return self.reply(404, "Not found\n")
        try:
            public_url = self.server.public_url_file.read_text(encoding="utf-8").strip()
            if not re.fullmatch(r"https?://[A-Za-z0-9.:-]+", public_url):
                raise ValueError("Invalid endpoint")
            script = self.server.uploader.read_text(encoding="utf-8")
            script = script.replace('"__BEC_ENDPOINT__"', json.dumps(public_url + "/" + self.server.token), 1)
        except (OSError, ValueError):
            return self.reply(503, "Endpoint is being prepared\n")
        self.reply(200, script)

    def do_POST(self):
        route, parts = self.route()
        if route is None:
            return self.reply(404, "Not found\n")
        if self.headers.get("Transfer-Encoding"):
            return self.reply(400, "Content-Length required\n")
        try:
            size = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            size = -1
        if size < 0 or size > MAX_FILE:
            return self.reply(413, "File exceeds limit\n")
        body = self.rfile.read(size)
        if len(body) != size:
            return self.reply(400, "Incomplete body\n")
        with self.server.lock:
            if route == ["start"]:
                if len(list(self.server.root.iterdir())) >= MAX_SESSIONS:
                    return self.reply(429, "Receiver session quota reached\n")
                session = uuid.uuid4().hex
                folder = self.server.root / session
                folder.mkdir()
                save_json(folder / "manifest.json", {
                    "session": session, "started": datetime.now(timezone.utc).isoformat(),
                    "computer": body[:256].decode("utf-8", errors="replace"), "files": {},
                    "bytes": 0, "complete": False,
                })
                return self.reply(201, "SESSION " + session + "\n")
            if not route or len(route) != 2 or route[0] not in ("upload", "finish") or not re.fullmatch(r"[0-9a-f]{32}", route[1]):
                return self.reply(404, "Not found\n")
            folder = self.server.root / route[1]
            manifest_path = folder / "manifest.json"
            if not manifest_path.is_file() or folder.is_symlink():
                return self.reply(404, "Unknown session\n")
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if route[0] == "finish":
                manifest["complete"] = True
                manifest["finished"] = datetime.now(timezone.utc).isoformat()
                save_json(manifest_path, manifest)
                save_json(self.server.root / "latest.json", {"session": route[1]})
                return self.reply(200, "OK " + route[1] + " " + str(len(manifest["files"])) + " files\n")
            names = parse_qs(parts.query).get("name", [])
            if len(names) != 1 or not allowed_name(names[0]):
                return self.reply(400, "Invalid file name\n")
            name = names[0]
            digest = hashlib.sha256(body).hexdigest()
            existing = manifest["files"].get(name)
            if existing:
                if existing["sha256"] == digest:
                    return self.reply(200, "OK already received\n")
                return self.reply(409, "File already received with different content\n")
            if manifest["complete"]:
                return self.reply(409, "Session finished\n")
            if len(manifest["files"]) >= MAX_FILES or manifest["bytes"] + size > MAX_SESSION:
                return self.reply(413, "Snapshot exceeds limit\n")
            target = folder / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if any(p.is_symlink() for p in [target, *target.parents]) or not target.resolve().is_relative_to(folder.resolve()):
                return self.reply(400, "Invalid destination\n")
            with target.open("xb") as stream:
                stream.write(body)
                stream.flush()
            manifest["files"][name] = {"bytes": size, "sha256": digest}
            manifest["bytes"] += size
            save_json(manifest_path, manifest)
            self.reply(200, "OK " + digest + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Private JSON config outside the repository")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8-sig"))
    token = config["token"]
    if not re.fullmatch(r"[0-9a-f]{48,128}", token):
        parser.error("token must contain at least 24 random bytes in hex")
    server = Receiver(("127.0.0.1", config.get("port", 8765)), config["data_dir"], token,
                      Path(__file__).with_name("upload.lua"), config["public_url_file"])
    print("BEC diagnostic receiver listening on loopback", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
