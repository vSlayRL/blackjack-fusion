"""Local Noray-compatible protocol fixture; not a production/public relay server.

TCP registration, UDP address registration and sender-port-translating UDP relays
match the upstream protocol. Real Godot ENet packets pass through these sockets.
"""
import asyncio
import secrets


class Registrar(asyncio.DatagramProtocol):
    def __init__(self, service):
        self.service = service

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, address):
        entry = self.service.private.get(data.decode("ascii", errors="ignore"))
        if entry:
            entry["remote"] = address
            self.transport.sendto(b"OK", address)


class Relay(asyncio.DatagramProtocol):
    def __init__(self, service, target):
        self.service, self.target = service, target

    def datagram_received(self, data, address):
        source = next((e for e in self.service.relay_entries if e.get("remote") == address), None)
        if source and source.get("relay") and self.target.get("remote"):
            source["relay"].sendto(data, self.target["remote"])
            self.service.packets += 1
            self.service.byte_count += len(data)


class NorayTestService:
    def __init__(self):
        self.entries, self.private = {}, {}
        self.relay_entries = []
        self.packets = self.byte_count = 0
        self.serial = 0
        self.transports = []
        self.silent = False

    async def start(self):
        loop = asyncio.get_running_loop()
        self.server = await asyncio.start_server(self.handle, "127.0.0.1", 0)
        self.control_port = self.server.sockets[0].getsockname()[1]
        udp, _ = await loop.create_datagram_endpoint(lambda: Registrar(self), local_addr=("127.0.0.1", 0))
        self.transports.append(udp)
        self.registrar_port = udp.get_extra_info("sockname")[1]
        return self

    async def ensure_relay(self, entry):
        if "relay" not in entry:
            transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(
                lambda: Relay(self, entry), local_addr=("127.0.0.1", 0))
            entry["relay"] = transport
            entry["port"] = transport.get_extra_info("sockname")[1]
            self.transports.append(transport)
            # Upstream relay entries outlive the TCP host repository entry. Retain
            # them so a final ENet disconnect datagram is forwarded after TCP EOF.
            self.relay_entries.append(entry)

    async def handle(self, reader, writer):
        entry = None
        try:
            while line := await reader.readline():
                if self.silent:
                    continue
                command, _, value = line.decode("ascii").strip().partition(" ")
                if command == "register-host":
                    self.serial += 1
                    entry = {"oid": "test-room-" + str(self.serial), "pid": secrets.token_hex(16), "writer": writer}
                    self.entries[entry["oid"]] = entry
                    self.private[entry["pid"]] = entry
                    # Split a command across TCP writes to exercise framing, not packet assumptions.
                    writer.write(b"set-o")
                    await writer.drain()
                    await asyncio.sleep(.01)
                    writer.write(("id " + entry["oid"] + "\nset-pid " + entry["pid"] + "\n").encode("ascii"))
                    await writer.drain()
                elif command == "connect-relay" and entry:
                    host = self.entries.get(value)
                    if not host or not host.get("remote"):
                        writer.write(b"error room-not-found\n")
                        await writer.drain()
                        continue
                    await self.ensure_relay(host)
                    await self.ensure_relay(entry)
                    writer.write(("connect-relay " + str(host["port"]) + "\n").encode("ascii"))
                    host["writer"].write(("connect-relay " + str(entry["port"]) + "\n").encode("ascii"))
                    await writer.drain()
                    await host["writer"].drain()
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            if entry:
                self.entries.pop(entry["oid"], None)
                self.private.pop(entry["pid"], None)
            writer.close()

    async def close(self):
        self.server.close()
        await self.server.wait_closed()
        for entry in list(self.entries.values()):
            entry["writer"].close()
        for transport in self.transports:
            transport.close()
        await asyncio.sleep(.05)
