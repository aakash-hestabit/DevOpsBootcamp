import os
import pwd
from fastapi import FastAPI

app = FastAPI(title="Python Security Hardening Demo")


@app.get("/")
def root():
    return {
        "message": "Hello from a hardened Python container!",
        "env": os.getenv("NODE_ENV", os.getenv("APP_ENV", "production")),
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/whoami")
def whoami():
    uid = os.getuid()
    gid = os.getgid()
    try:
        username = pwd.getpwuid(uid).pw_name
    except KeyError:
        username = "unknown"
    return {
        "uid": uid,
        "gid": gid,
        "username": username,
        "pid": os.getpid(),
        "python_version": __import__("sys").version,
    }


@app.get("/writable-check")
def writable_check():
    """Verify /tmp/runtime-data is writable (only dir allowed in read-only FS)."""
    test_file = "/tmp/runtime-data/test.txt"
    try:
        with open(test_file, "w") as f:
            f.write("ok")
        os.remove(test_file)
        return {"writable": True, "path": "/tmp/runtime-data"}
    except Exception as e:
        return {"writable": False, "error": str(e)}
