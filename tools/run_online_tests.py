"""Route three actual Godot game peers through a local Noray-compatible UDP relay."""
import argparse
import asyncio
from pathlib import Path
import tempfile
import time

from noray_test_service import NorayTestService


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--four", action="store_true", help="Run four-player relayed presentation/game flows")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    service = await NorayTestService().start()
    processes, handles = [], []
    prefix = [args.godot, "--headless", "--path", str(project),
              ("res://scenes/multiplayer/online_presentation_tests.tscn" if args.four else "res://scenes/multiplayer/online_table_tests.tscn"), "--",
              "--control=" + str(service.control_port), "--registrar=" + str(service.registrar_port)]
    with tempfile.TemporaryDirectory(prefix="blackjack-online-") as folder:
        logs = Path(folder)
        try:
            ui_handle = (logs / "ui.log").open("w")
            handles.append(ui_handle)
            ui_process = await asyncio.create_subprocess_exec(
                args.godot, "--headless", "--path", str(project),
                "res://scenes/multiplayer/online_connection_tests.tscn", "--",
                "--control=" + str(service.control_port), "--registrar=" + str(service.registrar_port),
                stdout=ui_handle, stderr=asyncio.subprocess.STDOUT)
            processes.append(ui_process)
            await asyncio.wait_for(ui_process.wait(), timeout=25)
            content = (logs / "ui.log").read_text()
            print(content, end="")
            if ui_process.returncode or "ERROR:" in content or "PASS:" not in content:
                raise RuntimeError("Online launcher/cleanup cases failed")
            processes.clear()
            code = ""
            for role in (("host", "A", "B", "C") if args.four else ("host", "A", "B")):
                handle = (logs / (role + ".log")).open("w")
                handles.append(handle)
                processes.append(await asyncio.create_subprocess_exec(*prefix, "--role=" + role, "--code=" + code, stdout=handle, stderr=asyncio.subprocess.STDOUT))
                if role == "host":
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        content = (logs / "host.log").read_text()
                        for line in content.splitlines():
                            if line.startswith("ONLINE ROOM CODE "):
                                code = line.removeprefix("ONLINE ROOM CODE ")
                        if code:
                            break
                        if "ERROR:" in content:
                            raise RuntimeError(content)
                        await asyncio.sleep(.1)
                    if not code:
                        raise RuntimeError("Online host did not register")
            deadline = time.monotonic() + 55
            while any(p.returncode is None for p in processes):
                if any("ERROR:" in p.read_text() for p in logs.glob("*.log")):
                    raise RuntimeError("Online peer reported an error")
                if time.monotonic() > deadline:
                    raise RuntimeError("Online game peers timed out")
                await asyncio.sleep(.1)
            for role, process in zip((("host", "A", "B", "C") if args.four else ("host", "A", "B")), processes):
                content = (logs / (role + ".log")).read_text()
                print(content, end="")
                if process.returncode or "PASS:" not in content:
                    raise RuntimeError("Online game flow failed: " + role)
            if service.packets < 100 or service.byte_count < 10000:
                raise RuntimeError("Game did not send enough data through the actual relay")
            print("Relay forwarded", service.packets, "packets /", service.byte_count, "bytes")
            print("ALL ONLINE RELAY TABLE TESTS PASSED")
        except Exception:
            for path in logs.glob("*.log"):
                print(path.name + ":\n" + path.read_text())
            raise
        finally:
            for process in processes:
                if process.returncode is None:
                    process.kill()
                await process.wait()
            for handle in handles:
                handle.close()
            await service.close()


if __name__ == "__main__":
    asyncio.run(main())
