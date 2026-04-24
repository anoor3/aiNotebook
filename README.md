# aiNotebook

A SwiftUI + PencilKit iPad notebook that feels like paper, keeps your ideas organized, and now remembers your notebooks between sessions.

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Abdullah%20Noor-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abdullah-noor1/)
[![Email](https://img.shields.io/badge/Email-abdullahnoorllc%40gmail.com-EA4335?logo=gmail&logoColor=white)](mailto:abdullahnoorllc@gmail.com)

## What it does
- **Digital ink that feels natural:** Pen/eraser tools, multiple stroke widths, and a custom color picker for quick sketching.
- **Pages that grow with you:** Infinite scrolling adds new pages automatically; a page grid lets you jump around.
- **Notebook library:** Create, rename, favorite, and delete notebooks with custom covers and paper styles (grid, dot, lined, blank).
- **Persistence built in:** Notebook metadata and drawing data are saved to the device so your work is there when you return.

## How it’s structured
- **SwiftUI UI:** `LibraryRootView` and `NotebookContainerView` drive navigation and notebook/page management.
- **Drawing stack:** `NotebookPageView` hosts `PencilCanvasView`, which wraps a `PKCanvasView` and custom ink rendering for smooth strokes and eraser highlighting.
- **Data model:** `Notebook` and `NotebookPageModel` track notebook metadata, pages, and drawing payloads.
- **Persistence:** `DrawingPersistence` stores per-page drawings; `NotebookLibraryPersistence` saves the library’s notebooks as JSON in the app’s Documents directory.

## Getting started
1. Open `NotebookApp/ainotebook/ainotebook.xcodeproj` in Xcode on macOS with an iPad simulator or device.
2. Build and run the **ainotebook** target.
3. Create a notebook, pick a cover color and paper style, and start drawing. Your notebooks and pages will auto-save.

## OpenAI API key (for the AI chat)
- The app reads your key from the environment variable `OPENAI_API_KEY` (recommended).
- In Xcode: **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables** and add `OPENAI_API_KEY`.
- A sample file is provided at `.env.example`. You can keep your real key in `env/` locally (the `env/` folder is in `.gitignore`).
- Optional: create `env/openai.env` with `OPENAI_API_KEY=...`, then add it to the Xcode target’s **Copy Bundle Resources** so the app can read it at runtime.

## Notes
- The app targets iPadOS and uses PencilKit (Apple Pencil recommended).
- Autosave runs on a background queue; drawings persist per page, and library metadata persists across launches.
