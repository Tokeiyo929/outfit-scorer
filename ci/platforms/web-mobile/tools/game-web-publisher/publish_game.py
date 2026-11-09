#!/usr/bin/env python3
"""Publish a Cocos or Unity Web ZIP from disk or LAN Share."""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
import ssl
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath


DEFAULT_PORTAL = "https://fz5j.asia"
DEFAULT_LAN_SHARE = "http://192.168.1.148:8811"
SCRIPT_UPLOAD_PASSWORD = "Es-HvkpNev62_O4lPaRC9J-FBPw"


class ClientError(RuntimeError):
    pass


def encoded_path(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def validate_lan_path(value: str) -> str:
    if not value or "\\" in value or value.startswith(("/", "~")):
        raise ClientError("LAN Share 路径必须是相对路径")
    path = PurePosixPath(value)
    if any(part in {"", ".", ".."} for part in path.parts):
        raise ClientError("LAN Share 路径无效或包含 ..")
    return str(path)


def get_json(url: str) -> object:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as exc:
        raise ClientError(f"请求失败：{url}: {exc}") from exc


def download_lan_share(base_url: str, relative_path: str, destination: Path) -> None:
    base = base_url.rstrip("/")
    info = get_json(f"{base}/api/info")
    if not isinstance(info, dict) or "free_bytes" not in info:
        raise ClientError("LAN Share /api/info 返回格式异常")

    path = PurePosixPath(relative_path)
    parent = "" if str(path.parent) == "." else str(path.parent)
    listing_url = f"{base}/api/files"
    if parent:
        listing_url += f"?path={encoded_path(parent)}"
    listing = get_json(listing_url)
    if not isinstance(listing, list):
        raise ClientError("LAN Share 文件列表格式异常")
    entry = next(
        (
            item
            for item in listing
            if isinstance(item, dict)
            and item.get("type") == "file"
            and item.get("path") == relative_path
        ),
        None,
    )
    if entry is None:
        raise ClientError(f"LAN Share 中未找到文件：{relative_path}")

    url = f"{base}/api/download?path={encoded_path(relative_path)}"
    try:
        with urllib.request.urlopen(url, timeout=60) as response, destination.open("xb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
    except (urllib.error.URLError, OSError) as exc:
        destination.unlink(missing_ok=True)
        raise ClientError(f"LAN Share 下载失败：{exc}") from exc

    expected_size = entry.get("size")
    if isinstance(expected_size, int) and destination.stat().st_size != expected_size:
        destination.unlink(missing_ok=True)
        raise ClientError("LAN Share 下载后的字节数与文件列表不一致")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def publish(
    portal: str,
    archive: Path,
    slug: str,
    title: str,
    username: str,
    password: str,
    allow_http: bool,
) -> dict[str, object]:
    parsed = urllib.parse.urlsplit(portal.rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ClientError("portal 必须是有效的 HTTP(S) 地址")
    if parsed.scheme != "https" and not allow_http and parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise ClientError("拒绝通过明文 HTTP 发送上传凭据；如为受控测试环境请显式使用 --allow-http")

    query = urllib.parse.urlencode({"slug": slug, "title": title})
    base_path = parsed.path.rstrip("/")
    target = f"{base_path}/game-upload-api/publish?{query}"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    connection_cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    kwargs = {"timeout": 30 * 60}
    if parsed.scheme == "https":
        kwargs["context"] = ssl.create_default_context()
    connection = connection_cls(parsed.hostname, port, **kwargs)

    file_size = archive.stat().st_size
    authorization = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    connection.putrequest("POST", target, skip_accept_encoding=True)
    connection.putheader("Authorization", f"Basic {authorization}")
    connection.putheader("Accept", "application/json")
    connection.putheader("Content-Type", "application/zip")
    connection.putheader("Content-Length", str(file_size))
    connection.putheader("Origin", f"{parsed.scheme}://{parsed.netloc}")
    connection.putheader("User-Agent", "game-web-publisher-skill/1.0")
    connection.endheaders()

    sent = 0
    last_percent = -1
    with archive.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            connection.send(chunk)
            sent += len(chunk)
            percent = int(sent * 100 / max(file_size, 1))
            if percent >= last_percent + 5 or percent == 100:
                print(f"上传 {percent:3d}% ({sent}/{file_size} bytes)", file=sys.stderr)
                last_percent = percent

    response = connection.getresponse()
    body = response.read()
    connection.close()
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ClientError(f"发布服务返回非 JSON 响应（HTTP {response.status}）") from exc
    if response.status < 200 or response.status >= 300 or not payload.get("ok"):
        message = payload.get("error") if isinstance(payload, dict) else None
        raise ClientError(f"发布失败（HTTP {response.status}）：{message or '未知错误'}")
    return payload


def verify_public_url(url: str) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "game-web-publisher-skill/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            prefix = response.read(1024).lower()
            content_type = response.headers.get_content_type()
            if response.status != 200 or content_type != "text/html" or b"<html" not in prefix:
                raise ClientError(
                    f"公开链接验证失败：HTTP {response.status}, Content-Type {content_type}"
                )
    except urllib.error.URLError as exc:
        raise ClientError(f"公开链接不可访问：{exc}") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", type=Path, help="本地 ZIP 文件")
    source.add_argument("--lan-path", help="LAN Share 中的相对 ZIP 路径")
    parser.add_argument("--slug", required=True, help="公开链接使用的游戏 slug")
    parser.add_argument("--title", default="", help="发布记录中的显示名称")
    parser.add_argument("--portal", default=os.environ.get("GAME_UPLOAD_PORTAL", DEFAULT_PORTAL))
    parser.add_argument("--username", default=os.environ.get("GAME_UPLOAD_USERNAME", "publisher"))
    parser.add_argument("--lan-share", default=os.environ.get("LAN_SHARE_URL", DEFAULT_LAN_SHARE))
    parser.add_argument("--allow-http", action="store_true")
    parser.add_argument("--json", action="store_true", help="仅输出 JSON 结果")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    temp_path: Path | None = None
    try:
        if args.file:
            archive = args.file.resolve()
            if not archive.is_file():
                raise ClientError(f"文件不存在：{archive}")
        else:
            relative_path = validate_lan_path(args.lan_path)
            descriptor, name = tempfile.mkstemp(prefix="lan-game-", suffix=".zip")
            os.close(descriptor)
            Path(name).unlink()
            temp_path = Path(name)
            print(f"从 LAN Share 下载 {relative_path}", file=sys.stderr)
            download_lan_share(args.lan_share, relative_path, temp_path)
            archive = temp_path

        if archive.suffix.casefold() != ".zip":
            raise ClientError("只支持 .zip 文件")
        local_hash = sha256_file(archive)
        password = SCRIPT_UPLOAD_PASSWORD
        if not password:
            raise ClientError("上传密码不能为空，请在 publish_game.py 的 SCRIPT_UPLOAD_PASSWORD 常量中配置")

        result = publish(
            portal=args.portal,
            archive=archive,
            slug=args.slug,
            title=args.title,
            username=args.username,
            password=password,
            allow_http=args.allow_http,
        )
        if result.get("sha256") != local_hash:
            raise ClientError("服务器返回的 SHA-256 与本地文件不一致")
        verify_public_url(str(result["url"]))
        result["verified"] = True
        if args.json:
            print(json.dumps(result, ensure_ascii=False))
        else:
            print(f"发布成功：{result['url']}")
            print(f"引擎：{result.get('engine')}")
            print(f"版本：{result.get('release')}")
            print(f"SHA-256：{result.get('sha256')}")
            print("公开链接验证：通过")
    except ClientError as exc:
        raise SystemExit(f"错误：{exc}") from exc
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
