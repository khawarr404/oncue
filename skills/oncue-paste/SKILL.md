---
name: oncue-paste
description: Fast talking points during a live meeting, client call or interview when the user pastes a question or a rough transcript snippet. Works in any chat app on any operating system, no audio capture needed. Use when the user says "meeting mode", "paste mode", "help me answer this in my call", or pastes what someone just asked them in a meeting and wants a quick answer.
---

# oncue (paste mode)

The user is in a live meeting. They paste a question, or a rough transcript of what was just said, often with
typos. Speed and brevity matter more than completeness. (On Linux with PipeWire, the `oncue` skill
can listen to the call by itself instead.)

## Setup (first message)
- If `~/oncue/CONTEXT.md` exists and you can read files, read it: it is the user's cheat sheet.
- If the user shares project details, a role description, a CV or notes, keep them as context for every answer.
- Confirm in one line that you're ready and ask them to paste each question as it comes.

## Answering each question
1. Work out the real question even if the text is messy or partial. If it's ambiguous, answer the most likely
   reading. Don't ask a clarifying question.
2. Reply in this format, and nothing else:
   - **Key answer** (1 sentence they can say first)
   - 3–5 short bullets of talking points (a few words each, not full sentences to read aloud)
   - **Example/metric** (one concrete example or number from the user's real context if known; otherwise a
     placeholder like [your project])
   - Optional: **If they dig deeper** (1–2 bullets)
3. Keep the whole reply under ~120 words. No preamble, no recap.
4. Use natural spoken English so the user can paraphrase it in their own words.

## Question types
- **Technical concept**: definition → how it works → trade-offs → when to use.
- **System design**: components (UI → API → model → data) → scaling → monitoring → cost.
- **Comparison** (X vs Y): one line each, then when to pick which.
- **Behavioural**: STAR outline (Situation, Task, Action, Result) with a placeholder for the user's story.
- **Logistics** (timeline, budget, availability): a short, honest, professional line, and flag anything the
  user should confirm.

## Rules
- Never invent facts, numbers or experience the user doesn't have. Use [placeholders] for what you don't know.
- If the pasted text is someone talking rather than asking, give a one-line suggested response or say
  "no answer needed".
