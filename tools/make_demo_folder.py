#!/usr/bin/env python3
"""Generate a neutral demo folder for screenshots of Disk Inventory Xs.

Every file is a sparse file: it has a believable name and a logical size of
several MB to GB but occupies (almost) no disk space, so a "disk" of tens of
gigabytes costs nothing and holds no private data. Turn "Show Physical File
Size" off in the app (View menu) to see the logical sizes, which is what the
screenshots show.

usage: tools/make_demo_folder.py DEST     (DEST must not exist or must be empty)
"""
import os
import random
import sys

MB = 1024 * 1024
GB = 1024 * MB


def sparse(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.truncate(int(size))


def build(root):
    rng = random.Random(2026)

    def jitter(low, high):
        return rng.uniform(low, high)

    # Movies: the big, colorful part of the map
    for i in range(1, 9):
        sparse(f"{root}/Movies/Lectures/lecture-{i:02d}.mp4", jitter(420, 900) * MB)
    for i in range(1, 6):
        sparse(f"{root}/Movies/Holiday 2025/clip-{i:02d}.mov", jitter(600, 1500) * MB)
    for i in range(1, 7):
        sparse(f"{root}/Movies/Trailers/trailer-{i:02d}.mp4", jitter(60, 220) * MB)
    sparse(f"{root}/Movies/Family archive.mov", 3.4 * GB)

    # Photos: many mid-size files
    for i in range(1, 160):
        sparse(f"{root}/Photos/2025/IMG_{i:04d}.heic", jitter(2, 6) * MB)
    for i in range(1, 40):
        sparse(f"{root}/Photos/RAW/DSC_{i:04d}.dng", jitter(22, 34) * MB)
    for i in range(1, 90):
        sparse(f"{root}/Photos/Screenshots/Screenshot {i}.png", jitter(0.4, 3) * MB)
    for i in range(1, 45):
        sparse(f"{root}/Photos/Exports/export-{i:03d}.jpg", jitter(1, 5) * MB)

    # Music
    for album in ("Blue Hour", "Night Drive", "Small Rooms", "Long Way Home"):
        for track in range(1, 13):
            ext = "m4a" if album in ("Blue Hour", "Night Drive") else "mp3"
            sparse(f"{root}/Music/{album}/{track:02d} Track.{ext}", jitter(4, 11) * MB)

    # Downloads: installers and disk images
    sparse(f"{root}/Downloads/macOS Installer.dmg", 13.2 * GB)
    sparse(f"{root}/Downloads/Design Tools.dmg", 2.1 * GB)
    sparse(f"{root}/Downloads/Editor-5.2.pkg", 1.4 * GB)
    sparse(f"{root}/Downloads/dataset.zip", 3.8 * GB)
    sparse(f"{root}/Downloads/linux.iso", 2.6 * GB)
    for i in range(1, 12):
        sparse(f"{root}/Downloads/archive-{i:02d}.zip", jitter(40, 320) * MB)
    for i in range(1, 8):
        sparse(f"{root}/Downloads/update-{i}.pkg", jitter(80, 600) * MB)

    # Projects: lots of small files and a few build products
    for pkg in range(1, 7):
        for i in range(1, 70):
            sparse(f"{root}/Projects/web-app/node_modules/package-{pkg}/lib/module-{i:03d}.js", jitter(0.004, 0.08) * MB)
    for i in range(1, 60):
        sparse(f"{root}/Projects/mobile-app/Sources/File{i:03d}.swift", jitter(0.002, 0.04) * MB)
    for i in range(1, 25):
        sparse(f"{root}/Projects/mobile-app/Assets/image-{i:02d}.png", jitter(0.1, 1.5) * MB)
    sparse(f"{root}/Projects/mobile-app/build/App.app.zip", 480 * MB)
    sparse(f"{root}/Projects/web-app/dist/bundle.js", 38 * MB)
    sparse(f"{root}/Projects/notes.json", 6 * MB)
    for i in range(1, 5):
        sparse(f"{root}/Projects/data/export-{i}.json", jitter(80, 260) * MB)

    # Documents
    for i in range(1, 70):
        sparse(f"{root}/Documents/Papers/paper-{i:02d}.pdf", jitter(0.3, 14) * MB)
    for i in range(1, 30):
        sparse(f"{root}/Documents/Reports/report-{i:02d}.docx", jitter(0.1, 2.5) * MB)
    for i in range(1, 15):
        sparse(f"{root}/Documents/Budgets/budget-{i:02d}.xlsx", jitter(0.1, 3.5) * MB)

    # Backups
    sparse(f"{root}/Backups/laptop-2025.dmg", 7.4 * GB)
    sparse(f"{root}/Backups/laptop-2024.dmg", 6.1 * GB)
    for i in range(1, 6):
        sparse(f"{root}/Backups/phone-backup-{i}.zip", jitter(700, 1900) * MB)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    dest = os.path.abspath(sys.argv[1])
    if os.path.exists(dest) and os.listdir(dest):
        sys.exit(f"{dest} is not empty")
    build(dest)
    total = 0
    count = 0
    for folder, _, files in os.walk(dest):
        for name in files:
            total += os.path.getsize(os.path.join(folder, name))
            count += 1
    print(f"{dest}: {count} files, {total / GB:.1f} GB logical")


main()
