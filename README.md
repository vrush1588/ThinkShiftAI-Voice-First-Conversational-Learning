# 🎙️ ThinkShift AI

### Voice-first AI learning companion for students

**ThinkShift AI** is a voice-powered learning companion that makes learning feel like a conversation.

Instead of typing questions into a chatbot, students **talk to ThinkShift AI**. They ask "why" questions, get short spoken answers, and are nudged to think for themselves, all in a live voice conversation.

Built for the **Agora Voice AI Hackathon by AI Mobile Coders**, powered by **Agora Conversational AI**.

---

## 🎬 Demo

[![ThinkShift AI demo video](https://img.youtube.com/vi/e1_AwnC8GOs/hqdefault.jpg)](https://youtu.be/e1_AwnC8GOs)

▶️ **Watch on YouTube:** https://youtu.be/e1_AwnC8GOs

---

## 💡 The Idea

Learning is often treated as a text-based experience:

> Read → Type → Search → Read → Repeat

ThinkShift AI explores a different approach:

> **Ask → Talk → Think → Understand**

A student taps one button, speaks their question, and has a natural back-and-forth with an AI companion.

The goal is not just to add a microphone to a chatbot, but to make **voice the primary interaction layer**.

---

## ✨ Key Features

* 🎙️ **Real-time voice conversation**: one tap to talk, powered by Agora RTC and Conversational AI
* 🧠 **Thinks with the student**: short answers (1–3 sentences), with at most **one** "why / what if / what do you think?" question per topic, never an endless quiz
* ✋ **Natural interruptions**: the student can talk over the agent at any time and it stops to listen
* ⏳ **No awkward silence**: if the AI takes a moment to answer, it says a short filler line ("Hmm, let me think.")
* 📚 **Student-focused topics**: General Knowledge, Science, History, Geography, Space, Environment, and everyday "why" questions
* 📷 **Show your homework**: during a conversation, snap or pick a photo of a homework or textbook page. ThinkShift says what it sees and asks one guiding question, without giving away the answer
* 💡 **Suggested prompts**: tap "Why is the sky blue?", "Tell me about space" or "Why do eclipses happen?" to get started
* 📱 **Mobile-first UI**: animated AI orb, voice waves, clear connection states
* 🌐 **Multilingual-ready**: the companion is instructed to reply in the student's language (English, Hindi, Marathi); multilingual speech recognition is next

---

## 🧑‍🎓 Example Experience

> **Student:** Why is the sky blue?
>
> **ThinkShift:** Sunlight has all colours, but the air scatters blue light the most, so blue reaches our eyes from every direction. What colour do you think the sky would be with no air at all?
>
> **Student:** Maybe black?
>
> **ThinkShift:** Exactly right! With no air to scatter light, the sky looks black. That's what astronauts see from the Moon.

One question, one moment of thinking, then the student leads again. The interaction becomes **a conversation instead of a search session**.

---

## 🏗️ How It Works

```text
Student
   │ 🎙️ voice
   ▼
Flutter App (Android)
   │  1. GET /token        ──►  Python backend (Flask)
   │  2. join channel (Agora RTC)
   │  3. POST /start-agent ──►  backend ──► Agora Agent SDK
   ▼
Agora Conversational AI agent (joins the same RTC channel)
   │
   ├── Deepgram nova-3        speech → text
   ├── OpenAI gpt-4o-mini     ThinkShift persona + one-question rule
   └── MiniMax speech-2.8     text → speech
   │
   ▼
🎙️ Voice response back to the student
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full flow and [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the code layout.

---

## 🛠️ Technology Stack

| Layer | Technology |
|---|---|
| **Mobile** | Flutter (Dart), Android · `agora_rtc_engine` · `permission_handler` · `http` · `image_picker` |
| **Voice** | Agora RTC · Agora Conversational AI (agent SDK `agora-agents` 2.8.1) |
| **AI pipeline** | Agora-managed models: Deepgram `nova-3` (STT) · OpenAI `gpt-4o-mini` (LLM) · MiniMax `speech-2.8-turbo` (TTS) |
| **Vision** | Google Gemini (`gemini-2.5-flash`) via `google-genai`, for describing homework photos |
| **Backend** | Python · Flask · flask-cors · `agora-token-builder` |

---

## 🚀 Getting Started

### Prerequisites

* An [Agora](https://console.agora.io) project with **App Certificate** enabled and **Conversational AI** activated
* Agora RESTful API **Customer ID / Secret**
* A Google **Gemini API key** for the homework photo feature (free at [Google AI Studio](https://aistudio.google.com/apikey))
* Python 3.10+
* Flutter SDK (Dart ≥ 3.12) and an Android device or emulator

### 1. Backend

```bash
cd backend
pip install flask flask-cors python-dotenv requests httpx agora-token-builder agora-agents==2.8.1 google-genai
cp .env.example .env        # then fill in your Agora credentials and Gemini key
python thinkshift_app_sdk.py
```

The server runs on `http://0.0.0.0:8001`. Open `http://localhost:8001/` and check that it says the backend is running.

### 2. Mobile app

1. Create your local config (it's git-ignored) and set the backend URL in it:

   ```bash
   cp frontend_mobile/lib/config.example.dart frontend_mobile/lib/config.dart
   ```

   * Android emulator: `http://10.0.2.2:8001` (the default)
   * Physical phone on Wi-Fi: `http://<your-PC-LAN-IP>:8001` (same Wi-Fi, port 8001 allowed through the firewall)
   * Physical phone over USB: run `adb reverse tcp:8001 tcp:8001` and use `http://127.0.0.1:8001`
2. Run the app:

   ```bash
   cd frontend_mobile
   flutter pub get
   flutter run
   ```

3. Tap **Tap to talk**, allow the microphone, and start speaking.

### Backend API

| Method | Endpoint | Body / query | Purpose |
|---|---|---|---|
| `GET` | `/` | — | Health check |
| `GET` | `/token` | `?channel=&uid=` | RTC + RTM tokens for the student |
| `POST` | `/start-agent` | `{"channel", "uid"?}` | Start the AI agent in the channel |
| `POST` | `/interrupt-agent` | `{"agent_id"}` | Stop the agent mid-sentence (session keeps running) |
| `POST` | `/stop-agent` | `{"agent_id"}` | Remove the agent from the channel |
| `POST` | `/analyze-homework` | multipart: `agent_id`, `image` (max 5 MB) | Gemini describes the photo; the agent talks about it |

### Customising the companion

Everything lives in [backend/constants.py](backend/constants.py): the system prompt, greeting, filler phrases, voice-detection timings, and LLM temperature. Restart the backend and start a new conversation to pick up changes.

---

## 🎯 Why Voice?

Typing creates friction between a student and learning.

Voice allows students to:

* Ask questions the way they naturally would
* Follow up instantly, without retyping
* Be asked to reason, not just handed answers
* Learn hands-free, while doing other things

ThinkShift AI explores how **real-time voice can become the main interface for mobile learning**.

---

## 🔮 Future Possibilities

* 🌍 **Multilingual speech**: Hindi and Marathi speech recognition with matching voices
* ⌨️ Keyboard input and 🕘 conversation history (history placeholder already in the UI)
* 🧠 Adaptive explanations based on the student's level
* ❓ Voice-based quizzes and 📝 exam preparation
* 📖 Explaining textbook content, 📚 RAG-powered learning material
* 🔎 Web and knowledge-base search via agent tools / MCP
* 👩‍🏫 AI tutor personas and 🎯 personalised learning plans
* 📊 Learning progress insights

---

## 📱 Project Status

🚧 **Prototype / Hackathon Project**

Working today: the full real-time voice loop between a student and the ThinkShift companion on Android.

Known limitations:

* Speech recognition is set to English (`ASR_LANGUAGE=en`)
* Single fixed channel (`thinkshift_room_1`) for one tester at a time
* Agent sessions are held in backend memory

---

## 👩‍💻 Built With

**Flutter • Android • Agora RTC • Agora Conversational AI • Python • Flask**

---

## 📄 License

This project was created for a hackathon and is intended for demonstration and experimentation.
