# Trace Replay Diagnostics

Douvo writes local transcription traces under:

```text
~/Library/Logs/Douvo/Traces
```

New traces include the fields needed to reproduce correction failures:

- `metadata.recording_path`: saved local WAV path when debug recording is available.
- `metadata.raw_text`: raw ASR text before LLM correction.
- `metadata.corrected_text`: final text after correction and deterministic cleanup.
- `metadata.correction.prompt_snapshot_path`: effective prompt snapshot used by correction.

These fields may contain transcript text. Keep trace, replay, and prompt snapshot files local unless the user explicitly chooses to share them.

## Replay Correction

Replay a trace without starting the UI app:

```bash
swift run Douvo --replay-trace ~/Library/Logs/Douvo/Traces/<trace>.json
```

The command reruns the correction step from `metadata.raw_text`. It does not rerun ASR from the WAV yet, because the current ASR providers are real-time WebSocket clients and do not expose an offline WAV transcription path.

Outputs are written under:

```text
~/Library/Logs/Douvo/Replays
```

The replay report contains:

- source trace path and trace id
- linked recording and prompt snapshot paths
- raw text, previous corrected text, and replay corrected text
- correction metadata, timings, and prompt/debug payload

## Prompt Lab Case

`--replay-trace` also writes a Prompt Lab config next to the replay report:

```text
~/Library/Logs/Douvo/Replays/<timestamp>-prompt-lab-case.json
```

Run it directly:

```bash
swift run Douvo --prompt-lab ~/Library/Logs/Douvo/Replays/<timestamp>-prompt-lab-case.json
```

The generated case uses the trace raw text as `inputs[].text`, the trace corrected text as `inputs[].expected`, and the current correction settings for model, punctuation style, output style, reasoning mode, and max tokens.
