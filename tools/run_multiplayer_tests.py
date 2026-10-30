"""Run three real Godot peers on loopback, then verify an unreachable-host timeout."""
import argparse
import pathlib
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7 executable path")
    args = parser.parse_args()
    project = pathlib.Path(__file__).resolve().parents[1]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    # Keep child processes in one parent/network environment and always clean them up.
    with tempfile.TemporaryDirectory(prefix="blackjack-network-tests-") as folder:
        logs = pathlib.Path(folder)
        processes = []
        handles = []
        try:
            for role in ("host", "A", "B"):
                handle = (logs / (role + ".log")).open("w", encoding="utf-8")
                handles.append(handle)
                command = [args.godot, "--headless", "--path", str(project),
                           "res://scenes/multiplayer/network_tests.tscn", "--",
                           "--role=" + role, "--port=" + str(port)]
                processes.append(subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT))
                if role == "host":
                    time.sleep(0.5)
            for process in processes:
                process.wait(timeout=48)
            failed = False
            for role, process in zip(("host", "A", "B"), processes):
                content = (logs / (role + ".log")).read_text(encoding="utf-8")
                print(content, end="")
                if process.returncode != 0 or "ERROR:" in content or "PASS:" not in content:
                    failed = True
            if failed:
                raise RuntimeError("One or more multiplayer peers failed.")
            # All peers are closed, so the same port is now unreachable.
            command = [args.godot, "--headless", "--path", str(project),
                       "res://scenes/multiplayer/network_tests.tscn", "--",
                       "--role=failed", "--port=" + str(port)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=14)
            content = result.stdout + result.stderr
            print(content, end="")
            if result.returncode != 0 or "ERROR:" in content or "PASS:" not in content:
                raise RuntimeError("Unreachable-host test failed.")
            # Unlike Leave Room, a killed process cannot send a graceful disconnect.
            crash_host_log = (logs / "crash_host.log").open("w", encoding="utf-8")
            crash_guest_log = (logs / "crash_guest.log").open("w", encoding="utf-8")
            handles.extend([crash_host_log, crash_guest_log])
            prefix = [args.godot, "--headless", "--path", str(project),
                      "res://scenes/multiplayer/network_tests.tscn", "--", "--port=" + str(port)]
            crash_host = subprocess.Popen(prefix + ["--role=crash_host"], stdout=crash_host_log, stderr=subprocess.STDOUT)
            processes.append(crash_host)
            time.sleep(0.5)
            crash_guest = subprocess.Popen(prefix + ["--role=crash"], stdout=crash_guest_log, stderr=subprocess.STDOUT)
            processes.append(crash_guest)
            for attempt in range(60):
                content = (logs / "crash_guest.log").read_text(encoding="utf-8")
                if "CRASH GUEST READY" in content:
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("Crash-test guest did not connect.")
            crash_host.kill()
            crash_host.wait()
            crash_guest.wait(timeout=10)
            content = (logs / "crash_guest.log").read_text(encoding="utf-8")
            print(content, end="")
            if crash_guest.returncode != 0 or "ERROR:" in content or "PASS:" not in content:
                raise RuntimeError("Abrupt host shutdown test failed.")
            print("ALL MULTIPLAYER ROOM TESTS PASSED")
        except Exception:
            for path in sorted(logs.glob("*.log")):
                print(path.name + ":\n" + path.read_text(encoding="utf-8"))
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
