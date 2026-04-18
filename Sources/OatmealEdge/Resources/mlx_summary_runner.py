#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_mlx_symbols():
    try:
        from mlx_lm import load, generate
        return load, generate
    except ImportError:
        from mlx_lm.utils import load, generate  # type: ignore
        return load, generate


def build_prompt(request: dict) -> str:
    transcript_lines = []
    for segment in request.get("transcriptSegments", []):
        speaker = segment.get("speakerName") or "Speaker"
        text = segment.get("text", "").strip()
        if text:
            transcript_lines.append(f"{speaker}: {text}")

    event = request.get("event") or {}
    event_lines = []
    if event.get("title"):
        event_lines.append(f"Event title: {event['title']}")
    if event.get("attendeeNames"):
        event_lines.append("Attendees: " + ", ".join(event["attendeeNames"]))
    if event.get("location"):
        event_lines.append(f"Location: {event['location']}")

    schema = {
        "summary": "string",
        "keyDiscussionPoints": ["string"],
        "decisions": ["string"],
        "risksOrOpenQuestions": ["string"],
        "actionItems": [{"text": "string", "assignee": "string|null"}],
        "warningMessages": ["string"],
    }

    return f"""
You are Oatmeal, a private local meeting summarizer running fully on-device.

Return JSON only. Do not include markdown fences or explanation.

Target JSON schema:
{json.dumps(schema, indent=2)}

Meeting title: {request.get("title", "")}
Template name: {request.get("templateName", "")}
Template instructions: {request.get("templateInstructions", "")}
Template sections: {", ".join(request.get("templateSections", []))}

Calendar context:
{chr(10).join(event_lines) if event_lines else "No calendar context."}

Raw notes:
{request.get("rawNotes", "").strip() or "No raw notes."}

Transcript:
{chr(10).join(transcript_lines) if transcript_lines else "No transcript available."}

Requirements:
- Keep the summary concise and specific.
- Prefer facts grounded in the meeting content.
- Extract action items with assignees when clear.
- Keep warningMessages empty unless the input is too sparse or ambiguous.
""".strip()


def extract_json_blob(text: str) -> str:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Model output did not contain a JSON object.")
    return text[start : end + 1]


def coerce_response(payload: dict) -> dict:
    payload = payload if isinstance(payload, dict) else {}
    return {
        "summary": str(payload.get("summary", "")).strip(),
        "keyDiscussionPoints": [str(item).strip() for item in payload.get("keyDiscussionPoints", []) if str(item).strip()],
        "decisions": [str(item).strip() for item in payload.get("decisions", []) if str(item).strip()],
        "risksOrOpenQuestions": [
            str(item).strip() for item in payload.get("risksOrOpenQuestions", []) if str(item).strip()
        ],
        "actionItems": [
            {
                "text": str(item.get("text", "")).strip(),
                "assignee": (str(item.get("assignee")).strip() if item.get("assignee") is not None else None),
            }
            for item in payload.get("actionItems", [])
            if isinstance(item, dict) and str(item.get("text", "")).strip()
        ],
        "warningMessages": [str(item).strip() for item in payload.get("warningMessages", []) if str(item).strip()],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--model", required=True)
    args = parser.parse_args()

    request = json.loads(Path(args.input).read_text())
    prompt = build_prompt(request)
    load, generate = load_mlx_symbols()
    model, tokenizer = load(args.model)

    generated_text = None
    attempts = [
        lambda: generate(model, tokenizer, prompt=prompt, max_tokens=700, verbose=False),
        lambda: generate(model, tokenizer, prompt=prompt, max_tokens=700, temp=0.1, verbose=False),
        lambda: generate(model, tokenizer, prompt, max_tokens=700),
    ]

    last_error = None
    for attempt in attempts:
        try:
            generated_text = attempt()
            break
        except TypeError as exc:
            last_error = exc
            continue

    if generated_text is None:
        raise last_error or RuntimeError("Unable to generate text with mlx_lm.")

    if not isinstance(generated_text, str):
        generated_text = str(generated_text)

    response = coerce_response(json.loads(extract_json_blob(generated_text)))
    Path(args.output).write_text(json.dumps(response, indent=2))


if __name__ == "__main__":
    main()
