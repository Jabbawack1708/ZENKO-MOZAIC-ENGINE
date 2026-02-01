from pathlib import Path

def run(config: dict):
    engine = config["engine"]
    paths = config["paths"]

    print("=" * 50)
    print(f"Starting {engine['name']}")
    print(f"Version : {engine['version']}")
    print(f"Profile : {engine['profile']}")
    print("=" * 50)

    for key, rel_path in paths.items():
        path = Path(rel_path)
        path.mkdir(parents=True, exist_ok=True)
        print(f"[OK] {key} directory -> {path.resolve()}")
