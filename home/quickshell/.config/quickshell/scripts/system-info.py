#!/usr/bin/env python3
"""What this computer is, for "Über diesen Computer" and System Settings → Allgemein → Info:
JSON with the computer, its parts and the versions of the system. Read without root.

    system-info.py          JSON
    system-info.py --text   the same as text, for "Bericht kopieren"
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path


def run(*argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def pkg_version(name):
    out = run("pacman", "-Q", name)
    return out.split()[1] if out.count(" ") == 1 else ""


def cpu():
    model = next((l.split(":", 1)[1].strip() for l in read("/proc/cpuinfo").splitlines() if l.startswith("model name")), "")
    threads = os.cpu_count() or 0
    cores = len({l for l in read("/proc/cpuinfo").splitlines() if l.startswith("core id")}) or threads
    return f"{model} ({cores} Kerne, {threads} Threads)" if model else ""


def gpus():
    found = []
    for line in run("lspci", "-mm").splitlines():
        parts = re.findall(r'"([^"]*)"', line)
        if len(parts) >= 3 and re.search(r"VGA|3D|Display", parts[0]):
            vendor, name = parts[1], parts[2]
            short = "AMD" if vendor.startswith("Advanced Micro") else vendor.split()[0]
            found.append(f"{short} {name}".replace("[", "").replace("]", ""))
    nvidia = run("nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader")
    names = []
    for g in found:
        if "NVIDIA" in g.upper() and nvidia:
            name, version = [p.strip() for p in nvidia.splitlines()[0].split(",", 1)]
            names.append(f"{name} (Treiber {version})")
        else:
            mesa = pkg_version("mesa")
            names.append(f"{g} (Mesa {mesa.split('-')[0]})" if mesa and "AMD" in g.upper() else g)
    return names


def memory():
    kb = next((int(l.split()[1]) for l in read("/proc/meminfo").splitlines() if l.startswith("MemTotal")), 0)
    return f"{round(kb / 1024 / 1024)} GB" if kb else ""


def displays():
    try:
        mons = json.loads(run("hyprctl", "monitors", "-j") or "[]")
    except ValueError:
        return []
    return [f"{m.get('make', '')} {m.get('model', '')}".strip() + f" – {m['width']}×{m['height']}, {round(m['refreshRate'])} Hz"
            for m in mons]


def disks():
    try:
        devs = json.loads(run("lsblk", "-J", "-d", "-o", "NAME,MODEL,SIZE,TYPE,TRAN") or "{}").get("blockdevices", [])
    except ValueError:
        return []
    return [f"{(d.get('model') or d['name']).strip()} ({d['size'].replace('G', ' GB').replace('T', ' TB')})"
            for d in devs if d.get("type") == "disk" and not d["name"].startswith(("zram", "loop"))]


def model():
    vendor, product = read("/sys/class/dmi/id/sys_vendor"), read("/sys/class/dmi/id/product_name")
    board = " ".join(x for x in (read("/sys/class/dmi/id/board_vendor"), read("/sys/class/dmi/id/board_name")) if x)
    generic = {"", "To Be Filled By O.E.M.", "System Product Name", "Default string"}
    name = f"{vendor} {product}".strip() if product not in generic else ""
    return name or board


def uptime():
    seconds = int(float(read("/proc/uptime").split()[0] or 0))
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    return (f"{days} T. " if days else "") + f"{hours} Std. {rest // 60} Min."


def info():
    os_release = dict(re.findall(r'^(\w+)="?([^"\n]*)"?$', read("/etc/os-release"), re.M))
    try:
        hypr = json.loads(run("hyprctl", "version", "-j") or "{}").get("tag", "")
    except ValueError:
        hypr = ""
    riptide = run("git", "-C", str(Path.home() / "dotfiles"), "log", "-1", "--format=%h vom %cd", "--date=format:%d.%m.%Y")
    return {
        "name": read("/proc/sys/kernel/hostname"),
        "system": os_release.get("PRETTY_NAME", "Linux") + " · riptide",
        "rows": [
            ["Computer", model()],
            ["Prozessor", cpu()],
            ["Grafik", ", ".join(gpus())],
            ["Arbeitsspeicher", memory()],
            ["Laufwerke", ", ".join(disks())],
            ["Bildschirme", ", ".join(displays())],
            ["Kernel", run("uname", "-r")],
            ["Hyprland", hypr],
            ["Quickshell", pkg_version("quickshell")],
            ["riptide", riptide],
            ["Eingeschaltet seit", uptime()],
        ],
    }


def main():
    data = info()
    data["rows"] = [r for r in data["rows"] if r[1]]
    if sys.argv[1:] == ["--text"]:
        print(f"{data['name']} – {data['system']}")
        for label, value in data["rows"]:
            print(f"{label}: {value}")
    else:
        print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
