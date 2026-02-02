"""
Profile: PREMIUM_SUBJECT_FOCUS

Intent (V1):
- Keep the center (faces) highly readable.
- Let tiles be more present toward the edges.
- Prefer stability and predictability over cleverness.
"""

PROFILE = {
    "name": "PREMIUM_SUBJECT_FOCUS",

    "output": {
        "width": 3840,
        "height": 2160,
    },

    "tiles": {
        "size": 48,
        "max": 800,
        "allow_reuse": True,
        "seed": 123,
    },

    "blend": {
        "alpha_center": 0.04,
        "alpha_edge": 0.18,
        "feather": 0.22,
        "center_x": 0.50,
        "center_y": 0.45,
        "ellipse_rx": 0.28,
        "ellipse_ry": 0.34,
    },
}
