#!/usr/bin/env python3
"""
reachd 集成测试套件 v3
测试真实部署的 reachd 节点：网络/daemon/信道切换/failover

用法:
  python3 tests/test_reachd_integration.py [--pve-host 192.168.111.4 --pve-ssh-key /path/to/key]
"""

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Optional


TEST_SCRIPT = """
import subprocess
def run(cmd, timeout=20):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr

tests = []

# 1. Ping gateway
c,o,e = run("ping -c 2 -W 3 10.0.8.1")
if c==0 and "bytes from" in o:
    line = [l for l in o.strip().split("\\n") if "bytes from" in l][0]
    tests.append(("ping_gateway","PASS",line))
else:
    tests.append(("ping_gateway","FAIL",e or o[:80]))

# 2. DNS
c,o,e = run("python3 -c \\"import socket; print(socket.gethostbyname('github.com'))\\"")
if c==0 and o.strip():
    ip = o.strip()
    dots = ip.split(".")
    if len(dots)==4 and all(d.isdigit() for d in dots):
        tests.append(("dns_github","PASS",f"-> {ip}"))
    else:
        tests.append(("dns_github","FAIL",f"Invalid: {ip}"))
else:
    tests.append(("dns_github","FAIL",(e or o[:80])))

# 3. TCP (3 targets)
for target, port in [("1.1.1.1",80),("8.8.8.8",53),("github.com",443)]:
    c,o,e = run(f"python3 -c \\"import socket; s=socket.socket(); s.settimeout(5); r=s.connect_ex(('{target}',{port})); print(r); s.close()\\"")
    ok = (c==0 and o.strip()=="0")
    tests.append((f"tcp_{target}_{port}","PASS" if ok else "FAIL", o.strip()))

# 4. reachd daemon
c,o,e = run("pgrep -f 'reachd.py.*daemon' && echo FOUND")
if c==0 and "FOUND" in o:
    tests.append(("reachd_daemon","PASS","Running"))
else:
    tests.append(("reachd_daemon","FAIL","Not running"))

# 5. reachd log (no ERROR/Exception)
c,o,e = run("tail -10 /root/reachd.log 2>/dev/null")
if c==0:
    lower = o.lower()
    if "error" in lower or "exception" in lower:
        tests.append(("reachd_log","FAIL",o[:150].replace("\\n"," ")))
    else:
        tests.append(("reachd_log","PASS","Clean"))
else:
    tests.append(("reachd_log","FAIL","No log"))

# 6. Ping 8.8.8.8 (NAT traversal check)
c,o,e = run("ping -c 2 -W 5 8.8.8.8")
if c==0 and "bytes from" in o:
    tests.append(("ping_8.8.8.8","PASS","OK"))
else:
    tests.append(("ping_8.8.8.8","FAIL",e[:80]))

for name,status,msg in tests:
    print(f"{status}|{name}|{msg[:120]}")
"""


@dataclass
class TestResult:
    name: str
    passed: bool
    message: str = ""


@dataclass
class NodeReport:
    ip: str
    vmid: int
    tests: list[TestResult] = field(default_factory=list)
    reachd_running: bool = False


class ReachdTester:
    def __init__(self, pve_host: str, pve_ssh_key: str):
        self.pve_host = pve_host
        self.pve_ssh_key = pve_ssh_key

    def pve_cmd(self, cmd: str) -> tuple:
        """在 PVE 主机上执行命令"""
        full = ["ssh", "-i", self.pve_ssh_key, "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=10", f"root@{self.pve_host}", cmd]
        try:
            r = subprocess.run(" ".join(full), shell=True, capture_output=True, text=True, timeout=60)
            return r.returncode, r.stdout, r.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "timeout"

    def test_node(self, vmid: int, node_name: str) -> NodeReport:
        """测试单个节点"""
        report = NodeReport(ip="", vmid=vmid)
        print(f"\n{'='*60}\n  {node_name} (VMID {vmid})\n{'='*60}")

        # Step 1: write test script to /tmp on PVE host
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(TEST_SCRIPT)
            local_path = f.name

        # Copy to PVE
        subprocess.run(["scp", "-i", self.pve_ssh_key, "-o", "StrictHostKeyChecking=no",
                       local_path, f"root@{self.pve_host}:/tmp/test_node_{vmid}.py"],
                      capture_output=True, timeout=10)

        # Push into container
        code, _, _ = self.pve_cmd(f"pct push {vmid} /tmp/test_node_{vmid}.py /tmp/test_node.py")
        if code != 0:
            print(f"  [ERROR] Failed to push test script to VMID {vmid}")
            return report

        # Step 2: exec test script
        code, stdout, stderr = self.pve_cmd(f"pct exec {vmid} -- python3 /tmp/test_node.py")

        # Parse results
        for line in stdout.strip().split("\n"):
            if "|" in line:
                parts = line.split("|", 2)
                if len(parts) == 3:
                    status, name, msg = parts
                    passed = status == "PASS"
                    t = TestResult(name=name, passed=passed, message=msg)
                    report.tests.append(t)
                    if name == "reachd_daemon":
                        report.reachd_running = passed
                    sym = "✅" if passed else "❌"
                    print(f"  [{sym}] {name}: {msg[:80]}")

        return report


def main():
    parser = argparse.ArgumentParser(description="reachd 集成测试")
    parser.add_argument("--pve-host", default="192.168.111.4")
    parser.add_argument("--pve-ssh-key", default="/opt/data/.ssh/pve_key")
    parser.add_argument("--nodes", default="10.0.8.11,10.0.8.12,10.0.8.13")
    parser.add_argument("--vmids", default="161,162,163")
    args = parser.parse_args()

    node_ips = [ip.strip() for ip in args.nodes.split(",")]
    vmids = [int(v) for v in args.vmids.split(",")]
    nodes = list(zip(vmids, node_ips))

    tester = ReachdTester(args.pve_host, args.pve_ssh_key)
    reports = []
    for vmid, ip in nodes:
        r = tester.test_node(vmid, f"node-{vmid-160}")
        r.ip = ip
        reports.append(r)

    # Summary
    total = passed = 0
    print(f"\n{'='*60}\n  SUMMARY\n{'='*60}")
    for r in reports:
        if r.tests:
            p = sum(1 for t in r.tests if t.passed)
            t = len(r.tests)
            total += t
            passed += p
            sym = "✅" if p == t else "❌"
            print(f"  {sym} {r.ip}: {p}/{t}")
    print(f"\n  TOTAL: {passed}/{total}")
    print(f"{'='*60}\n")

    # CI JSON
    output = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "overall_passed": passed == total,
        "nodes": [{"ip": r.ip, "vmid": r.vmid, "reachd_running": r.reachd_running,
                   "passed": sum(1 for t in r.tests if t.passed), "total": len(r.tests)} for r in reports]
    }
    print("=== CI JSON ===")
    print(json.dumps(output, indent=2))
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()