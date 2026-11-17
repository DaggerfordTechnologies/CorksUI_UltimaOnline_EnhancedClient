"""Corks' UOAM Bridge

Lets UOAM (UO Automap) follow an Enhanced Client player, so EC players show
up on a shared UOAM map with classic and ClassicUO players.

UOAM reads positions through the UOAssist API: it looks for a hidden window
named "UOASSIST-TP-MSG-WND" and asks it for the player's coordinates with
Windows messages. ClassicUO and Razor provide that window; the EC doesn't.
This script provides it, answering with the position the EC writes to
logs/pos.log (map|x|y, rewritten as the player moves).

It also relays UOAM's link to its hub (uoam_relay.py): link UOAM to
127.0.0.1 port 2000 instead of the hub, and the other players are written to
logs/CorksUOAMBridge.txt for CorksUI to show on the EC map.

Run it while the EC is running, then start UOAM. Windows only, Python 3,
standard library only.

    py uoam_bridge.py                 (pos.log found from this script's folder)
    py uoam_bridge.py --log "D:\\...\\Ultima Online Enhanced\\logs\\pos.log"
    py uoam_bridge.py --hub uoamhub.classicuo.org:443   (the hub to relay to)
    py uoam_bridge.py --verbose       (print every message UOAM sends)
"""

import argparse
import ctypes
import os
import re
import signal
import sys
import time
from ctypes import wintypes

from uoam_relay import Relay

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)


class WNDCLASSW(ctypes.Structure):
    _fields_ = [
        ("style", wintypes.UINT),
        ("lpfnWndProc", WNDPROC),
        ("cbClsExtra", ctypes.c_int),
        ("cbWndExtra", ctypes.c_int),
        ("hInstance", wintypes.HINSTANCE),
        ("hIcon", wintypes.HICON),
        ("hCursor", wintypes.HANDLE),
        ("hbrBackground", wintypes.HBRUSH),
        ("lpszMenuName", wintypes.LPCWSTR),
        ("lpszClassName", wintypes.LPCWSTR),
    ]


user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASSW)]
user32.RegisterClassW.restype = wintypes.ATOM
user32.CreateWindowExW.argtypes = [
    wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
    ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID,
]
user32.CreateWindowExW.restype = wintypes.HWND
user32.DefWindowProcW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.DefWindowProcW.restype = LRESULT
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL
user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
user32.FindWindowW.restype = wintypes.HWND
user32.SetTimer.argtypes = [wintypes.HWND, ctypes.c_size_t, wintypes.UINT, wintypes.LPVOID]
user32.SetTimer.restype = ctypes.c_size_t
user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
user32.GetMessageW.restype = wintypes.BOOL
user32.TranslateMessage.argtypes = [ctypes.POINTER(wintypes.MSG)]
user32.DispatchMessageW.argtypes = [ctypes.POINTER(wintypes.MSG)]
user32.DispatchMessageW.restype = LRESULT
user32.PostQuitMessage.argtypes = [ctypes.c_int]
user32.IsWindow.argtypes = [wintypes.HWND]
user32.IsWindow.restype = wintypes.BOOL
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user32.EnumWindows.argtypes = [WNDENUMPROC, wintypes.LPARAM]
kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.GlobalGetAtomNameW.argtypes = [wintypes.ATOM, wintypes.LPWSTR, ctypes.c_int]
kernel32.GlobalGetAtomNameW.restype = wintypes.UINT

# The UOAssist API, as ClassicUO implements it (Game/UoAssist.cs)
WINDOW_NAME = "UOASSIST-TP-MSG-WND"
WM_USER = 0x400
WM_TIMER = 0x0113
# Sent to us by UOAM
REGISTER = WM_USER + 200
COUNT_RESOURCES = WM_USER + 201
GET_COORDS = WM_USER + 202
GET_SKILL = WM_USER + 203
GET_STAT = WM_USER + 204
SET_MACRO = WM_USER + 205
PLAY_MACRO = WM_USER + 206
DISPLAY_TEXT = WM_USER + 207
REQUEST_MULTIS = WM_USER + 208
ADD_CMD = WM_USER + 209
GET_UID = WM_USER + 210
GET_SHARDNAME = WM_USER + 211
ADD_USER_2_PARTY = WM_USER + 212
GET_UO_HWND = WM_USER + 213
GET_POISON = WM_USER + 214
SET_SKILL_LOCK = WM_USER + 215
GET_ACCT_ID = WM_USER + 216
# Posted by us to UOAM
LOGIN = WM_USER + 303
LOGOUT = WM_USER + 308
MAP_INFO = WM_USER + 312

NAMES = {v: k for k, v in list(globals().items()) if k.isupper() and isinstance(v, int) and WM_USER + 200 <= v <= WM_USER + 216}

