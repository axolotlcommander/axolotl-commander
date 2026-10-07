#!/usr/bin/env python3
"""Minimal FTP server for iCommander tests and manual GUI testing (stdlib only).

    /usr/bin/python3 -I scripts/ftp-test-server.py --root DIR --user U --password P \
        [--port 0] [--no-mlsd] [--anonymous]

--password-hex HEX gives the password as hex of its UTF-8 bytes instead (exact bytes;
Foundation's Process may NFD-normalize non-ASCII arguments).

Listens on 127.0.0.1 only and prints the chosen port as the first line of stdout.
The login directory is ROOT, shown as "/". Every path must resolve (symlinks included)
inside ROOT, otherwise the command fails with 550. Names are UTF-8. Plain FTP only (no TLS).
Serves threaded sessions until killed.
"""

import argparse
import os
import posixpath
import socket
import socketserver
import stat
import sys
import threading
import time

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


class Config:
    root = ""
    user = ""
    password = ""
    mlsd = True
    anonymous = False


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
        super().setup()
        self.cwd = "/"
        self.user = None
        self.logged_in = False
        self.pasv = None
        self.active = None
        self.rename_from = None

    # --- I/O ---

    def reply(self, text):
        self.wfile.write((text + "\r\n").encode("utf-8", "surrogateescape"))
        self.wfile.flush()

    def handle(self):
        self.reply("220 iCommander test FTP server")
        while True:
            try:
                raw = self.rfile.readline()
            except (ConnectionError, OSError):
                break
            if not raw:
                break
            line = raw.rstrip(b"\r\n").decode("utf-8", "surrogateescape")
            cmd, _, arg = line.partition(" ")
            cmd = cmd.upper()
            try:
                if not self.dispatch(cmd, arg):
                    break
            except (ConnectionError, BrokenPipeError):
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
            with conn:
                for chunk in payload_iter:
                    conn.sendall(chunk)
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
        if cmd not in ("USER", "PASS", "SYST", "FEAT", "OPTS", "NOOP", "AUTH") and self.need_login():
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
        self.reply("502 TLS not supported")

    def cmd_SYST(self, arg):
        self.reply("215 UNIX Type: L8")

    def cmd_FEAT(self, arg):
        feats = ["UTF8", "EPSV", "SIZE", "MDTM"]
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
        self.send_data([("".join(l + "\r\n" for l in lines)).encode("utf-8", "surrogateescape")])

    def cmd_NLST(self, arg):
        v, r = self.resolve(self.list_target(arg))
        if r is None or not os.path.isdir(r):
            self.reply("550 No such directory")
            return
        names = sorted(os.listdir(r))
        self.send_data([("".join(n + "\r\n" for n in names)).encode("utf-8", "surrogateescape")])

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
        self.send_data([("".join(l + "\r\n" for l in lines)).encode("utf-8", "surrogateescape")])

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
    a = ap.parse_args()
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
    server = Server(("127.0.0.1", a.port), Session)
    print(server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
