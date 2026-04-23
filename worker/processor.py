"""Image transformations using Pillow.

Each function takes raw image bytes and returns (variant_name, output_bytes).
All processing is done in memory — no temp files — which is faster and
avoids filesystem permission issues in containers.
"""
import io
import logging
from typing import Tuple

from PIL import Image, ImageFilter

logger = logging.getLogger(__name__)


def _load_image(image_bytes: bytes) -> Image.Image:
    """Load bytes into a Pillow Image, converting to RGB if necessary."""
    img = Image.open(io.BytesIO(image_bytes))
    # Convert to RGB so JPEG output always works (PNG with alpha would fail)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    return img


def _to_jpeg_bytes(img: Image.Image, quality: int = 85) -> bytes:
    """Serialize a Pillow Image to JPEG bytes."""
    buf = io.BytesIO()
    # Ensure RGB for JPEG output (grayscale images can be "L" and that's fine too)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    img.save(buf, format="JPEG", quality=quality, optimize=True)
    return buf.getvalue()


def make_thumbnail(image_bytes: bytes, size: int = 150) -> Tuple[str, bytes]:
    """150x150 square thumbnail (preserves aspect ratio, fits within box)."""
    img = _load_image(image_bytes)
    img.thumbnail((size, size), Image.Resampling.LANCZOS)
    return "thumbnail", _to_jpeg_bytes(img)


def make_medium(image_bytes: bytes, width: int = 800) -> Tuple[str, bytes]:
    """Resize to a given width, keeping aspect ratio."""
    img = _load_image(image_bytes)
    w, h = img.size
    if w > width:
        new_h = int(h * (width / w))
        img = img.resize((width, new_h), Image.Resampling.LANCZOS)
    return "medium", _to_jpeg_bytes(img)


def make_grayscale(image_bytes: bytes) -> Tuple[str, bytes]:
    """Convert to grayscale."""
    img = _load_image(image_bytes)
    img = img.convert("L")
    return "grayscale", _to_jpeg_bytes(img)


def make_blur(image_bytes: bytes, radius: int = 5) -> Tuple[str, bytes]:
    """Apply a Gaussian blur."""
    img = _load_image(image_bytes)
    img = img.filter(ImageFilter.GaussianBlur(radius=radius))
    return "blur", _to_jpeg_bytes(img)


def make_edges(image_bytes: bytes) -> Tuple[str, bytes]:
    """Edge detection filter."""
    img = _load_image(image_bytes)
    img = img.convert("L").filter(ImageFilter.FIND_EDGES)
    return "edges", _to_jpeg_bytes(img)


# Registry: maps operation name (from SQS message) to a processor function.
OPERATIONS = {
    "thumbnail": make_thumbnail,
    "medium": make_medium,
    "grayscale": make_grayscale,
    "blur": make_blur,
    "edges": make_edges,
}


def process_operation(op_name: str, image_bytes: bytes) -> Tuple[str, bytes]:
    """Dispatch to the right processor. Raises KeyError on unknown op."""
    if op_name not in OPERATIONS:
        raise KeyError(f"Unknown operation: {op_name}")
    logger.info("Running operation: %s", op_name)
    return OPERATIONS[op_name](image_bytes)
