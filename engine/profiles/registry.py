import importlib


PROFILE_MODULES = {
    "PREMIUM_SUBJECT_FOCUS": "engine.profiles.premium_subject_focus",
}


def load_profile(name: str) -> dict:
    name = (name or "").strip()
    if name not in PROFILE_MODULES:
        raise ValueError(f"Unknown profile '{name}'. Available: {list(PROFILE_MODULES.keys())}")

    module_path = PROFILE_MODULES[name]
    module = importlib.import_module(module_path)

    if not hasattr(module, "PROFILE"):
        raise ValueError(f"Profile module '{module_path}' has no PROFILE dict")

    return module.PROFILE
