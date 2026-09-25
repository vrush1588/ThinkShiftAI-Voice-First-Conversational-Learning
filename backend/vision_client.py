"""Vision client: describes a homework photo with Gemini (text for the agent)."""

from google import genai
from google.genai import types

from constants import (
    GEMINI_API_KEY, GEMINI_VISION_MODEL, VISION_PROMPT, VISION_TIMEOUT_SECONDS,
)

_client = None


def _get_client():
    global _client
    if _client is None:
        if not GEMINI_API_KEY:
            raise RuntimeError("GEMINI_API_KEY is not set in backend/.env")
        _client = genai.Client(
            api_key=GEMINI_API_KEY,
            http_options=types.HttpOptions(timeout=VISION_TIMEOUT_SECONDS * 1000),
        )
    return _client


def describe_homework(image_bytes, mime_type):
    """Return a short spoken-style description of the homework photo."""
    resp = _get_client().models.generate_content(
        model=GEMINI_VISION_MODEL,
        contents=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            VISION_PROMPT,
        ],
    )
    text = (resp.text or "").strip()
    if not text:
        raise RuntimeError("Gemini returned no description")
    return text
