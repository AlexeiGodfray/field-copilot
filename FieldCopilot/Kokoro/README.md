# Kokoro voice model

The app reads results aloud with Kokoro-82M, an open voice model (Apache-2.0), bundled from this folder.
The model is 88 MB, so it isn't in git. To download it, run this from the repository root, then rebuild the app:

```bash
swift FieldCopilot/Scripts/fetch_voice.swift
```

Without it, the app uses the phone's own voice.