# One line, e.g. "[26/11/16][18:16:01] XY:  3|1067|534!"  (map|x|y)
POS_PATTERN = re.compile(r"XY:\s*(\d+)\|(\d+)\|(\d+)!")
EC_PROCESS = "uosa.exe"
# Window housekeeping messages not worth printing with --verbose
QUIET_MESSAGES = {0x0001, 0x0002, 0x0003, 0x0005, 0x0006, 0x0007, 0x0008, 0x000C, 0x000D, 0x000E, 0x0018,
                  0x001C, 0x0024, 0x0046, 0x0047, 0x0081, 0x0082, 0x0083, 0x0086, 0x007F, 0x0090, 0x031F}
POLL_MS = 250
TIMER_ID = 1
# UOAM can miss the map number sent when it connects, and is only told again
# on a map change, so it's repeated this often (seconds)
MAP_INFO_EVERY = 5
DEFAULT_HUB = "uoamhub.classicuo.org:443"
DEFAULT_LISTEN_PORT = 2000
PLAYERS_FILE = "CorksUOAMBridge.txt"  # next to pos.log


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def default_log_path():
    # This script lives in <EC>\UserInterface\CorksUI\Tools\UOAMBridge
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "..", "..", "logs", "pos.log"))


def process_name(hwnd):
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    handle = kernel32.OpenProcess(0x1000, False, pid.value)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wintypes.DWORD(len(buf))
        if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return os.path.basename(buf.value).lower()
        return ""
    finally:
        kernel32.CloseHandle(handle)


def find_ec_window():
    """The EC's visible game window, or None."""
    found = []

    def check(hwnd, _):
        if user32.IsWindowVisible(hwnd) and process_name(hwnd) == EC_PROCESS:
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(WNDENUMPROC(check), 0)
    return found[0] if found else None


def window_title(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, buf, len(buf))
    return buf.value


class Bridge:
    def __init__(self, log_path, verbose, relay=None):
        self.log_path = log_path
        self.verbose = verbose
        self.relay = relay
        self.last_map_info = 0.0
        self.hwnd = None
        self.listeners = set()  # UOAM windows that sent REGISTER
        self.position = None  # (map, x, y)
        self.log_mtime = None
        self.ec_hwnd = None
        self.ec_checked = 0.0
        self.stopping = False  # set by Ctrl+C; the next timer tick ends the loop
        self.coord_requests = 0  # since the last report
        self.last_report = time.monotonic()
        self._wndproc = WNDPROC(self.wndproc)  # kept alive for the window's lifetime

    # --- position ---------------------------------------------------------

    def read_position(self):
        """Re-reads pos.log when it has changed; tells UOAM about map changes."""
        try:
            mtime = os.stat(self.log_path).st_mtime_ns
        except OSError:
            return
        if mtime == self.log_mtime:
            return
        try:
            with open(self.log_path, "rb") as f:
                raw = f.read()
        except OSError:
            return  # the EC is writing it; try again next tick
        text = raw.decode("utf-16", errors="ignore") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", errors="ignore")
        matches = POS_PATTERN.findall(text)
        if not matches:
            return
        self.log_mtime = mtime
        new = tuple(int(n) for n in matches[-1])
        old = self.position
        self.position = new
        if old is None or old[0] != new[0]:
            log(f"Map {new[0]}, at {new[1]}, {new[2]}")
            self.send_map()
            if self.relay:
                self.relay.expected_facet = new[0]
                self.relay.check_own_facet()
        elif self.verbose:
            log(f"At {new[1]}, {new[2]}")

    def ec_window(self):
        now = time.monotonic()
        if self.ec_hwnd and user32.IsWindow(self.ec_hwnd):
            return self.ec_hwnd
        if now - self.ec_checked > 2:
            self.ec_checked = now
            self.ec_hwnd = find_ec_window()
            if self.ec_hwnd:
                log(f"Found the EC window: {window_title(self.ec_hwnd)}")
        return self.ec_hwnd

    def report(self):
        """With --verbose, every 5 seconds: how often UOAM asked for coordinates."""
        now = time.monotonic()
        if not self.verbose or now - self.last_report < 5:
            return
        self.last_report = now
        where = f"map {self.position[0]}, {self.position[1]}, {self.position[2]}" if self.position else "no position yet"
        log(f"UOAM asked for coordinates {self.coord_requests} times in 5s ({where}, {len(self.listeners)} UOAM connected)")
        self.coord_requests = 0

    # --- messages ---------------------------------------------------------

    def send_map(self):
        """Tells every connected UOAM which map the EC player is on."""
        if self.position:
            self.last_map_info = time.monotonic()
            self.post_all(MAP_INFO, self.position[0], 0)

    def post_all(self, msg, wparam, lparam):
        for hwnd in list(self.listeners):
            if not user32.PostMessageW(hwnd, msg, wparam, lparam):
                self.listeners.discard(hwnd)

    def wndproc(self, hwnd, msg, wparam, lparam):
        if msg == WM_TIMER and wparam == TIMER_ID:
            if self.stopping:
                user32.PostQuitMessage(0)
            else:
                self.read_position()
                if time.monotonic() - self.last_map_info >= MAP_INFO_EVERY:
                    self.send_map()
                self.report()
            return 0
        if self.verbose and msg not in QUIET_MESSAGES and not (WM_USER + 200 <= msg < WM_USER + 315):
            log(f"Other message 0x{msg:04X}({wparam}, {lparam})")
        if WM_USER + 200 <= msg < WM_USER + 315:
            try:
                result = self.on_uoassist(msg, wparam, lparam)
            except Exception as e:  # never let an error escape into Windows
                log(f"Error handling {NAMES.get(msg, msg)}: {e}")
                result = 0
            if self.verbose and msg != GET_COORDS:
                log(f"{NAMES.get(msg, msg)}({wparam}, {lparam}) -> {result}")
            return result
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    def on_uoassist(self, msg, wparam, lparam):
        if msg == REGISTER:
            if wparam in self.listeners:
                self.listeners.discard(wparam)
                log("UOAM disconnected")
                return 2
            self.listeners.add(wparam)
            log("UOAM connected")
            if self.position:
                user32.PostMessageW(wparam, MAP_INFO, self.position[0], 0)
            return 1

        if msg == GET_COORDS:
            self.coord_requests += 1
            self.read_position()
            if not self.position:
                return 0
            if wparam == 1:
                return 0  # height; the EC doesn't write it
            _, x, y = self.position
            return (x & 0xFFFF) | ((y & 0xFFFF) << 16)

        if msg == GET_UO_HWND:
            return self.ec_window() or 0

        if msg == DISPLAY_TEXT:
            # Text UOAM wants shown in the game (e.g. UOAM chat). The EC can't
            # be sent text from outside, so it's shown here instead.
            buf = ctypes.create_unicode_buffer(256)
            if kernel32.GlobalGetAtomNameW(lparam & 0xFFFF, buf, len(buf)):
                log(f"UOAM: {buf.value}")
                return 1
            return 0

        if msg == REQUEST_MULTIS:
            return 1 if self.position else 0

        if msg == GET_UID:
            return 0x7FFFFFFF if self.position else 0

        return 0  # not supported

    # --- window -----------------------------------------------------------

    def run(self):
        if user32.FindWindowW(None, WINDOW_NAME):
            log("Another UOAssist window is already open (UOAssist, Razor, ClassicUO or another bridge). Close it first.")
            return 1

        hinst = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSW()
        wc.lpfnWndProc = self._wndproc
        wc.hInstance = hinst
        wc.lpszClassName = WINDOW_NAME
        if not user32.RegisterClassW(ctypes.byref(wc)):
            err = ctypes.get_last_error()
            if err != 1410:  # ERROR_CLASS_ALREADY_EXISTS
                log(f"Couldn't register the window class (error {err})")
                return 1

        self.hwnd = user32.CreateWindowExW(0, WINDOW_NAME, WINDOW_NAME, 0, 0, 0, 0, 0, None, None, hinst, None)
        if not self.hwnd:
            log(f"Couldn't create the window (error {ctypes.get_last_error()})")
            return 1

        user32.SetTimer(self.hwnd, TIMER_ID, POLL_MS, None)
        log(f"Reading {self.log_path}")
        if not os.path.exists(self.log_path):
            log("pos.log doesn't exist yet. It appears once you're logged in to the EC and move.")
        self.read_position()
        self.ec_window()
        log("Ready. Start UOAM now. Press Ctrl+C here to stop.")

        msg = wintypes.MSG()
        while True:
            r = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if r == 0 or r == -1:
                break
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        return 0


