"""Exercise real multiplayer toys and bet focus, including a guest who joins mid-carry."""
import argparse
import pathlib
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--physics", action="store_true", help="Run fast-catch and player-throw cases")
    args = parser.parse_args()
    project = pathlib.Path(__file__).resolve().parents[1]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    prefix = [args.godot, "--headless", "--path", str(project),
              ("res://scenes/multiplayer/toy_physics_tests.tscn" if args.physics else "res://scenes/multiplayer/toy_integration_tests.tscn"), "--", "--port=" + str(port)]
    with tempfile.TemporaryDirectory(prefix="blackjack-toys-") as folder:
        logs = pathlib.Path(folder)
        processes, handles = [], []
        try:
            for role in ("host", "A", "late"):
                if role == "late":
                    deadline = time.monotonic() + 20
                    while "TOY LATE JOIN READY" not in (logs / "host.log").read_text():
                        if processes[0].poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError("Host did not reach late join test")
                        time.sleep(.1)
                handle = (logs / (role + ".log")).open("w")
                handles.append(handle)
                processes.append(subprocess.Popen(prefix + ["--role=" + role], stdout=handle, stderr=subprocess.STDOUT))
                if role == "host":
                    time.sleep(.5)
            deadline = time.monotonic() + 65
            while any(process.poll() is None for process in processes):
                if any("ERROR:" in path.read_text() for path in logs.glob("*.log")):
                    raise RuntimeError("Peer reported an error")
                if time.monotonic() > deadline:
                    raise RuntimeError("Toy peers timed out")
                time.sleep(.1)
            for role, process in zip(("host", "A", "late"), processes):
                content = (logs / (role + ".log")).read_text()
                print(content, end="")
                if process.returncode or "ERROR:" in content or "PASS:" not in content:
                    raise RuntimeError("Toy test failed: " + role)
            print("ALL MULTIPLAYER TOY TESTS PASSED")
        except Exception:
            for path in logs.glob("*.log"):
                print(path.name + ":\n" + path.read_text())
            raise
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            for handle in handles:
                handle.close()


if __name__ == "__main__":
    main()
