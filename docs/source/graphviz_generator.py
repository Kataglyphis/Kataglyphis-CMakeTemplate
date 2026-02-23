import re
from pathlib import Path

STATIC_DIR = Path("_static")
OUTPUT_FILE = Path("graphviz_files.rst")

ALLOWED_KEYWORDS = ("__incl", "_dep", "_cgraph", "_icgraph")
EXCLUDED_BASENAMES = {
    "doc",
    "docd",
    "doxygen",
    "folderclosed",
    "folderclosedd",
    "folderopen",
    "folderopend",
    "graph_legend",
    "minus",
    "minusd",
    "plus",
    "plusd",
}


def normalize_title(filename: str) -> str:
    stem = Path(filename).stem
    stem = stem.replace("_8", ".")
    stem = re.sub(r"_+", " ", stem)
    stem = re.sub(r"\s+", " ", stem).strip()
    return stem[:1].upper() + stem[1:] if stem else filename


def graphviz_key(filename: str) -> tuple[str, str]:
    stem = Path(filename).stem.lower()
    if "_icgraph" in stem:
        kind = "4_callers"
    elif "_cgraph" in stem:
        kind = "3_calls"
    elif "_dep" in stem:
        kind = "2_dependency"
    elif "__incl" in stem:
        kind = "1_include"
    else:
        kind = "9_other"
    return kind, stem


def is_relevant_svg(path: Path) -> bool:
    stem_lower = path.stem.lower()
    if stem_lower in EXCLUDED_BASENAMES:
        return False
    return any(keyword in stem_lower for keyword in ALLOWED_KEYWORDS)


svg_files = sorted(
    [file.name for file in STATIC_DIR.glob("*.svg") if is_relevant_svg(file)],
    key=graphviz_key,
)

with OUTPUT_FILE.open("w", encoding="utf-8") as out:
    out.write("Graphviz Diagrams\n")
    out.write("=================\n\n")
    out.write(
        "Filtered and grouped dependency/call/include diagrams generated from Doxygen output.\n\n"
    )

    if not svg_files:
        out.write(".. note:: No relevant Graphviz SVG files found in `_static`.\n")
    else:
        out.write(".. dropdown:: Show Graphviz diagrams\n")
        out.write("   :open:\n\n")
        out.write("   .. grid:: 1\n")
        out.write("      :gutter: 2\n\n")

        for svg in svg_files:
            title = normalize_title(svg)
            out.write(f"      .. grid-item-card:: {title}\n")
            out.write("         :class-card: sd-shadow-sm\n")
            out.write(f"         :link: _static/{svg}\n")
            out.write(f"         :img-top: _static/{svg}\n\n")
            out.write("         Open full-size SVG\n\n")
