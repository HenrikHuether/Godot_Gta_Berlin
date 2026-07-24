#!/usr/bin/env python3

import pathlib
import shutil
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox


OUTPUT_PATH = pathlib.Path(
    "/home/hhuether/Godot_Gta_Berlin/Assets/Maps/"
    "Berlin_Segmentiert_EinzelneHaeuser.glb"
)


def choose_blend_file() -> pathlib.Path | None:
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    selected_file = filedialog.askopenfilename(
        title="Blender-Datei auswählen",
        initialdir="/home/hhuether/GTA_Berlin_Maps/Berlin",
        filetypes=[
            ("Blender-Dateien", "*.blend"),
            ("Alle Dateien", "*.*"),
        ],
    )

    root.destroy()

    if not selected_file:
        return None

    return pathlib.Path(selected_file).resolve()


def show_error(message: str) -> None:
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    messagebox.showerror("Export fehlgeschlagen", message)
    root.destroy()


def show_success(message: str) -> None:
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    messagebox.showinfo("Export erfolgreich", message)
    root.destroy()


def main() -> int:
    blend_file = choose_blend_file()

    if blend_file is None:
        print("Keine Datei ausgewählt. Export abgebrochen.")
        return 0

    if not blend_file.is_file():
        show_error(f"Die Datei existiert nicht:\n{blend_file}")
        return 1

    blender_executable = shutil.which("blender")

    if blender_executable is None:
        show_error(
            "Blender wurde nicht gefunden.\n\n"
            "Prüfe mit:\n"
            "blender --version"
        )
        return 1

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    python_expression = (
        "import bpy; "
        "bpy.ops.export_scene.gltf("
        f"filepath={str(OUTPUT_PATH)!r}, "
        "export_format='GLB'"
        ")"
    )

    command = [
        blender_executable,
        "--background",
        str(blend_file),
        "--python-exit-code",
        "1",
        "--python-expr",
        python_expression,
    ]

    print("=" * 70)
    print("Blender GLB Export")
    print("=" * 70)
    print(f"Blend-Datei: {blend_file}")
    print(f"GLB-Ausgabe: {OUTPUT_PATH}")
    print("=" * 70)

    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as error:
        show_error(
            "Blender konnte die Datei nicht exportieren.\n\n"
            f"Exit-Code: {error.returncode}\n"
            "Weitere Details stehen im Terminal."
        )
        return error.returncode or 1

    if not OUTPUT_PATH.is_file():
        show_error(
            "Blender wurde ohne gemeldeten Fehler beendet, "
            "aber die GLB-Datei wurde nicht erstellt."
        )
        return 1

    show_success(
        "Die Blender-Datei wurde erfolgreich exportiert:\n\n"
        f"{OUTPUT_PATH}"
    )

    print(f"Export erfolgreich: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())