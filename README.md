# FlowGym 🧘‍♂️💻

<p align="left">
  <img src="logo.png" width="160" alt="FlowGym Logo">
</p>

**Demo Video**: [See it in action on Douyin](https://v.douyin.com/yep7XMAjvPg/)

**Turn every move into a productivity boost.**

`FlowGym` is a productivity tool for Mac users that brings "Gym at your Desk" to life. Powered by AI motion capture, it translates your body movements—like squats, jumps, and punches—directly into precise keyboard and mouse commands.

Stay in your **Flow** state while getting a mini **Gym** session during your workday.

---

## ✨ Features

- **AI Pose Detection**: Built on Apple's Vision framework for real-time, low-latency tracking of 17 body landmarks.
- **Workflow Integration**: Seamlessly map exercises to high-frequency office tasks (e.g., Squat to Dictate, Jump to Send).
- **Minimalist HUD**: A sleek, translucent overlay providing real-time feedback with native smooth dragging support.
- **Learning Mode**: Customize input field focus for different applications.
- **Ready to Go**: Packaged as a standard `.app` bundle—just double-click and play.

---

## 🎮 Gesture Guide

| Icon | Gesture | Action Mapping |
| :--- | :--- | :--- |
| 🏋️ | **Squat** | **Dictation** (Fn key down) |
| 👏 | **Clap** | **Enter** (Confirm/New line) |
| ❌ | **Cross Arms** | **Escape** (Cancel/Back) |
| 👊 | **Punch** (Left/Right) | **← / →** Arrow Keys |
| 💪 | **Side Lift** | **Tab** (Switch Tabs) |
| ⛹️ | **Jump** | **Enter** (Express Send) |
| 🤚 | **Right arm raise** | **Click** screen center |
| ⚙ | **Config** | Record input cursor location |

---

## 🚀 Installation & Distribution

### Option 1: Run as App (Recommended)
1. Download and open `FlowGym.app`.
2. Drag the HUD to any corner of your screen.
3. Click [❓ Help] for a quick gesture reference.

### Option 2: Build from Source
If you wish to customize or optimize for your setup:
1. **Clone the repository**:
   ```bash
   git clone https://github.com/zhulin025/FlowGym.git
   ```
2. **Build Release**:
   ```bash
   swift build -c release
   ```
3. **Package as .app**:
   ```bash
   chmod +x package.sh
   ./package.sh
   ```
The compiled `FlowGym.app` will be created in the root directory.

---

## 💻 Hardware & System Requirements

| Hardware | Compatibility | Notes |
| :--- | :--- | :--- |
| **Apple Silicon (M1/M2/M3)** | ✅ **Native Support** | Recommended. Uses Neural Engine for ultra-low latency tracking. |
| **Intel Macs** | ⚠️ **Emulated/Basic** | Supported, but Vision algorithms will rely more on CPU/GPU. |
| **Operating System** | 🍏 **macOS 14.0+** | Sonoma or higher is recommended for the best experience. |

---

## 🛡 Privacy & Security

`FlowGym` processes all visual data **locally in real-time**. No images are ever saved or uploaded.
To function correctly, first-time users must grant:
1. **Camera Permission**: For motion detection.
2. **Accessibility Permission**: Found in `System Settings -> Privacy & Security -> Accessibility`. Enable **FlowGym** to allow keyboard simulation.

---

## 👨‍💻 Acknowledgments

This project is built and expanded upon [fifteen42/vibemove](https://github.com/fifteen42/vibemove/). Special thanks to the original author for the core pose-tracking inspiration.

## 📄 License

This project is licensed under the **MIT License**.
Copyright (c) 2026 **zhulin025**
