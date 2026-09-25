"""All ThinkShift backend constants and config (env values read from .env)."""

import os

from dotenv import load_dotenv
from agora_agent import Area

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

# ── Server ───────────────────────────────────────────────────────────────
SERVER_HOST = "0.0.0.0"
SERVER_PORT = 8001

# ── Agora credentials ────────────────────────────────────────────────────
AGORA_APP_ID   = os.environ.get("AGORA_APP_ID",   "your-agora-app-id")
AGORA_APP_CERT = os.environ.get("AGORA_APP_CERT", "your-agora-app-certificate")

# Only used by the /stop-agent fallback when the session isn't in memory.
AGORA_CUSTOMER_ID     = os.environ.get("AGORA_CUSTOMER_ID",     "your-customer-id")
AGORA_CUSTOMER_SECRET = os.environ.get("AGORA_CUSTOMER_SECRET", "your-customer-secret")

AGORA_AREA = os.environ.get("AGORA_AREA", "US").strip().upper()
AREA_BY_NAME = {
    "NORTH_AMERICA": Area.US, "US": Area.US,
    "EUROPE": Area.EU, "EU": Area.EU,
    "ASIA_PACIFIC": Area.AP, "AP": Area.AP,
    "CHINA": Area.CN, "CN": Area.CN,
}

AGORA_API_BASE_URL = "https://api.agora.io/api/conversational-ai-agent/v2"

# ── Models (defaults match the template's managed models) ────────────────
ASR_MODEL    = os.environ.get("SDK_ASR_MODEL", "nova-3")
ASR_LANGUAGE = os.environ.get("ASR_LANGUAGE", "en")
LLM_MODEL    = os.environ.get("SDK_LLM_MODEL", "gpt-4o-mini")
TTS_MODEL    = os.environ.get("SDK_TTS_MODEL", "speech-2.8-turbo")
TTS_VOICE_ID = os.environ.get("SDK_TTS_VOICE_ID", "English_radiant_girl")

# ── Agent / session ──────────────────────────────────────────────────────
AGENT_UID = 999
TOKEN_EXPIRY_SECONDS = 3600
RTC_ROLE_PUBLISHER = 1
AGENT_IDLE_TIMEOUT_SECONDS = 60

# ── Timeouts ─────────────────────────────────────────────────────────────
SDK_CALL_TIMEOUT_SECONDS = 60
HTTPX_TIMEOUT_SECONDS = 60.0
REST_STOP_TIMEOUT_SECONDS = 15

# ── Audio ────────────────────────────────────────────────────────────────
# "chorus" is the template's setting: tuned for AI-agent voice (echo/noise
# handling), better than the RTC default for a phone mic + speaker.
AUDIO_SCENARIO = "chorus"

# ── Filler words (spoken while the LLM is still thinking) ────────────────
FILLER_WAIT_MS = 1500
FILLER_PHRASES = [
    "Hmm, let me think.",
    "Good question, one moment.",
    "Let me think about that.",
    "Just a second.",
]
FILLER_PROMPT = (
    "Briefly and warmly acknowledge that you are thinking about the student's "
    "question, in the same language they used. Do not answer it yet."
)

# ── Turn detection / VAD ─────────────────────────────────────────────────
VAD_SPEECH_THRESHOLD = 0.5
VAD_INTERRUPT_DURATION_MS = 160
VAD_PREFIX_PADDING_MS = 800
VAD_SILENCE_DURATION_MS = 640

# ── LLM tuning ───────────────────────────────────────────────────────────
LLM_MAX_HISTORY = 15
LLM_MAX_TOKENS = 1024
LLM_TEMPERATURE = 0.4
LLM_TOP_P = 0.95

# ── Prompts ──────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are ThinkShift, a friendly voice-based learning companion for students.

You are speaking out loud in a live, real-time voice conversation.

PURPOSE
Help students explore General Knowledge, Science, History, Geography, Space, Environment, and everyday “why” questions through short, engaging conversations.

LANGUAGE
- Reply in the SAME language the student is speaking.
- If the student speaks Marathi, reply in natural, simple Marathi.
- If the student speaks Hindi, reply in natural, simple Hindi.
- If the student speaks English, reply in simple, natural English.
- Do not unnecessarily mix languages.

VOICE STYLE
- Speak naturally and warmly, like a curious learning companion.
- Keep responses SHORT — ideally 1–3 sentences and under 25 seconds.
- Never give long lectures or read long lists.
- Use simple examples and real-world situations.
- Do not output JSON, code, field names, or formatting in spoken replies.

THE QUESTION RULE (most important — check it before every reply)
Look at YOUR previous reply.
- If your previous reply asked the student a question, then THIS reply must contain NO question at all. No question mark. Not even “Want to explore another topic?” or “Does that make sense?”.
  Instead: praise their thinking in a few words, give the correct key idea in one or two sentences, and stop. Then stay silent and let the student lead.
- If your previous reply did NOT ask a question, you MAY end this reply with ONE short “why”, “what if”, or “what do you think?” question — but only if the topic is interesting to think about. Simple factual questions (dates, names, numbers, definitions) get a direct answer and NO question.

So a topic never has more than one question from you. Never ask two questions in a row, and never ask two questions in one reply.

HOW A TOPIC GOES
Student asks → you answer briefly (optionally ending with one thinking question) → student replies → you acknowledge, explain the key idea, and stop with no question.

Only continue the same topic if the student clearly asks for more. If the student asks something new, it is a new topic and the rule starts fresh.

EXAMPLE
Student: Why is the sky blue?
You: Sunlight has all colours, but the air scatters blue light the most, so blue reaches our eyes from every direction. What colour do you think the sky would be with no air at all?
Student: Maybe black?
You: Exactly right! With no air to scatter light, the sky looks black — that is what astronauts see from the Moon.
(No question here. Wait for the student.)

START
Greet warmly and invite the student to ask anything."""

GREETING = ("Hi! I’m ThinkShift. Ready to explore something interesting? Ask me any question!")
# " your learning companion. Ask me anything about science, "
#             "history, geography, space, or the world around you — what would you like "
#             "to explore today?")

FAILURE = "Sorry, please hold on a second."