def main():
    if sys.platform != "win32":
        print("Windows only.")
        return 1
    parser = argparse.ArgumentParser(description="Lets UOAM follow an Enhanced Client player.")
    parser.add_argument("--log", default=default_log_path(), help="path to the EC's logs\\pos.log")
    parser.add_argument("--verbose", action="store_true", help="print every message UOAM sends")
    parser.add_argument("--hub", default=DEFAULT_HUB, help="the UOAM hub to relay to, as host:port (default %(default)s)")
    parser.add_argument("--listen-port", type=int, default=DEFAULT_LISTEN_PORT,
                        help="the port UOAM links to on 127.0.0.1 (default %(default)s)")
    parser.add_argument("--no-relay", action="store_true", help="don't relay UOAM's hub link (no other players on the EC map)")
    args = parser.parse_args()

    relay = None
    if not args.no_relay:
        host, _, port = args.hub.rpartition(":")
        if not host or not port.isdigit():
            print("--hub must be host:port, e.g. " + DEFAULT_HUB)
            return 1
        out = os.path.join(os.path.dirname(os.path.abspath(args.log)), PLAYERS_FILE)
        relay = Relay(host, int(port), args.listen_port, out, log, args.verbose)
        relay.start()

    bridge = Bridge(args.log, args.verbose, relay)

    def stop(*_):
        bridge.stopping = True

    # Ctrl+C can't interrupt the Windows message loop, so it sets a flag instead
    signal.signal(signal.SIGINT, stop)
    result = bridge.run()
    if relay:
        relay.clear()  # so the EC map doesn't keep showing players
    log("Stopped")
    return result


if __name__ == "__main__":
    sys.exit(main())
