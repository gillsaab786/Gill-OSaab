import importlib.machinery
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYSTEM = ROOT / "files" / "system"
sys.path.insert(0, str(SYSTEM / "usr/libexec/gill-osaab"))


def load(relpath, name=None):
    """Import an extension-less script from files/system as a module."""
    path = SYSTEM / relpath
    name = name or path.name.replace("-", "_")
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def which_only(*tools):
    return lambda t: f"/usr/bin/{t}" if t in tools else None


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
