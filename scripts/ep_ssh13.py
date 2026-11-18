#!/usr/bin/env python3
"""Tiny ssh/scp helper for the test router 10.10.10.13."""
import sys, os
import paramiko

HOST = "10.10.10.13"
USER = "root"
PWD = "root"


def client():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=22, username=USER, password=PWD, timeout=15,
              allow_agent=False, look_for_keys=False)
    return c


def run(cmd, timeout=120):
    c = client()
    tr = c.exec_command(cmd, timeout=timeout)
    out = tr[0].read().decode("utf-8", "replace")
    err = tr[1].read().decode("utf-8", "replace")
    code = tr[1].channel.recv_exit_status()
    c.close()
    return out, err, code


def put(local, remote):
    c = client()
    sftp = c.open_sftp()
    sftp.put(local, remote)
    sftp.close()
    c.close()


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "put":
        put(sys.argv[2], sys.argv[3])
        print("put", sys.argv[2], "->", sys.argv[3])
    else:
        out, err, code = run(sys.argv[2])
        sys.stdout.write(out)
        sys.stderr.write(err)
        sys.exit(code)
