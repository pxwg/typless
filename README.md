# Typless

A native macOS 14+ voice input app, with a Typeless-inspired desktop experience
and Qwen Omni recognition and writing. No Apple Speech framework or Speech
Recognition permission is used.

## Build and run

```sh
make build                 # signed debug .app in .build/app/Typless.app
make run                   # rebuild and launch
make test
make install               # copy to ~/Applications/Typless.app
make build CONFIGURATION=release
```

The app requires microphone and Accessibility permissions. The home screen
shows setup when permissions are missing. Keep the bundle ID, signing identity,
and install location stable so macOS can reuse existing authorization.

## Qwen configuration

The default configuration source is `~/test-omni/.env`, matching the companion
Qwen voice project's connection contract. Change the directory and test the
connection in **设置 → 语音模型**.

Supported values:

- `DASHSCOPE_API_KEY`: a Model Studio / DashScope API key.
- `QWEN_REGION`: `beijing` (default) or `singapore`.
- `DASHSCOPE_WORKSPACE_ID`: optional workspace domain.
- `QWEN_REALTIME_URL`: optional complete WebSocket endpoint.
- Process environment values override the file.

The model is `qwen3.5-omni-flash-realtime`, with
`qwen3-asr-flash-realtime` as its input transcription track, exactly as in
`test-omni`. Audio is converted to mono 16 kHz PCM16, streamed through a native
WebSocket connection, and committed explicitly when the user stops.

**智能整理** uses Qwen to remove accidental repetitions and fillers, apply
self-corrections, and add punctuation while preserving meaning and language.
It waits for the complete input transcription, supplies that draft to the same
Qwen session as explicitly marked data, and waits for the editing instructions
to be accepted before generating and inserting the finished text.
**忠实转写** returns the input transcription track. Vocabulary hints apply to
smart writing. The old optional Chat Completions corrector is no longer called
by the dictation workflow.

Audio goes to the configured Qwen endpoint over WSS (WS is permitted only for
loopback development servers). The app reads credentials at runtime; they are
never bundled, logged, or stored in dictation history. The companion Python CLI
does not need to run.

## Interaction

- In macOS **System Settings → Keyboard**, set **Press 🌐 / Fn key to** to
  **Do Nothing**. The system emoji/input-source action can run outside the app's
  event tap. Typless detects conflicting or unknown settings on Home and Settings,
  and provides a button to open Keyboard settings; it never silently overwrites
  system preferences at launch. If changed with `defaults`, macOS may require
  signing out and back in; use the Settings UI for an immediate change.
- Tap **Fn** to start, then tap again to finish.
- Hold **Fn** for more than 300 ms to use push-to-talk; release to finish.
- Settings also offers dedicated hold-only and toggle-only modes.
- **Esc** cancels recording or pending transcription.
- The floating voice bar has cancel and stop controls, a real audio meter,
  elapsed time, and a processing state. It does not activate the app.
- Dictations stop automatically after five minutes.
- The original editable field is captured when recording starts. If focus
  changes, the result stays in history and **复制上次转写** instead of being
  inserted in the new field. Secure fields are excluded.
- Text is pasted with Cmd+V without switching the user's input method (including
  Squirrel/Rime). The clipboard is restored after paste unless the user changed
  it in the meantime. Accessibility direct writing is not enabled yet.
- **试着说一句** on Home lets you test without targeting another app.

## Local data

History, original transcription text, and the dictionary are saved under
`~/Library/Application Support/Typless/`. Audio is not persisted. History can
be searched, copied, exported, or deleted; it can also be disabled for new
dictations. Statistics are calculated from retained history, not fabricated
sample data. Dictionary supports adding several words and importing simple
CSV/text lists.

## Verification

`swift test` exercises configuration parsing and validation, stereo 48 kHz →
mono 16 kHz conversion including the resampler tail, and history persistence.

An opt-in live integration test sends only an explicitly supplied audio file,
using the real Qwen client in both writing modes:

```sh
TYPLESS_QWEN_TEST_AUDIO=/path/to/synthetic-test.aiff \
  swift test --filter QwenTests/testLiveQwenTranscription
```

Use synthetic, non-sensitive audio for this check. It does not open the
microphone. GUI and microphone verification are separate from this test.

For Chinese cleanup regression, synthesize this exact fixture with `say -v Tingting`:
“嗯，那个，我想说，就是明天下午三点，不对，四点，我们开个会，然后讨论一下那个项目进度。”
Run the live test with `TYPLESS_QWEN_LANGUAGE=zh-CN`, `TYPLESS_QWEN_EXPECTED=项目进度`
and `TYPLESS_QWEN_CHECK_CLEANUP=1`. It checks removal of hesitation and the
superseded time, retention of the corrected time and topic, and sentence punctuation.
`TYPLESS_QWEN_KEEP` and `TYPLESS_QWEN_DROP` optionally accept pipe-separated phrases
for other semantic fixtures. “那个文件” is a meaningful demonstrative and must not
be removed by a blanket filler-word replacement.

Reference behavior:
[Typeless dictation](https://www.typeless.com/help/quickstart/dictate),
[history and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary),
[Qwen Realtime protocol](https://www.alibabacloud.com/help/en/model-studio/realtime).
