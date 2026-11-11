# Changelog

## 2.3.1 — 2026-11-11

A conversation that changes provider keeps working (lm15-contract `81b519f`, MAP-24,
issue #3; to ratify; 4,269 of 4,269 checks, the same as every lm15 language).

- **Fixed: a conversation answered by an OpenAI Responses model and continued on Claude
  failed on every request** with `messages: text content blocks must be non-empty`. OpenAI's
  hidden reasoning is kept in the history as a `ThinkingPart` with empty text and OpenAI's
  own state; the Messages builder wrote it as an empty text block. A part with nothing for
  the provider it is sent to now writes nothing there, and a message left with nothing is
  not sent. Your messages are not changed: sent back to OpenAI, the reasoning goes with
  them.
- The same on every wire and for every such part: an empty `TextPart` (what lm15 reads for
  a reply with no parts), a citation that quotes nothing, an empty system prompt given as
  parts. Anthropic, Gemini, OpenAI Responses and Chat Completions requests no longer carry
  an empty text block or an empty message.
- Claude's own thinking with display omitted (empty text and its signature) still goes back
  as a thinking block. A tool result is always sent; an empty output is the empty string.
- Nothing is recorded in `Response.adaptations` for this: no word anyone wrote is withheld.
- **Fixed: a reply with citations, or with a structured (data) answer, could not be sent
  back to OpenAI.** `build_request` raised `UnsupportedFeatureError` for an assistant
  `CitationPart` or `DataPart` on the Responses and Chat Completions wires, so a
  conversation that had used web search or judgments stopped there. A citation now writes
  nothing on those wires (the text it annotates is sent, as in every lm15 language), and a
  data part is sent as its compact JSON (as on Anthropic and Gemini).
- On Anthropic and Gemini a citation in an assistant message is now sent as the text it
  quotes, as in the reference; it was `title — url — text`.
- Small wire changes for requests that worked before: text joined into one string has no
  blank line for an empty part; a user message that is only an empty string is not sent.
- Not changed, and still refused by the provider when it happens: thinking signed by
  another server of the same API family (DeepSeek's or Meta's Anthropic-compatible endpoint
  to Anthropic), a tool loop moved to Gemini 3 or DeepSeek between a call and its result,
  and a message whose only text is whitespace sent to Anthropic.

## 2.3.0 — 2026-11-10

Tinker (Thinking Machines): base models and the models you trained there
(lm15-contract `18b3788`; to ratify; 2,266 of 2,266 checks, the same as every lm15
language).

- **Two new providers, one key (`TINKER_API_KEY`):** `tinker` (Chat Completions, also
  spelled `thinkingmachines`) and `tinker-anthropic` (Messages). Both serve Tinker's base
  models and any sampler checkpoint by its path.
- **A URI is one model name:** `tinker://<run>:train:0/sampler_weights/<n>` routes to
  Tinker whole.
- **Reasoning is switched the way each model family takes it;** a checkpoint follows the
  family of its base model when you name it: `RouterConfig(; base_models=Dict("tinker://…"
  => "Qwen/Qwen3.5-4B"))` (also `ProviderLM(...; base_models)`). Model listing on `tinker`
  marks each checkpoint as a fine-tune with `origin.base_model`.
- **Error messages from FastAPI servers are kept** (`{"detail": ...}` bodies), and
  **`stop` means the same everywhere** (Tinker returns the stop sequence; lm15 cuts it).
- New compat values: `thinking_format="reasoning_effort_switch"`, `reasoning_off="switch"`,
  `json_schema="none"`, `stop_in_text`. Registry entries may carry aliases.

## 2.2.0 — 2026-11-07

Claude shows its thinking when you ask for it (lm15-contract `9d8e1ce`, MAP-7 rule 7
amended; 2,140 of 2,140 checks, the same as every lm15 language).

- **`Reasoning(; summary=...)` on Claude sends `thinking.display: "summarized"`.** Since
  Opus 4.7, Anthropic returns a thinking block with empty text unless the request asks for
  the summary: on Opus 4.7, Opus 4.8 and every Claude 5 model, `summary="auto"` gave an
  empty thinking part (live on 14 models). Any `summary` now adds the knob, with adaptive
  thinking and with a budget alike; every Claude model accepts it. Without `summary`
  nothing changes. DeepSeek, Meta and Moonshot over the Messages wire are unchanged.

## 2.1.0 — 2026-11-05

Streams yield what the provider said, all of it, once (lm15-contract `77f22f4`, MAP-20;
2,132 of 2,132 checks, the same as every lm15 language). Nothing is removed and no field
changes meaning.

- **Parallel tool calls on the Codex subscription arrive with their inputs.** The Codex
  backend sends the arguments of parallel calls only in each call's final
  `response.output_item.done`, never in pieces; every call came back with input `{}`. A
  stream's final copy of an item now completes whatever its pieces did not deliver
  (arguments, message text, a reasoning summary); a piece that contradicts the final copy
  throws `StreamAssemblyError` (`stream_assembly`, `part_index` set) instead of either
  value being chosen.
- **A streamed reasoning summary reads like the complete one:** its parts are joined with a
  newline; they used to run together.
- **Gemini parallel calls sent one per chunk stay separate calls.** gemini-2.5-pro and
  gemini-3-flash-preview send each call in a chunk of its own; every call landed in the
  same slot and their arguments ran into one unreadable input.
- `stream_reader(lm, request)` and `feed!(reader, frame)` read one stream (internal, not
  exported); `stream` and the vet shim go through them. (`response.incomplete` already
  ended a Julia stream with `length`.)

## 2.0.0 — 2026-11-01

The first release of lm15 for Julia, as the package **`LanguageModel15`** (`using
LanguageModel15`). It is numbered 2.0.0 because every lm15 language shares its major
version, the generation of the shared contract it implements (2 since one meaning per
usage counter, below); 1.x was never published for Julia. Until 2026-10-31 it was called `LM15`; Julia's General registry does
not accept that name automatically (fewer than five letters, an acronym), and the request
for an exception went unanswered, so the Julia name spells out what lm15 stands for. The
UUID is unchanged and `LM15` was never registered, so nothing installed from the registry
breaks; a checkout used with `using LM15` must now say `using LanguageModel15`. The error
type `LM15Error` and the `LM15_*` environment variables keep their names: they are shared
with every lm15 language.

Graded by lm15-contract at the commit in
`CONTRACT_PIN` (`cfc3edc`): 1,968 of 1,968 checks, the same count as Python, TypeScript,
Rust, Go and R. The registration first opened on 2026-09-26 at 1,788 checks; while it
waited for review it was moved eight times, so the first published version carries what
landed meanwhile: on 2026-09-30 (contract `57e33d1`, 1,838 checks) the Claude Code and
Claude default changes, on 2026-10-06 (`0f3ea82`, 1,901) the two stream and tool fixes
below, on 2026-10-10 (`880f72c` and `8eedbae`, 1,904) the two key fixes and the structured
answer and thinking budget, on 2026-10-12 (`88bb560`, 1,905) the Muse Code
subscription, on 2026-10-14 (`10645e5`, 1,911) pictures for Jev, on 2026-10-15
(`1cbdc12`, 1,912) a saved cloud login's settings and (`6dc1c5c`, 1,921) bounding boxes,
and on 2026-10-31 (`cfc3edc`, 1,968) one meaning per usage counter.

**One meaning per usage counter (2026-10-31, contract `cfc3edc`):**

- `Usage` means the same on every provider: `input_tokens` includes cached tokens,
  `output_tokens` includes reasoning, the cache, reasoning and audio counters are parts of
  one of the two, and `total_tokens` is their sum (MAP-19). Anthropic input and Gemini and
  xAI output counts are larger than the providers' own numbers, which stay in
  `provider_data`. A `Usage` whose part exceeds its whole, or whose total is not the sum,
  is an `ArgumentError`.
- `estimate(pricing, usage)` returns the exact list price or `nothing` when an unknown
  count could change it; `InferencePricing(; tiers=(PricingTier(; above_input_tokens,
  ...),))` reprices long prompts. The first registered
  version already has this meaning (lm15-contract `changes/2026-10-31-usage-one-meaning.md`).

**Bounding boxes (2026-10-15, contract `6dc1c5c`):**

- `bounding_box("the coffee mug")` declares a judgment whose answer is four numbers, `top`,
  `bottom`, `left` and `right`, each a fraction of the picture from its top-left corner. On
  TypeSafe it is Jev 1.14's Box question (`jev-preview` or `jev-1.14.0`); on other
  providers it is ordinary structured output. A box has no probabilities; pair it with
  `yes_no` to ask whether the thing is there.

**A saved cloud login's settings (2026-10-15, contract `1cbdc12`):**

- A connection saved with `configure(auth, "vertex-anthropic"; method="cloud", answers=...,
  settings=Dict("project" => ..., "location" => ...))` sends that project and location; a
  router `settings` entry for the provider changes only the settings it names. Found in
  lm15-python by Rolf Fredheim (lm15-python #21).

**Pictures for Jev (2026-10-14, contract `10645e5`):**

- A PNG or JPEG `image(...)` in the one user message reaches Jev (provider `typesafe`), on its
  own or beside text and data parts (sent as an ordered list); lm15 adds TypeSafe's
  `TypeSafe-Danger-Zone-Images: true` opt-in header. TypeSafe calls images beta. A picture
  given by URL or file id, another format, audio and video are refused before the wire.

**The Muse Code subscription through the Meta login (2026-10-12, contract `88bb560`):**

- Requests go to the address the key mint names, only when it is an https `meta.ai` host
  (anything else is refused before the key is sent); the connection's `account_label` names
  the plan. `meta:muse-wonder-full-1.0` answers on a Power or Maximum Usage plan. The method
  stays unverified: Meta's terms reserve this key for Muse Code.

**A structured answer and a thinking budget (2026-10-10, contract `8eedbae`):**

- `text(response)` and `parse_json(response)` read a structured answer that came back as a
  `DataPart` (a schema with a boolean or enum property is a judgment request, answered that
  way); they returned `nothing` and failed.
- `Reasoning(; thinking_budget=1024)` works without `effort`: the highest level whose budget is
  at or below the given one, `"minimal"` below 1024. `effort="none"` says lm15 spells it `"off"`.

**A refused key, and a key in the wrong argument:**

- **A wrong or expired key is `AuthError` on every provider.** Gemini and xAI answer a
  key they refuse with HTTP 400, and lm15 raised `InvalidRequestError`. Gemini is
  recognized by the reason its error carries (`API_KEY_INVALID`), xAI by its exact
  sentence; any other Gemini 400 is still `InvalidRequestError`. lm15-contract MAP-18
  (`changes/2026-10-10-bad-key-and-misplaced-key.md`); contract `880f72c`.
- **A key passed as `credential=` is never printed.** `credential=` takes the name of a
  cloud identity; a key given there was repeated in the refusal, and so in logs. The
  refusal now says the value is not shown because it may be a key, and that a key goes in
  `api_key`.

**Long streams and tools without a description:**

- **Long streamed replies no longer fail at the last moment.** `parse_sse` refused a line
  over 64 KiB and an event over 1 MiB, and real streams are larger: OpenAI Responses
  repeats the whole response, system prompt included, in its first and last events, and
  Gemini sends a 4K image as one 29.7 MB line. There is no default limit now, as a
  non-streamed reply never had one; `max_line_bytes=` / `max_event_bytes=` remain as opt-in
  caps (`nothing` by default). The reader copies whole runs of bytes instead of one byte at
  a time (a 30 MB line: 0.5 s, was 3.1 s). lm15-contract INV-056
  (`changes/2026-10-06-sse-event-bound.md`); contract `0f3ea82`.
- **A tool with no description works on every provider.** A `FunctionTool` with only a
  name and parameters was sent with `"description": null`, which Anthropic and Groq refuse
  with a 400. The description key is now left out when the tool has none (`""` counts as
  none, as it already does in lm15's own JSON), on every wire, including Gemini cached
  prefixes, Gemini Live and the OpenAI Realtime session. A tool with a description is sent
  exactly as before. lm15-contract MAP-17
  (`changes/2026-10-02-tool-description-absent.md`); contract `f6465c8`.

**Claude Code and Claude defaults** (lm15-contract
`changes/2026-09-30-claude-code-client-version.md`):

- **The Claude Code release is current and settable.** The `claude-code` door claims
  Claude Code 2.1.285 (it claimed 2.1.170, which `claude-opus-5-5` refuses). When a model
  needs a newer release, pass `settings=Dict("client_version" => "...")` (a router's
  `RouterConfig(settings=...)` entry, or the client's own) or set
  `LM15_CLAUDE_CODE_VERSION`, which a router reads. The Codex door's `client_version` is
  the same setting (`LM15_CODEX_CLIENT_VERSION`). `explain_auth` prints the release and
  where it came from.
- **The refusal says what to change**: updating the `claude` program does not move what
  LM15 sends, so the error names the setting.
- **A settings entry nothing reads raises** `NotConfiguredError` (it was ignored).
- **Claude's default `max_tokens` is the model's own output ceiling**: 128000 for the 4.6
  generation and later, 64000 for 4.5 (it was 16384); on the manual class it covers the
  thinking budget. Other models on Anthropic-dialect servers keep 16384.
- **Chat Completions ingest** reads `input_audio` in ogg, opus, flac, aac, aiff, webm
  and mpeg as their true media types (contract `307925a`).

Brought up from the 2026-09-11 contract (`cfed007`) with everything ratified since:

- **Providers.** DeepInfra, Together AI, Fireworks AI and Parasail (registry, presets
  with per-model rules, litellm prefixes); TypeSafe (`TypeSafeLM`). The compat knob
  `reasoning_off`. Chat model listings read a bare array; a flat `cached_tokens` counts.
  Provider tables, routing rules, litellm prefixes and the MAP-15 "no such model" forms
  are copied from the reference as data (`tools/import_tables.py`).
- **Judgments (MAP-14).** `DataPart`/`data`, `Config.probabilities`, the schema helpers
  `judgments`, `choice`, `yes_no`, `score`; the Anthropic and Gemini schema rewrites;
  TypeSafe's classification; candidate-sequence likelihood on vLLM; `data(answer)`,
  `probabilities(answer)`, `data_part(answer)`, `expected_level`.
- **Gemini schemas (MAP-16).** A schema goes to `responseJsonSchema`/`parametersJsonSchema`
  exactly when Gemini's OpenAPI field cannot carry it.
- **Refusals name their field.** Message media a wire has no slot for, and stored-cache
  resources where there is no such tier, raise `UnsupportedFeatureError` with `feature`.
- **Cloud identity.** Named credentials (`platform`, `workload`, `environment`, `cli`),
  `CredentialSource` provenance on auth errors, endpoint roots and the vendors' endpoint
  variables, settings with their origin in `explain_auth`, the Google project from
  gcloud's configuration and the metadata server, API keys on `vertex`, token-shaped
  strings sent as bearer tokens, Google IAM guidance on 401/403.
- **Managed sign-in (AUTH-12–26).** `Auth` over the shared credential file or memory:
  xAI, Claude, ChatGPT, GitHub Copilot, Kimi Code, Meta and OpenRouter sign-ins
  (profiles copied from the contract), saved keys and recipes, replacement, logout with
  the suppression marker, durable cancellation, renewal under the cross-process lock,
  bound clients, `LM15.Interactive.connect`, managed routers and the managed doctor.
  R3: an unusable or signed-out xAI subscription blocks the ambient key.
- **Reply faults and diagnostics.** Compressed replies inflated or refused by name
  (INV-053); a non-JSON success is a `ProviderError` (INV-054); invalid Unicode refused
  before the wire (INV-055); rate-limit header snapshots, millisecond retry hints and
  more request-id headers on every HTTP error; handshake evidence on in-stream errors.
- **Transport.** `Timeouts` and `max_connections` with the ratified defaults.
- **Live sessions.** Bounded turn collection (`CollectionLimitError`).
- **Streams.** Scores kept for whole tokens before a client-side stop, coverage marked
  incomplete otherwise (`logprobs_complete`).
- **Routing.** Router-local provider declarations (`RouterConfig(providers=...)`);
  a router-made `CachedPrefix` keeps its provider; a client strips its own
  `provider:` prefix.
- **Package.** Registrable `Project.toml` (compat for every dependency, tested at the
  lower bounds on Julia 1.10), Aqua checks, CI for the contract harness, CompatHelper,
  TagBot; the manual builds in a network-free sandbox.

## 0.3.0 and earlier

Development versions, installed from GitHub only.
