"""Real game peers through a local relay with 120ms per direction (240ms RTT)."""
import argparse
import asyncio
from pathlib import Path
import tempfile
import time

from noray_test_service import NorayTestService


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--rendered", action="store_true", help="Use native windows on the current display")
    parser.add_argument("--screenshots", default="", help="Optional rendered QA screenshot directory")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    service = await NorayTestService(delay_seconds=.12).start()
    processes, handles = [], []
    prefix = [args.godot] + (["--audio-driver", "Dummy"] if args.rendered else ["--headless"]) + ["--path", str(project),
              "res://scenes/multiplayer/latency_integration_tests.tscn", "--",
              "--control=" + str(service.control_port), "--registrar=" + str(service.registrar_port),
              "--screenshots=" + args.screenshots]
    with tempfile.TemporaryDirectory(prefix="blackjack-latency-") as folder:
        logs = Path(folder)
        try:
            code = ""
            for role in ("host", "A"):
                handle = (logs / (role + ".log")).open("w")
                handles.append(handle)
                processes.append(await asyncio.create_subprocess_exec(
                    *prefix, "--role=" + role, "--code=" + code,
                    stdout=handle, stderr=asyncio.subprocess.STDOUT))
                if role == "host":
                    deadline = time.monotonic() + 12
                    while time.monotonic() < deadline:
                        for line in (logs / "host.log").read_text().splitlines():
                            if line.startswith("ONLINE ROOM CODE "):
                                code = line.removeprefix("ONLINE ROOM CODE ")
                        if code:
                            break
                        if processes[0].returncode is not None:
                            raise RuntimeError("Host could not start")
                        await asyncio.sleep(.1)
                    if not code:
                        raise RuntimeError("Host registration timed out")
            deadline = time.monotonic() + 65
            while any(p.returncode is None for p in processes):
                if any("ERROR:" in p.read_text() for p in logs.glob("*.log")):
                    raise RuntimeError("Peer reported an error")
                if time.monotonic() > deadline:
                    raise RuntimeError("Latency peers timed out")
                await asyncio.sleep(.1)
            for role, process in zip(("host", "A"), processes):
                content = (logs / (role + ".log")).read_text()
                print(content, end="")
                if process.returncode or "PASS:" not in content:
                    raise RuntimeError("Latency test failed: " + role)
            print("ALL MULTIPLAYER LATENCY TESTS PASSED (240ms added RTT)")
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
