"""Run deterministic table flows, then Classic Blackjack over three and four real ENet peers."""
import argparse
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    prefix = [args.godot, "--headless", "--path", str(project)]
    for scene, marker in [("classic_table_tests", "ALL SHARED CLASSIC TABLE TESTS PASSED"),
                          ("special_table_tests", "ALL SHARED SPECIAL RULE TESTS PASSED"),
                          ("table_session_tests", "ALL MULTIPLAYER SESSION ENGINE TESTS PASSED")]:
        result = subprocess.run(prefix + ["res://scenes/multiplayer/" + scene + ".tscn"],
                                text=True, capture_output=True, timeout=15)
        content = result.stdout + result.stderr
        print(content, end="")
        if result.returncode or "ERROR:" in content or marker not in content:
            raise RuntimeError("Deterministic table flows failed: " + scene)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    run_peers(prefix, port, "res://scenes/multiplayer/table_integration_tests.tscn", ("host", "A", "B"))
    run_peers(prefix, port, "res://scenes/multiplayer/table_presentation_tests.tscn", ("host", "A", "B", "C"))
    run_peers(prefix, port, "res://scenes/multiplayer/special_table_integration_tests.tscn", ("host", "A", "B", "C"))
    print("ALL MULTIPLAYER CLASSIC AND FOUR-PLAYER PRESENTATION TESTS PASSED")
    print("ALL MULTIPLAYER SPECIAL RULE TESTS PASSED")
    run_peers(prefix, port, "res://scenes/multiplayer/table_session_integration_tests.tscn", ("host", "A", "B", "C"))
    print("ALL MULTIPLAYER SESSION TESTS PASSED")


def run_peers(prefix, port, scene, roles):
    with tempfile.TemporaryDirectory(prefix="blackjack-table-tests-") as folder:
        logs = Path(folder)
        processes = []
        handles = []
        try:
            for role in roles:
                handle = (logs / (role + ".log")).open("w", encoding="utf-8")
                handles.append(handle)
                processes.append(subprocess.Popen(
                    prefix + [scene, "--",
                              "--role=" + role, "--port=" + str(port)],
                    stdout=handle, stderr=subprocess.STDOUT))
                if role == "host":
                    time.sleep(0.5)
            for process in processes:
                process.wait(timeout=70)
            failed = False
            for role, process in zip(roles, processes):
                content = (logs / (role + ".log")).read_text(encoding="utf-8")
                print(content, end="")
                failed |= process.returncode != 0 or "ERROR:" in content or "PASS:" not in content
            if failed:
                raise RuntimeError("Shared table RPC tests failed.")
            print("ALL MULTIPLAYER CLASSIC TESTS PASSED")
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
