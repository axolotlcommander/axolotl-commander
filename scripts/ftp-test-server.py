#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The iCommander Authors
"""Minimal FTP server for iCommander tests and manual GUI testing (stdlib only).

    /usr/bin/python3 -I scripts/ftp-test-server.py --root DIR --user U --password P \
        [--port 0] [--no-mlsd] [--anonymous] [--wire-encoding cp1250] \
        [--tls-cert FILE --tls-key FILE [--implicit-tls]]

--password-hex HEX gives the password as hex of its UTF-8 bytes instead (exact bytes;
Foundation's Process may NFD-normalize non-ASCII arguments).

Listens on 127.0.0.1 only and prints the chosen port as the first line of stdout.
The login directory is ROOT, shown as "/". Every path must resolve (symlinks included)
inside ROOT, otherwise the command fails with 550. Names are UTF-8 on the wire, or with
--wire-encoding (a Python codec such as cp1250, iso8859_2, cp852) the server plays a legacy
server: names on disk stay UTF-8, but listings, replies and command arguments use that
encoding (USER and PASS stay UTF-8, FEAT no longer offers UTF8).
Plain FTP by default. With --tls-cert and --tls-key it also speaks FTPS: explicit (AUTH TLS,
PBSZ 0, PROT P/PROT C; PROT P wraps PASV/EPSV/PORT data connections in TLS) and, with
--implicit-tls, implicit (the control connection is TLS from the first byte and data
connections default to protection P; use --port 990 for the conventional port).
Serves threaded sessions until killed.
"""

import argparse
import codecs
import os
import posixpath
import socket
import socketserver
import ssl
import stat
import sys
import threading
import time
import unicodedata

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


class Config:
    root = ""
    user = ""
    password = ""
    mlsd = True
    anonymous = False
    tls = None  # ssl.SSLContext (server side) or None
    implicit_tls = False
    wire = "utf-8"  # encoding of names on the control and listing connections


def to_wire(text):
    if Config.wire != "utf-8":
        text = unicodedata.normalize("NFC", text)  # code pages have no combining accents
    return text.encode(Config.wire, "surrogateescape")


def mode_string(st):
    m = st.st_mode
    if stat.S_ISDIR(m):
        t = "d"
    elif stat.S_ISLNK(m):
        t = "l"
    elif stat.S_ISREG(m):
        t = "-"
    else:
        t = "p"
    bits = ""
    for who in range(3):
        shift = 6 - who * 3
        bits += "r" if m & (4 << shift) else "-"
        bits += "w" if m & (2 << shift) else "-"
        bits += "x" if m & (1 << shift) else "-"
    return t + bits


def list_time(mtime):
    t = time.localtime(mtime)
    if abs(time.time() - mtime) < 180 * 86400:
        return "%s %2d %02d:%02d" % (MONTHS[t.tm_mon - 1], t.tm_mday, t.tm_hour, t.tm_min)
    return "%s %2d  %d" % (MONTHS[t.tm_mon - 1], t.tm_mday, t.tm_year)


def mlsd_time(mtime):
    return time.strftime("%Y%m%d%H%M%S", time.gmtime(mtime))


