#!/usr/bin/env python3
"""
JioTV+ Companion Dev Proxy (Port 5001)
=====================================
Lightweight Python proxy designed for local Chrome Web development and debugging.
Bypasses browser CORS restrictions and Jio WAF blocks on AES-128 keys (.pkey)
by stripping browser Origin/Referer headers and injecting required DRM credentials.

For Native Android / Android TV deployment, no external script is needed:
the Flutter app runs an embedded Dart proxy (StreamProxyIO) automatically inside the APK.

Usage:
    python companion_proxy.py
"""

import sys
import json
import re
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
import datetime

PORT = 5001
EXO_UA = "plaYtv/7.1.8 (Linux;Android 8.1.0) ExoPlayerLib/2.11.7"
APP_KEY = "NzNiMDhlYzQyNjJm"
USER_GROUP = "tvYR7NSNn7rymo3F"
VERSION_CODE = "422"

hdnea_cache = {}

class ProxyHandler(BaseHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        path = u.path
        q = urllib.parse.parse_qs(u.query)

        if path == "/health" or path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"JioTV Dev Companion Proxy is RUNNING\n")
            return

        if path.startswith("/live/") and path.endswith(".m3u8"):
            channel_id = path[len("/live/"):len(path) - len(".m3u8")]
            self.handle_live_channel(channel_id)
            return

        if path == "/render.m3u8" or path == "/variant.m3u8":
            target_url = q.get("url", [""])[0]
            channel_id = q.get("channel_id", [""])[0]
            hdnea = q.get("hdnea", [""])[0]
            self.handle_variant_playlist(target_url, channel_id, hdnea)
            return

        if path == "/render.key" or path == "/key":
            target_url = q.get("url", [""])[0]
            channel_id = q.get("channel_id", [""])[0]
            hdnea = q.get("hdnea", [""])[0]
            self.handle_key_request(target_url, channel_id, hdnea)
            return

        if path == "/render.ts" or path == "/ts":
            target_url = q.get("url", [""])[0]
            hdnea = q.get("hdnea", [""])[0]
            self.handle_segment_request(target_url, hdnea)
            return

        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"Not Found")

    def handle_variant_playlist(self, target_url, channel_id, hdnea):
        if not target_url:
            self.send_response(400)
            self.end_headers()
            return

        if not hdnea:
            hdnea = hdnea_cache.get(channel_id, "")

        req = urllib.request.Request(target_url, headers={
            "User-Agent": EXO_UA,
            "Accept": "*/*",
            "Cookie": f"__hdnea__={hdnea}" if hdnea else ""
        })

        try:
            with urllib.request.urlopen(req) as resp:
                content = resp.read().decode("utf-8", errors="ignore")
                lines = content.splitlines()
                rewritten = []
                key_pattern = re.compile(r'#EXT-X-KEY:METHOD=([^,]+),URI="([^"]+)"(.*)')

                for line in lines:
                    line_s = line.strip()
                    if not line_s:
                        rewritten.append(line)
                        continue

                    km = key_pattern.match(line_s)
                    if km:
                        method = km.group(1)
                        raw_key = km.group(2)
                        rest = km.group(3)
                        resolved_key = urllib.parse.urljoin(target_url, raw_key)
                        proxy_key = f"http://127.0.0.1:{PORT}/key?channel_id={channel_id}&hdnea={urllib.parse.quote(hdnea)}&url={urllib.parse.quote(resolved_key)}"
                        rewritten.append(f'#EXT-X-KEY:METHOD={method},URI="{proxy_key}"{rest}')
                        continue

                    if line_s.startswith("#"):
                        rewritten.append(line)
                        continue

                    # Segment line
                    resolved_seg = urllib.parse.urljoin(target_url, line_s)
                    proxy_seg = f"http://127.0.0.1:{PORT}/ts?channel_id={channel_id}&hdnea={urllib.parse.quote(hdnea)}&url={urllib.parse.quote(resolved_seg)}"
                    rewritten.append(proxy_seg)

                out_bytes = "\n".join(rewritten).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.apple.mpegurl")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(out_bytes)
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"Proxy error: {e}".encode("utf-8"))

    def handle_key_request(self, target_url, channel_id, hdnea):
        if not target_url:
            self.send_response(400)
            self.end_headers()
            return

        headers = {
            "User-Agent": EXO_UA,
            "appkey": APP_KEY,
            "channelId": channel_id,
            "deviceId": "d04b868e404b88df",
            "devicetype": "phone",
            "os": "android",
            "usergroup": USER_GROUP,
            "versionCode": VERSION_CODE,
            "srno": "230203144000",
        }
        if hdnea:
            headers["Cookie"] = f"__hdnea__={hdnea}"

        # Explicitly NO Origin or Referer header sent to tv.media.jio.com!
        req = urllib.request.Request(target_url, headers=headers)
        try:
            with urllib.request.urlopen(req) as resp:
                key_bytes = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(key_bytes)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as ex:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(ex).encode("utf-8"))

    def handle_segment_request(self, target_url, hdnea):
        if not target_url:
            self.send_response(400)
            self.end_headers()
            return

        headers = {
            "User-Agent": EXO_UA,
            "Accept": "*/*",
        }
        if hdnea:
            headers["Cookie"] = f"__hdnea__={hdnea}"

        range_val = self.headers.get("Range")
        if range_val:
            headers["Range"] = range_val

        req = urllib.request.Request(target_url, headers=headers)
        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for h, v in resp.headers.items():
                    if h.lower() not in ["access-control-allow-origin", "set-cookie"]:
                        self.send_header(h, v)
                self.end_headers()
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as ex:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(ex).encode("utf-8"))

def main():
    server = HTTPServer(("127.0.0.1", PORT), ProxyHandler)
    print("=" * 60)
    print(f"JioTV+ Dev Companion Proxy started on http://127.0.0.1:{PORT}")
    print("Ready to proxy AES-128 keys and Akamai streams for Web development!")
    print("Press Ctrl+C to stop.")
    print("=" * 60)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Dev Companion Proxy...")
        server.server_close()

if __name__ == "__main__":
    main()
