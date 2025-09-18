import os
import io
import json
import time
import tempfile
from typing import Dict, Any, List, Optional
import stat

import boto3

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")

# ---------- helpers ----------

def _env(name: str) -> str:
    v = os.getenv(name)
    if not v:
        raise RuntimeError(f"Missing env var: {name}")
    return v

def _load_config() -> Dict[str, Any]:
    bucket = os.getenv("config_bucket") or os.getenv("CONFIG_BUCKET")
    key    = os.getenv("config_file")   or os.getenv("CONFIG_FILE")
    if not bucket or not key:
        raise RuntimeError("Missing config_bucket/config_file env vars.")
    obj = s3.get_object(Bucket=bucket, Key=key)
    body = obj["Body"].read().decode("utf-8")
    return json.loads(body)

def _get_secret_json(secret_id: str) -> Dict[str, Any]:
    resp = secrets.get_secret_value(SecretId=secret_id)
    raw = resp.get("SecretString") or ""
    try:
        return json.loads(raw)
    except Exception:
        if ":" in raw:
            u, p = raw.split(":", 1)
            return {"username": u, "password": p}
        return {"value": raw}

def _object_exists(bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except Exception:
        return False

def _suffix_key(key: str) -> str:
    base, ext = os.path.splitext(key)
    ts = time.strftime("%Y%m%d-%H%M%S")
    return f"{base}__{ts}{ext}"

class FtpClientBase:
    def list_files(self, directory: str) -> List[str]: ...
    def download_to_path(self, remote_path: str, local_path: str) -> None: ...
    def rename(self, src: str, dst: str) -> None: ...
    def delete(self, remote_path: str) -> None: ...
    def ensure_dir(self, directory: str) -> None: ...
    def close(self) -> None: ...

class SFTP(FtpClientBase):
    def __init__(self, host: str, port: int, username: str, password: Optional[str], pkey: Optional[str]):
        try:
            import paramiko
        except ImportError:
            raise RuntimeError("SFTP requires Paramiko. Attach the Paramiko layer (e.g., paramiko-py312).")
        self._pmk = paramiko
        self._t = paramiko.Transport((host, port))
        if pkey:
            key = paramiko.RSAKey.from_private_key(io.StringIO(pkey))
            self._t.connect(username=username, pkey=key)
        else:
            self._t.connect(username=username, password=password)
        self._sftp = paramiko.SFTPClient.from_transport(self._t)

    def list_files(self, directory: str) -> List[str]:
        files = []
        try:
            for a in self._sftp.listdir_attr(directory):
                if stat.S_ISREG(a.st_mode):
                    files.append(f"{directory.rstrip('/')}/{a.filename}")
        except IOError:
            pass
        return files

    def download_to_path(self, remote_path: str, local_path: str) -> None:
        self._sftp.get(remote_path, local_path)

    def rename(self, src: str, dst: str) -> None:
        parent = "/".join(dst.split("/")[:-1])
        self.ensure_dir(parent)
        self._sftp.rename(src, dst)

    def delete(self, remote_path: str) -> None:
        self._sftp.remove(remote_path)

    def ensure_dir(self, directory: str) -> None:
        if not directory or directory == "/":
            return
        parts, cur = [p for p in directory.split("/") if p], ""
        for p in parts:
            cur = f"{cur}/{p}" if cur else f"/{p}"
            try:
                self._sftp.mkdir(cur)
            except IOError:
                pass

    def close(self) -> None:
        try: self._sftp.close()
        except Exception: pass
        try: self._t.close()
        except Exception: pass

def _connect(cfg: Dict[str, Any]) -> FtpClientBase:
    c = cfg["connection"]
    secret_name = c["secrets_manager_secret_name"]
    sec = _get_secret_json(secret_name)

    host = sec.get("host")
    port = int(sec.get("port") or 22)
    username = sec.get("username") or sec.get("user")
    password = sec.get("password") or sec.get("pass")
    pkey     = sec.get("private_key")

    if not host or not username or (not password and not pkey):
        raise RuntimeError("SFTP secret must include 'host', 'username' and either 'password' or 'private_key'.")

    return SFTP(host, port, username, password, pkey)

# ---------- core ----------

def lambda_handler(event, context):
    cfg = _load_config()
    conn = cfg["connection"]
    remote_root = conn.get("remote_path", "/")

    defaults = cfg.get("defaults", {})
    def_ext  = (defaults.get("extension", ".csv") or ".csv").lower()
    def_del  = bool(defaults.get("delete_after_transfer", False))
    def_over = bool(defaults.get("overwrite_existing", False))

    client = _connect(cfg)

    processed, skipped, failed = [], [], []
    try:
        files = client.list_files(remote_root)
        for remote_path in files:
            fname = remote_path.split("/")[-1]
            matched = False
            for rule in cfg.get("transfer_rules", []):
                pat = rule["file_pattern"]
                ext = (rule.get("extension") or def_ext).lower()
                if not fname.lower().endswith(ext):
                    continue
                if not fname.startswith(pat):
                    continue

                bucket = rule["target"]["bucket"]
                prefix = rule["target"].get("prefix") or ""
                if prefix and not prefix.endswith("/"):
                    prefix += "/"
                key = prefix + fname

                #overwrite = bool(rule.get("overwrite_existing", def_over))
                #if not overwrite and _object_exists(bucket, key):
                #    key = _suffix_key(key)

                try:
                    with tempfile.TemporaryDirectory() as td:
                        lp = os.path.join(td, fname)
                        client.download_to_path(remote_path, lp)
                        s3.upload_file(lp, bucket, key)
                    if bool(rule.get("delete_after_transfer", def_del)):
                        client.delete(remote_path)
                    processed.append({"file": remote_path, "s3": f"s3://{bucket}/{key}", "rule": rule["name"]})
                    matched = True
                    break
                except Exception as e:
                    failed.append({"file": remote_path, "error": str(e), "rule": rule["name"]})
                    matched = True
                    break
            if not matched:
                skipped.append({"file": remote_path, "reason": "no_matching_rule"})
    finally:
        client.close()

    return {
        "summary": {"processed": len(processed), "skipped": len(skipped), "failed": len(failed)},
        "processed": processed,
        "skipped": skipped,
        "failed": failed
    }