class Session(socketserver.StreamRequestHandler):
    def setup(self):
        if Config.tls is not None and Config.implicit_tls:
            # TLS from the first byte: handshake before the streams are made.
            self.request.settimeout(30)
            self.request = Config.tls.wrap_socket(self.request, server_side=True)
            self.request.settimeout(None)
        super().setup()
        self.cwd = "/"
        self.user = None
        self.logged_in = False
        self.pasv = None
        self.active = None
        self.rename_from = None
        self.tls_active = Config.tls is not None and Config.implicit_tls
        self.prot_p = self.tls_active  # implicit FTPS: data connections protected by default
        self.pbsz = False

    # --- I/O ---

    def reply(self, text):
        self.wfile.write(to_wire(text + "\r\n"))
        self.wfile.flush()

    def handle(self):
        self.reply("220 iCommander test FTP server")
        while True:
            try:
                raw = self.rfile.readline()
            except OSError:  # includes ConnectionError and ssl.SSLError
                break
            if not raw:
                break
            cmd, _, arg = raw.rstrip(b"\r\n").partition(b" ")
            cmd = cmd.decode("ascii", "replace").upper()
            arg = arg.decode("utf-8" if cmd in ("USER", "PASS") else Config.wire, "surrogateescape")
            try:
                if not self.dispatch(cmd, arg):
                    break
            except OSError:
                break
            except Exception as e:  # keep serving
                try:
                    self.reply("451 Local error: %s" % e)
                except OSError:
                    break
        self.close_data()

    # --- paths ---

    def virtual(self, arg):
        if not arg:
            return self.cwd
        return posixpath.normpath(posixpath.join(self.cwd, arg)).replace("//", "/") or "/"

    def real(self, vpath):
        """Real path for a virtual one, or None when it would leave the root."""
        vpath = posixpath.normpath("/" + vpath.lstrip("/"))
        if vpath.startswith("//"):
            vpath = vpath[1:]
        candidate = os.path.join(Config.root, vpath.lstrip("/"))
        resolved = os.path.realpath(candidate)
        if resolved != Config.root and not resolved.startswith(Config.root + os.sep):
            return None
        return candidate

    def resolve(self, arg):
        v = self.virtual(arg)
        return v, self.real(v)

    # --- data connections ---

    def close_data(self):
        if self.pasv is not None:
            try:
                self.pasv.close()
            except OSError:
                pass
            self.pasv = None
        self.active = None

    def open_data(self):
        if self.pasv is not None:
            self.pasv.settimeout(30)
            conn, _ = self.pasv.accept()
            self.close_data()
            return conn
        if self.active is not None:
            addr = self.active
            self.active = None
            return socket.create_connection(addr, timeout=30)
        return None

    def protect(self, conn):
        """TLS-wrap a data connection (server role, also for active mode) under PROT P."""
        if not self.prot_p:
            return conn
        conn.settimeout(30)
        try:
            return Config.tls.wrap_socket(conn, server_side=True)
        except OSError:
            conn.close()
            raise

    @staticmethod
    def finish_data(conn):
        """Close a data connection; under TLS send close_notify first (best effort)."""
        if isinstance(conn, ssl.SSLSocket):
            try:
                conn.settimeout(5)
                conn.unwrap()
            except (OSError, ValueError):
                pass
        conn.close()

    def send_data(self, payload_iter):
        try:
            conn = self.open_data()
        except OSError:
            self.close_data()
            self.reply("425 Cannot open data connection")
            return
        if conn is None:
            self.reply("425 Use PASV or EPSV first")
            return
        self.reply("150 Opening BINARY mode data connection")
        try:
            conn = self.protect(conn)  # TLS handshake after the 150: clients may wait for it
            try:
                for chunk in payload_iter:
                    conn.sendall(chunk)
                self.finish_data(conn)
            finally:
                conn.close()
        except OSError:
            self.reply("426 Connection closed; transfer aborted")
            return
        self.reply("226 Transfer complete")

    # --- commands ---

    def need_login(self):
        if not self.logged_in:
            self.reply("530 Please login with USER and PASS")
            return True
        return False

    def dispatch(self, cmd, arg):
        if cmd == "QUIT":
            self.reply("221 Goodbye")
            return False
        handler = getattr(self, "cmd_" + cmd, None)
        if handler is None or (cmd in ("MLSD", "MLST") and not Config.mlsd):
            self.reply("500 Unknown command")
            return True
        if cmd not in ("USER", "PASS", "SYST", "FEAT", "OPTS", "NOOP", "AUTH", "PBSZ", "PROT") and self.need_login():
            return True
        handler(arg)
        return True

    def cmd_USER(self, arg):
        self.user = arg
        self.logged_in = False
        self.reply("331 Password required")

    def cmd_PASS(self, arg):
        if self.user is None:
            self.reply("503 Login with USER first")
        elif self.user == "anonymous" and Config.anonymous:
            self.logged_in = True
            self.reply("230 Anonymous login ok")
        elif self.user == Config.user and arg == Config.password:
            self.logged_in = True
            self.reply("230 Login successful")
        else:
            self.reply("530 Login incorrect")

    def cmd_AUTH(self, arg):
        if Config.tls is None or arg.upper() not in ("TLS", "TLS-C"):
            self.reply("502 TLS not supported" if Config.tls is None else "504 Unknown security mechanism")
        elif self.tls_active:
            self.reply("503 TLS already active")
        else:
            self.reply("234 Proceed with negotiation")
            self.connection.settimeout(30)
            self.connection = Config.tls.wrap_socket(self.connection, server_side=True)
            self.connection.settimeout(None)
            self.rfile = self.connection.makefile("rb", self.rbufsize)
            self.wfile = socketserver._SocketWriter(self.connection) if self.wbufsize == 0 \
                else self.connection.makefile("wb", self.wbufsize)
            self.tls_active = True
            # A fresh TLS session resets the security state (RFC 4217).
            self.prot_p = False
            self.pbsz = False

    def cmd_PBSZ(self, arg):
        if not self.tls_active:
            self.reply("503 AUTH TLS first")
        else:
            self.pbsz = True
            self.reply("200 PBSZ=0")

    def cmd_PROT(self, arg):
        level = arg.upper()
        if not self.tls_active:
            self.reply("503 AUTH TLS first")
        elif not self.pbsz:
            self.reply("503 PBSZ first")
        elif level in ("P", "C"):
            self.prot_p = level == "P"
            self.reply("200 Protection level set to %s" % level)
        else:
            self.reply("504 Only protection levels C and P")

    def cmd_SYST(self, arg):
        self.reply("215 UNIX Type: L8")

    def cmd_FEAT(self, arg):
        feats = ["UTF8", "EPSV", "SIZE", "MDTM"] if Config.wire == "utf-8" else ["EPSV", "SIZE", "MDTM"]
        if Config.tls is not None:
            feats = ["AUTH TLS", "PBSZ", "PROT"] + feats
        if Config.mlsd:
            feats = ["MLST type*;size*;modify*;unix.mode*;perm*;", "MLSD"] + feats
        self.reply("211-Features:")
        for f in feats:
            self.reply(" " + f)
        self.reply("211 End")

    def cmd_OPTS(self, arg):
        self.reply("200 OK")

    def cmd_NOOP(self, arg):
        self.reply("200 OK")

    def cmd_PWD(self, arg):
        self.reply('257 "%s" is the current directory' % self.cwd.replace('"', '""'))

    def cmd_CWD(self, arg):
        v, r = self.resolve(arg)
        if r is None or not os.path.isdir(r):
            self.reply("550 No such directory")
        else:
            self.cwd = v
            self.reply("250 Directory changed")

    def cmd_CDUP(self, arg):
        self.cmd_CWD("..")

    def cmd_TYPE(self, arg):
        self.reply("200 Type set to %s" % (arg or "I"))

    def cmd_MODE(self, arg):
        self.reply("200 OK" if arg.upper() == "S" else "504 Only stream mode")

    def cmd_STRU(self, arg):
        self.reply("200 OK" if arg.upper() == "F" else "504 Only file structure")

    def cmd_PASV(self, arg):
        self.close_data()
        self.pasv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.pasv.bind(("127.0.0.1", 0))
        self.pasv.listen(1)
        port = self.pasv.getsockname()[1]
        self.reply("227 Entering Passive Mode (127,0,0,1,%d,%d)" % (port >> 8, port & 0xFF))

    def cmd_EPSV(self, arg):
        self.close_data()
        self.pasv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.pasv.bind(("127.0.0.1", 0))
        self.pasv.listen(1)
        self.reply("229 Entering Extended Passive Mode (|||%d|)" % self.pasv.getsockname()[1])

    def set_active(self, host, port):
        if host not in ("127.0.0.1", "::1", "localhost"):
            self.reply("504 Only loopback data connections")
            return
        self.close_data()
        self.active = (host, port)
        self.reply("200 PORT command successful")

    def cmd_PORT(self, arg):
        try:
            p = [int(x) for x in arg.split(",")]
            self.set_active("%d.%d.%d.%d" % tuple(p[:4]), p[4] * 256 + p[5])
        except (ValueError, IndexError, TypeError):
            self.reply("501 Bad PORT")

    def cmd_EPRT(self, arg):
        try:
            d = arg[0]
            _, _, host, port, _ = arg.split(d)
            self.set_active(host, int(port))
        except (ValueError, IndexError):
            self.reply("501 Bad EPRT")

    def list_target(self, arg):
        parts = [a for a in arg.split(" ") if a] if arg else []
        while parts and parts[0].startswith("-"):
            parts.pop(0)
        return " ".join(parts)

    def entries(self, r, follow=False):
        # A link to a folder is listed as the link, except when the folder itself is listed (MLSD,
        # or LIST of the current folder after CWD through the link), as real servers do.
        if os.path.isdir(r) and (follow or not os.path.islink(r)):
            names = sorted(os.listdir(r))
            return [(n, os.lstat(os.path.join(r, n)), os.path.join(r, n)) for n in names]
        return [(os.path.basename(r), os.lstat(r), r)]

    def cmd_LIST(self, arg):
        target = self.list_target(arg)
        v, r = self.resolve(target)
        if r is None or not os.path.lexists(r):
            self.reply("550 No such file or directory")
            return
        lines = []
        for name, st, full in self.entries(r, follow=not target):
            text = "%s %3d %-8s %-8s %10d %s %s" % (
                mode_string(st), st.st_nlink, "owner", "group", st.st_size, list_time(st.st_mtime), name)
            if stat.S_ISLNK(st.st_mode):
                text += " -> " + os.readlink(full)
            lines.append(text)
        self.send_data([to_wire("".join(l + "\r\n" for l in lines))])

    def cmd_NLST(self, arg):
        v, r = self.resolve(self.list_target(arg))
        if r is None or not os.path.isdir(r):
            self.reply("550 No such directory")
            return
        names = sorted(os.listdir(r))
        self.send_data([to_wire("".join(n + "\r\n" for n in names))])

    def facts(self, name, st):
        m = st.st_mode
        if stat.S_ISDIR(m):
            t, perm = "dir", "elcmf"
        elif stat.S_ISLNK(m):
            t, perm = "OS.unix=symlink", "r"
        else:
            t, perm = "file", "rwadf"
        f = "type=%s;" % t
        if not stat.S_ISDIR(m):
            f += "size=%d;" % st.st_size
        f += "modify=%s;unix.mode=%04o;perm=%s; %s" % (mlsd_time(st.st_mtime), m & 0o7777, perm, name)
        return f

    def cmd_MLSD(self, arg):
        v, r = self.resolve(arg)
        if r is None or not os.path.isdir(r):
            self.reply("550 No such directory")
            return
        lines = [self.facts(n, st) for n, st, _ in self.entries(r, follow=True)]
        self.send_data([to_wire("".join(l + "\r\n" for l in lines))])

    def cmd_MLST(self, arg):
        v, r = self.resolve(arg)
        if r is None or not os.path.lexists(r):
            self.reply("550 No such file or directory")
            return
        self.reply("250-Listing " + v)
        self.reply(" " + self.facts(v, os.lstat(r)))
        self.reply("250 End")

    def regular_file(self, arg):
        v, r = self.resolve(arg)
        if r is None or not os.path.isfile(r):
            self.reply("550 No such file")
            return None
        return r

    def cmd_SIZE(self, arg):
        r = self.regular_file(arg)
        if r is not None:
            self.reply("213 %d" % os.path.getsize(r))

    def cmd_MDTM(self, arg):
        r = self.regular_file(arg)
        if r is not None:
            self.reply("213 " + mlsd_time(os.path.getmtime(r)))

    def cmd_RETR(self, arg):
        r = self.regular_file(arg)
        if r is None:
            self.close_data()
            return

        def chunks():
            with open(r, "rb") as f:
                while True:
                    b = f.read(65536)
                    if not b:
                        return
                    yield b

        self.send_data(chunks())

    def cmd_STOR(self, arg):
        v, r = self.resolve(arg)
        if r is None or v == "/" or not os.path.isdir(os.path.dirname(r)) or os.path.isdir(r):
            self.close_data()
            self.reply("553 Cannot store file here")
            return
        try:
            conn = self.open_data()
        except OSError:
            self.close_data()
            self.reply("425 Cannot open data connection")
            return
        if conn is None:
            self.reply("425 Use PASV or EPSV first")
            return
        self.reply("150 Ready to receive")
        try:
            conn = self.protect(conn)
            with conn, open(r, "wb") as f:
                while True:
                    b = conn.recv(65536)
                    if not b:
                        break
                    f.write(b)
        except OSError:
            self.reply("426 Transfer aborted")
            return
        self.reply("226 Transfer complete")

    def cmd_DELE(self, arg):
        v, r = self.resolve(arg)
        if r is None or not os.path.lexists(r) or (os.path.isdir(r) and not os.path.islink(r)):
            self.reply("550 No such file")
            return
        os.remove(r)
        self.reply("250 Deleted")

    def cmd_MKD(self, arg):
        v, r = self.resolve(arg)
        if r is None or os.path.lexists(r):
            self.reply("550 Cannot create directory")
            return
        try:
            os.mkdir(r)
        except OSError as e:
            self.reply("550 %s" % e.strerror)
            return
        self.reply('257 "%s" created' % v.replace('"', '""'))

    def cmd_RMD(self, arg):
        v, r = self.resolve(arg)
        if r is None or v == "/" or not os.path.isdir(r) or os.path.islink(r):
            self.reply("550 No such directory")
            return
        try:
            os.rmdir(r)
        except OSError as e:
            self.reply("550 %s" % e.strerror)
            return
        self.reply("250 Removed")

    def cmd_RNFR(self, arg):
        v, r = self.resolve(arg)
        if r is None or v == "/" or not os.path.lexists(r):
            self.rename_from = None
            self.reply("550 No such file or directory")
            return
        self.rename_from = r
        self.reply("350 Ready for RNTO")

    def cmd_RNTO(self, arg):
        src, self.rename_from = self.rename_from, None
        if src is None:
            self.reply("503 RNFR first")
            return
        v, r = self.resolve(arg)
        if r is None or os.path.lexists(r):
            self.reply("553 Cannot rename to that name")
            return
        try:
            os.rename(src, r)
        except OSError as e:
            self.reply("550 %s" % e.strerror)
            return
        self.reply("250 Renamed")

    def cmd_ABOR(self, arg):
        self.close_data()
        self.reply("226 Aborted")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", required=True)
    ap.add_argument("--user", required=True)
    pw = ap.add_mutually_exclusive_group(required=True)
    pw.add_argument("--password")
    pw.add_argument("--password-hex")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--no-mlsd", action="store_true")
    ap.add_argument("--anonymous", action="store_true")
    ap.add_argument("--tls-cert", help="PEM certificate (chain) enabling FTPS; needs --tls-key")
    ap.add_argument("--tls-key", help="PEM private key for --tls-cert")
    ap.add_argument("--wire-encoding", default="utf-8",
                    help="names on the wire in this Python codec (e.g. cp1250); on disk they stay UTF-8")
    ap.add_argument("--implicit-tls", action="store_true",
                    help="implicit FTPS: TLS on the control connection from the first byte")
    a = ap.parse_args()
    if bool(a.tls_cert) != bool(a.tls_key):
        sys.exit("--tls-cert and --tls-key go together")
    if a.implicit_tls and not a.tls_cert:
        sys.exit("--implicit-tls needs --tls-cert and --tls-key")
    Config.root = os.path.realpath(a.root)
    if not os.path.isdir(Config.root):
        sys.exit("root is not a directory: %s" % a.root)
    # Re-decode as UTF-8 whatever the locale (argv bytes survive via surrogateescape).
    Config.user = os.fsencode(a.user).decode("utf-8", "surrogateescape")
    if a.password_hex is not None:
        Config.password = bytes.fromhex(a.password_hex).decode("utf-8", "surrogateescape")
    else:
        Config.password = os.fsencode(a.password).decode("utf-8", "surrogateescape")
    Config.mlsd = not a.no_mlsd
    Config.anonymous = a.anonymous
    Config.wire = codecs.lookup(a.wire_encoding).name
    if a.tls_cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.tls_cert, a.tls_key)
        Config.tls = ctx
        Config.implicit_tls = a.implicit_tls
    server = Server(("127.0.0.1", a.port), Session)
    print(server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
