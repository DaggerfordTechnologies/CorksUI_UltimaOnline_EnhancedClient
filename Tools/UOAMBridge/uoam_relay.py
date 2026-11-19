"""UOAM hub relay for Corks' UOAM Bridge

UOAM links to the bridge (127.0.0.1:2000) instead of the hub; the relay passes
everything through unchanged and reads the player list out of the hub's
replies, so CorksUI can show the other players on the EC map.

UOAM talks to its hub with Microsoft RPC (DCE/RPC over TCP). Worked out from a
recording of UOAM 8 and uoamhub.classicuo.org:

  opnum 1, request stub of 116 bytes: this player's position
      password[20] ip[4] name[79] facet[1] x:u32 y:u32 z:u32
  opnum 2, reply: the group's players
      count:u32 referent:u32 [max:u32] then count records of 92 bytes:
      name[79] facet[1] x:u32 y:u32 z:u32
  facet is a letter: f Felucca, t Trammel, i Ilshenar, m Malas, s Tokuno
  (UOAM's table is "ftims"; it has none for Ter Mur).

UOAM doesn't take the map number the bridge posts it (it keeps sending 'f'),
so the relay sets the facet letter in UOAM's position updates to the EC's map
on the way to the hub.

UOAM asks for the list about every 5 seconds. The relay writes it to a text
file the EC reads with LoadTextFile:

  UOAM|<update number>
  <facet>|<x>|<y>|<name>        one line per player, not including you
"""

import asyncio
import os
import struct
import threading
import time

FACETS = {"f": 0, "t": 1, "i": 2, "m": 3, "s": 4}
FACET_LETTERS = {v: k for k, v in FACETS.items()}

RPC_REQUEST = 0
RPC_RESPONSE = 2
FIRST_FRAG = 0x01
LAST_FRAG = 0x02
OBJECT_UUID = 0x80

OP_POSITION = 1
OP_PLAYERS = 2
POSITION_STUB = 116
RECORD = 92


def _text(raw):
    """A fixed-size name field as plain text (UOAM pads with zeros)."""
    name = raw.split(b"\0", 1)[0].decode("latin-1")
    # One line per player in the file, fields split on "|"; keep it plain ASCII
    return "".join(c if 32 <= ord(c) < 127 and c != "|" else "?" for c in name).strip()


def parse_position(stub):
    """This player's update (opnum 1): (name, facet letter, x, y), or None."""
    if len(stub) != POSITION_STUB:
        return None
    name = _text(stub[24:103])
    facet = chr(stub[103])
    x, y = struct.unpack_from("<II", stub, 104)
    return name, facet, x, y


def parse_players(stub):
    """The player list (opnum 2): [(name, facet letter, x, y)], or None if malformed."""
    if len(stub) < 8:
        return None
    count, referent = struct.unpack_from("<II", stub, 0)
    if count == 0 or referent == 0:
        return []
    start = 12  # count, referent, then the array's max count
    if count > 1000 or start + count * RECORD > len(stub):
        return None
    players = []
    for i in range(count):
        r = stub[start + i * RECORD: start + (i + 1) * RECORD]
        x, y = struct.unpack_from("<II", r, 80)
        players.append((_text(r[:79]), chr(r[79]), x, y))
    return players


