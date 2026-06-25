#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import hmac
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


def sign(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode("utf-8"), hashlib.sha256).digest()


def signing_key(secret_key: str, date_stamp: str, region: str) -> bytes:
    key_date = sign(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    key_region = hmac.new(key_date, region.encode("utf-8"), hashlib.sha256).digest()
    key_service = hmac.new(key_region, b"s3", hashlib.sha256).digest()
    return hmac.new(key_service, b"aws4_request", hashlib.sha256).digest()


def canonical_uri(bucket: str) -> str:
    return "/" + urllib.parse.quote(bucket, safe="")


def bucket_url(endpoint: str, bucket: str) -> str:
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("endpoint RGW invalido")

    base = endpoint.rstrip("/")
    return base + canonical_uri(bucket)


def build_headers(endpoint: str, bucket: str, region: str, access_key: str, secret_key: str) -> dict:
    parsed = urllib.parse.urlparse(endpoint)
    now = dt.datetime.now(dt.UTC)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(b"").hexdigest()

    headers = {
        "host": parsed.netloc,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }

    signed_headers = ";".join(sorted(headers))
    canonical_headers = "".join(f"{key}:{headers[key]}\n" for key in sorted(headers))
    canonical_request = "\n".join([
        "HEAD",
        canonical_uri(bucket),
        "",
        canonical_headers,
        signed_headers,
        payload_hash,
    ])

    credential_scope = f"{date_stamp}/{region}/s3/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])
    signature = hmac.new(
        signing_key(secret_key, date_stamp, region),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    headers["Authorization"] = (
        "AWS4-HMAC-SHA256 "
        f"Credential={access_key}/{credential_scope},"
        f"SignedHeaders={signed_headers},"
        f"Signature={signature}"
    )
    return headers


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Ceph RGW bucket access with a signed HEAD request.")
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args()

    access_key = os.environ.get("CEPH_RGW_ACCESS_KEY_ID")
    secret_key = os.environ.get("CEPH_RGW_SECRET_ACCESS_KEY")
    if not access_key or not secret_key:
        print("credenciais CEPH_RGW_ACCESS_KEY_ID/CEPH_RGW_SECRET_ACCESS_KEY ausentes", file=sys.stderr)
        return 2

    try:
        url = bucket_url(args.endpoint, args.bucket)
        headers = build_headers(args.endpoint, args.bucket, args.region, access_key, secret_key)
        request = urllib.request.Request(url, headers=headers, method="HEAD")
        context = ssl._create_unverified_context() if args.insecure else None
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        print(f"bucket HEAD falhou: HTTP {error.code} {error.reason}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"falha ao acessar endpoint RGW: {error.reason}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"falha ao validar bucket RGW: {error}", file=sys.stderr)
        return 1

    if 200 <= status < 300:
        print(f"bucket {args.bucket} acessivel")
        return 0

    print(f"bucket HEAD retornou status inesperado: HTTP {status}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
