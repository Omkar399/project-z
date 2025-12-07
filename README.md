<div align="center">

<img src="Clippy/Resources/clippy-writing.gif" alt="Project Z - Clippy Writing" width="200" />

<img src="https://img.icons8.com/?id=dL3M6FPblFer&format=png&size=128" alt="Project Z Logo" />

# <img src="https://img.icons8.com/?id=ESeqfDjC5eVO&format=png&size=48" valign="middle" /> Project Z
### The Memory-Augmented OS Copilot
#### <img src="https://img.icons8.com/?id=kuU7I7uPlHfo&format=png&size=32" valign="middle" /> xAI Hackathon 2025 Submission

[![xAI Hackathon](https://img.shields.io/badge/Submission-xAI_Hackathon_2025-black?style=for-the-badge&logo=x&logoColor=white)](https://x.ai)
[![Powered by Grok](https://img.shields.io/badge/AI-Grok_4_Fast-000000?style=for-the-badge&logo=x&logoColor=white)](https://x.ai)
[![Memory by Mem0](https://img.shields.io/badge/Memory-Mem0-FF4F00?style=for-the-badge&logo=brain&logoColor=white)](https://mem0.ai)
[![Platform](https://img.shields.io/badge/Platform-macOS_15.0+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

<br />

**Project Z is the first OS assistant that actually remembers.**  
It combines the reasoning speed of **Grok-4** with the long-term memory of **Mem0** to create a companion that knows your context, protects your social life, and manages your digital workflow.

[View Demo](https://youtu.be/G7C_tThwl9s) · [Report Bug](https://github.com/yhinai/project-z/issues) · [Request Feature](https://github.com/yhinai/project-z/issues)

</div>

---

## <img src="https://img.icons8.com/?id=IYgsr2y1M2w8&format=png&size=32" valign="middle" /> Table of Contents
- [About the Project](#-about-the-project)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Getting Started](#-getting-started)
- [Usage Guide](#-usage-guide)
- [Technology Stack](#-technology-stack)
- [Roadmap](#-roadmap)

---

## <img src="https://img.icons8.com/?id=dL3M6FPblFer&format=png&size=32" valign="middle" /> About The Project

Project Z was built to solve a specific problem: **AI assistants are amnesiacs.** They don't know what you copied 5 minutes ago, they don't know your schedule, and they definitely don't know you shouldn't text your ex at 2 AM.

**Project Z changes that.**

By integrating deeply with macOS accessibility and clipboard APIs, and backing it with a persistent vector memory, Project Z acts as a "second brain" that lives on your desktop. It's not just a wrapper; it's an agent that proactively helps you.

---

## <img src="https://img.icons8.com/?id=qdQpy48X3Rjv&format=png&size=32" valign="middle" /> Key Features

### <img src="https://img.icons8.com/?id=RZ3Ux64yROj8&format=png&size=24" valign="middle" /> **Agentic Brain (Grok-4)**
Project Z uses an **Agentic RAG** system to route your queries intelligently.
- **Context Aware:** It knows if you're asking about your clipboard, your calendar, or general knowledge.
- **Fast Reasoning:** Powered by `grok-4-fast` for near-instant responses.

### <img src="https://img.icons8.com/?id=b2Ffb1mhmDna&format=png&size=24" valign="middle" /> **Smart Clipboard**
- **Semantic Search:** Don't remember the exact words? Search by meaning. "The tracking code I copied this morning" finds `1Z999...`.
- **Auto-Tagging:** Every copied item is analyzed and tagged by AI (e.g., `["code", "swift", "networking"]`).
- **Infinite History:** Stored locally and vector-indexed for retrieval.

### <img src="https://img.icons8.com/?id=lsZBoVE2zMo3&format=png&size=24" valign="middle" /> **Guardian Mode**
**Your AI Wingman.** Project Z monitors your screen context.
- **Intervention:** If you open a chat with a "blocked" contact (configured in settings), Z wakes up.
- **Savage Roasts:** It generates a funny, savage roast to stop you from making a mistake.
- **Supported Apps:** Messages, WhatsApp, Telegram, Signal.
> *"Bestie, put the phone down. He's not worth the therapy bills. 🚩"*

### <img src="https://img.icons8.com/?id=IYyZyQ9av9Vf&format=png&size=24" valign="middle" /> **Rizz Mode**
Struggling with a reply on a dating app?
- **Context Analysis:** Reads the chat history on your screen.
- **Suggestion Engine:** Generates 4 distinct reply options (Playful, Direct, Mysterious, Casual).
- **Anti-Cringe:** Fine-tuned to avoid generic AI-sounding responses.

### <img src="https://img.icons8.com/?id=VROWGw8C8j6y&format=png&size=24" valign="middle" /> **Vision Intelligence**
- **Screen Reading:** Press `Option+V` to have Z analyze your current window.
- **OCR:** Extract text from images, videos, or protected websites instantly.

---

## <img src="https://img.icons8.com/?id=13542&format=png&size=32" valign="middle" /> Architecture

We use a **Hybrid Architecture** to ensure speed and privacy.

```mermaid
graph TD
    User(("User")) -->|Option+X| App["macOS App (Swift)"]
    
    subgraph "Local Device (macOS)"
        App -->|Monitor| Clipboard["Clipboard Manager"]
        App -->|Analyze| Vision["Apple Vision Framework"]
        App -->|Persist| SwiftData[("Local DB")]
    end
    
    subgraph "Memory Service (Local Python)"
        App <-->|HTTP| Mem0["Mem0 Service (FastAPI)"]
        Mem0 <-->|Store| VectorDB[("Qdrant")]
        Mem0 -->|Embed| OpenAI["OpenAI Embeddings"]
    end
    
    subgraph "Reasoning Cloud (xAI)"
        App <-->|Inference| Grok["Grok-4 API"]
        Grok -->|Agentic Decision| Action{"Action Router"}
        Action -->|Text| Reply["Generate Answer"]
        Action -->|Calendar| Cal["Manage Schedule"]
        Action -->|Roast| Roast["Guardian Intervention"]
    end
```

---

## <img src="https://img.icons8.com/?id=bY5t0noHcfXn&format=png&size=32" valign="middle" /> Getting Started

### Prerequisites

*   **macOS 15.0+** (Sequoia) - Required for latest SwiftUI/SwiftData features.
*   **Xcode 16.0+** - To build the Swift project.
*   **Python 3.10+** - To run the memory backend.
*   **API Keys**:
    *   **xAI API Key** (for Grok)
    *   **OpenAI API Key** (for Mem0 embeddings)

### Installation

#### 1. Backend Setup (Memory Service)
The memory service runs locally to keep your data secure and fast.

```bash
# Clone the repository
git clone https://github.com/yhinai/project-z.git
cd project-z/mem0_service

# Install dependencies
pip install -r requirements.txt

# Configure Environment
echo "OPENAI_API_KEY=your_openai_key_here" > .env

# Start the Service
python main.py
```
*You should see: `🚀 Starting Mem0 Service on http://localhost:8420`*

#### 2. iOS/macOS App Setup
1.  Open `Clippy.xcodeproj` in Xcode.
2.  Navigate to **ProjectZApp.swift** or run the app to access **Settings**.
3.  Enter your **xAI API Key**.
4.  Build and Run (`Cmd+R`).
5.  **Important:** Grant **Accessibility** and **Screen Recording** permissions when prompted. These are required for Clipboard monitoring and Guardian Mode.

---

## <img src="https://img.icons8.com/?id=WAOz8R8T2yma&format=png&size=32" valign="middle" /> Usage Guide

### Keyboard Shortcuts

| Shortcut | Function | Description |
|:---:|:---|:---|
| **`⌥ + X`** | **Talk / Ask** | Opens the main chat interface. Ask about your clipboard, schedule, or general questions. |
| **`⌥ + V`** | **Vision Mode** | Captures the active window/screen and extracts text or context for analysis. |
| **`⌥ + Space`** | **Voice Mode** | *Experimental* - Trigger voice capture to talk to Project Z directly. |
| **`Cmd + Shift + K`** | **Spotlight** | Opens the quick-search history view (Semantic Search). |
| **`Ctrl + Return`** | **Rizz Mode** | **Context Aware:** Analyzes the chat you are looking at and generates 4 reply options. |
| **`Shift + Esc`** | **Privacy Toggle** | Instantly toggles "Incognito Mode" (stops recording clipboard/screen). |
| **`Esc`** | **Dismiss** | Hides the assistant immediately. |

### Rizz Mode Controls
*While Rizz Mode is active:*
*   **`↑` / `↓` Arrow Keys:** Cycle through generated reply options.
*   **`Enter`:** Commit selected reply (pastes into text field).
*   **`Esc`:** Cancel Rizz Mode.

### Example Queries
*   *"What was that code snippet I copied about Python lists?"*
*   *"Do I have any meetings before 2 PM tomorrow?"*
*   *"Schedule a sync with the design team for Friday at 10 AM."*
*   *"Does this email look passive-aggressive? (while looking at an email)"*

---

## <img src="https://img.icons8.com/?id=VLOHQKgPwqxY&format=png&size=32" valign="middle" /> Technology Stack

### **macOS Client**
*   **Language:** Swift 6
*   **UI Framework:** SwiftUI
*   **Database:** SwiftData (Structured), VecturaKit (Local Vector Cache)
*   **OS Integration:** Accessibility API, ScreenCaptureKit, Vision Framework

### **Backend Service**
*   **Framework:** FastAPI (Python)
*   **Memory Engine:** Mem0
*   **Vector DB:** Qdrant (Local Docker/File)
*   **Embeddings:** OpenAI `text-embedding-3-small`

### **AI Models**
*   **Reasoning:** xAI `grok-4-fast` (via API)
*   **Embeddings:** OpenAI (via Mem0)

---

## <img src="https://img.icons8.com/?id=RpspyEyOEJOU&format=png&size=32" valign="middle" /> Roadmap

- [x] **Core Clipboard Engine**
- [x] **Grok-4 Integration**
- [x] **Mem0 Long-term Memory**
- [x] **Guardian Mode (Screen Context)**
- [ ] **Voice Interface (Speech-to-Text)**
- [ ] **Local LLM Fallback (MLX)**
- [ ] **HomeKit Integration**

---

## <img src="https://img.icons8.com/?id=iyojsvSTyosf&format=png&size=32" valign="middle" /> License

Distributed under the MIT License. See `LICENSE` for more information.

---

<div align="center">

**Built with ❤️ for the xAI Hackathon 2025**  
*The future of OS interaction is Agentic.*

<a href="https://x.ai">
<img src="https://img.shields.io/badge/xAI-Hackathon-black?style=for-the-badge&logo=x&logoColor=white" />
</a>

</div>