class RpcStream:
    """Splits one direction of a connection into DCE/RPC PDUs and joins fragments.

    feed() returns completed calls as (ptype, call_id, opnum or None, stub)."""

    def __init__(self):
        self.buf = bytearray()
        self.partial = {}  # call_id -> (ptype, opnum, bytearray)

    def feed(self, data):
        self.buf += data
        done = []
        while len(self.buf) >= 16:
            if self.buf[0] != 5:  # not RPC version 5: give up on this stream
                self.buf.clear()
                break
            frag_len, auth_len = struct.unpack_from("<HH", self.buf, 8)
            if frag_len < 16:
                self.buf.clear()
                break
            if len(self.buf) < frag_len:
                break
            pdu = bytes(self.buf[:frag_len])
            del self.buf[:frag_len]
            ptype, flags = pdu[2], pdu[3]
            if ptype not in (RPC_REQUEST, RPC_RESPONSE) or len(pdu) < 24:
                continue
            call_id = struct.unpack_from("<I", pdu, 12)[0]
            opnum = struct.unpack_from("<H", pdu, 22)[0] if ptype == RPC_REQUEST else None
            start = 24 + (16 if ptype == RPC_REQUEST and flags & OBJECT_UUID else 0)
            end = frag_len - (auth_len + 8 if auth_len else 0)
            stub = pdu[start:end]
            if flags & FIRST_FRAG:
                self.partial[call_id] = (ptype, opnum, bytearray())
            entry = self.partial.get(call_id)
            if entry is None:
                continue
            entry[2].extend(stub)
            if flags & LAST_FRAG:
                del self.partial[call_id]
                done.append((entry[0], call_id, entry[1], bytes(entry[2])))
        return done


class PduSplitter:
    """Splits a byte stream into whole DCE/RPC PDUs, so one can be changed
    before it's passed on. Anything that isn't RPC is passed on as it comes."""

    def __init__(self):
        self.buf = bytearray()
        self.passthrough = False

    def feed(self, data):
        if self.passthrough:
            return [bytes(data)]
        self.buf += data
        out = []
        while len(self.buf) >= 16:
            frag_len = struct.unpack_from("<H", self.buf, 8)[0]
            if self.buf[0] != 5 or frag_len < 16:
                self.passthrough = True
                out.append(bytes(self.buf))
                self.buf.clear()
                break
            if len(self.buf) < frag_len:
                break
            out.append(bytes(self.buf[:frag_len]))
            del self.buf[:frag_len]
        return out


# Where the facet letter sits in UOAM's position update: a single-fragment
# request, no object UUID or authentication, 24-byte header + 116-byte stub
POSITION_PDU = 24 + POSITION_STUB
POSITION_FACET_AT = 24 + 103


def fix_position_facet(pdu, letter):
    """UOAM's position update with its facet letter set to letter; any other
    PDU is returned as it is."""
    if (letter is None or len(pdu) != POSITION_PDU or pdu[2] != RPC_REQUEST
            or pdu[3] & (FIRST_FRAG | LAST_FRAG | OBJECT_UUID) != FIRST_FRAG | LAST_FRAG
            or struct.unpack_from("<H", pdu, 10)[0] != 0
            or struct.unpack_from("<H", pdu, 22)[0] != OP_POSITION
            or pdu[POSITION_FACET_AT] == ord(letter)):
        return pdu
    fixed = bytearray(pdu)
    fixed[POSITION_FACET_AT] = ord(letter)
    return bytes(fixed)


