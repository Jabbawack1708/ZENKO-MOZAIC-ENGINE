from pathlib import Path
from engine.profiles.registry import load_profile


def run(config: dict):
    engine = config["engine"]
    paths = config["paths"]

    profile_name = engine.get("profile", "")
    profile = load_profile(profile_name)

    print("=" * 50)
    print(f"Starting {engine['name']}")
    print(f"Version : {engine['version']}")
    print(f"Profile : {profile['name']}")
    print("=" * 50)

    for key, rel_path in paths.items():
        path = Path(rel_path)
        path.mkdir(parents=True, exist_ok=True)
        print(f"[OK] {key} directory -> {path.resolve()}")
