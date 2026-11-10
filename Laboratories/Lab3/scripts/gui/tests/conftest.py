"""Configuracion comun de los tests del depurador (pytest).

* Agrega scripts/ y scripts/gui/ al path (rutas.py).
* La interfaz corre sin pantalla (QT_QPA_PLATFORM=offscreen).
* El log va a una carpeta temporal, no a ~/.local/state.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import pytest  # noqa: E402

import rutas  # noqa: E402,F401


@pytest.fixture(autouse=True)
def log_temporal(tmp_path, monkeypatch):
    monkeypatch.setenv("TP_RISCV_LOG_DIR", str(tmp_path / "logs"))