class Relay:
    """Listens for UOAM, forwards to the hub, keeps the latest player list."""

    def __init__(self, hub_host, hub_port, listen_port, out_path, log, verbose=False):
        self.hub = (hub_host, hub_port)
        self.listen_port = listen_port
        self.out_path = out_path
        self.log = log
        self.verbose = verbose
        self.own_name = None
        self.own_facet = None
        self.players = []
        self.update_number = 0
        self.unknown_facets = set()
        self.connections = 0
        self.expected_facet = None  # set by the bridge from the EC's map number

    # --- player list --------------------------------------------------------

    def on_call(self, direction, ptype, opnum, stub, pending):
        if direction == "up" and ptype == RPC_REQUEST:
            if opnum == OP_POSITION:
                pos = parse_position(stub)
                if pos:
                    name, facet, _, _ = pos
                    if name != self.own_name:
                        self.log(f"UOAM is sending you as {name}")
                        self.own_name = name
                    if facet != self.own_facet:
                        self.own_facet = facet
                        self.check_own_facet()
            return
        if direction == "down" and ptype == RPC_RESPONSE and pending == OP_PLAYERS:
            players = parse_players(stub)
            if players is None:
                self.log("Couldn't read a player list from the hub; skipped it")
                return
            self.set_players(players)

    def check_own_facet(self):
        want = FACET_LETTERS.get(self.expected_facet)
        if self.own_facet and want and self.own_facet != want:
            # fix_position_facet corrects it on the way to the hub
            self.log(f"UOAM has you on map '{self.own_facet}', but the EC says '{want}'; "
                     f"the bridge sends '{want}' to the hub instead")

    def set_players(self, players):
        others = []
        for name, letter, x, y in players:
            if name == self.own_name:
                continue
            facet = FACETS.get(letter)
            if facet is None:
                if letter not in self.unknown_facets:
                    self.unknown_facets.add(letter)
                    self.log(f"{name} is on a map UOAM calls '{letter}', which the bridge doesn't know; not shown")
                continue
            others.append((facet, x, y, name))
        if self.verbose or len(others) != len(self.players):
            self.log(f"{len(others)} other UOAM player(s): " + ", ".join(p[3] for p in others))
        self.players = others
        self.write()

    def write(self, players=None):
        players = self.players if players is None else players
        self.update_number += 1
        lines = [f"UOAM|{self.update_number}"] + [f"{f}|{x}|{y}|{n}" for f, x, y, n in players]
        text = "\n".join(lines) + "\n"
        tmp = self.out_path + ".tmp"
        for _ in range(5):  # the EC may be reading it; try again shortly
            try:
                with open(tmp, "w", encoding="ascii", newline="\n") as f:
                    f.write(text)
                os.replace(tmp, self.out_path)
                return
            except OSError:
                time.sleep(0.05)
        self.log(f"Couldn't write {self.out_path}")

    def clear(self):
        self.players = []
        self.write([])

    # --- network ------------------------------------------------------------

    async def pipe(self, direction, reader, writer, stream, pending):
        # UOAM's own updates are passed on a whole PDU at a time, so the facet
        # letter can be corrected; the hub's replies are passed on as they come
        splitter = PduSplitter() if direction == "up" else None
        try:
            while True:
                data = await reader.read(65536)
                if not data:
                    break
                if splitter:
                    letter = FACET_LETTERS.get(self.expected_facet)
                    for pdu in splitter.feed(data):
                        writer.write(fix_position_facet(pdu, letter))
                else:
                    writer.write(data)  # pass it on first; reading it never holds UOAM up
                await writer.drain()
                try:
                    for ptype, call_id, opnum, stub in stream.feed(data):
                        if ptype == RPC_REQUEST:
                            pending[call_id] = opnum
                            self.on_call(direction, ptype, opnum, stub, None)
                        else:
                            self.on_call(direction, ptype, None, stub, pending.pop(call_id, None))
                except Exception as e:  # a decoding problem must never break the link
                    self.log(f"Couldn't decode hub traffic: {e}")
        except (ConnectionError, OSError):
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def handle(self, up_reader, up_writer):
        try:
            down_reader, down_writer = await asyncio.open_connection(*self.hub)
        except OSError as e:
            self.log(f"Couldn't reach the UOAM hub {self.hub[0]}:{self.hub[1]}: {e}")
            up_writer.close()
            return
        self.connections += 1
        if self.connections == 1:
            self.log(f"UOAM linked through the bridge to {self.hub[0]}:{self.hub[1]}")
        pending = {}
        await asyncio.gather(
            self.pipe("up", up_reader, down_writer, RpcStream(), pending),
            self.pipe("down", down_reader, up_writer, RpcStream(), pending),
        )
        self.connections -= 1
        if self.connections == 0:
            self.log("UOAM unlinked from the hub")
            self.clear()

    async def serve(self):
        try:
            server = await asyncio.start_server(self.handle, "127.0.0.1", self.listen_port)
        except OSError as e:
            self.log(f"Couldn't listen on 127.0.0.1:{self.listen_port} ({e}); other players won't be shown")
            return
        self.log(f"For other players on the EC map, link UOAM to 127.0.0.1 port {self.listen_port}")
        async with server:
            await server.serve_forever()

    def start(self):
        self.clear()
        threading.Thread(target=lambda: asyncio.run(self.serve()), daemon=True).start()
