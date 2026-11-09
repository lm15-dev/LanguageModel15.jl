module TinkerTests
using Test, LanguageModel15
const LM15 = LanguageModel15

# Tinker (Thinking Machines): the two doors, the reasoning switch per base family, a
# checkpoint that follows its declared base model, URI model names, FastAPI error bodies
# (MAP-21), the stop sequence returned in the text (MAP-22) and the catalog's fine-tune
# origin (MAP-23). lm15-contract changes/2026-11-09-tinker-live.md; the harness pins the
# same rules through the corpus, these tests keep them visible here.

const CK = "tinker://e68146d2-1a2e-56e8-b42f-1f5957705501:train:0/sampler_weights/lm15-untrained"
function chat(; base_models=Dict{String,String}())
    return ProviderLM("tinker"; api_key="k", env=Dict{String,String}(), base_models)
end
config(; kw...) = Config(; kw...)
function wire(lm, model, cfg)
    return LM15.JSON.parse(
        String(copy(build_request(lm, Request(model, user("hi"); config=cfg)).body))
    )
end
function effort(lm, model, e)
    return get(
        wire(lm, model, config(; reasoning=Reasoning(; effort=e))), "reasoning_effort", missing
    )
end

@testset "tinker: doors, URI names, aliases" begin
    @test LM15.PROVIDERS["tinker"].access.env_keys == ("TINKER_API_KEY",)
    @test LM15.PROVIDERS["tinker-anthropic"].access.env_keys == ("TINKER_API_KEY",)
    router = LMRouter(RouterConfig(; env=Dict{String,String}()))
    for (model, provider, wire_model) in (
        (CK, "tinker", CK),
        ("tinker:" * CK, "tinker", CK),
        ("tinker-anthropic:" * CK, "tinker-anthropic", CK),
        ("thinkingmachines:" * CK, "tinker", CK),
        ("thinkingmachines:Qwen/Qwen3-8B", "tinker", "Qwen/Qwen3-8B"),
    )
        r = resolve(router, model)
        @test (r.provider, r.model) == (provider, wire_model)
    end
    @test_throws UnknownModelError resolve(router, "openai://x")
    @test LM15.openai_chat_model_string("thinkingmachines/Qwen/Qwen3-8B") == "tinker:Qwen/Qwen3-8B"
end

@testset "tinker: reasoning per base family" begin
    lm = chat()
    for (model, off) in (
        ("thinkingmachines/Inkling-Small", "none"),
        ("Qwen/Qwen3.5-4B", false),
        ("moonshotai/Kimi-K2.6", false),
        ("nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16", false),
        ("Qwen/Qwen3.8-27B", false),
        ("deepseek-ai/DeepSeek-V4.1-Flash:peft:262144", false),
        (CK, false),
    )
        @test effort(lm, model, "off") === off
        @test isempty(
            plan(
                lm, Request(model, user("hi"); config=config(; reasoning=Reasoning(; effort="off")))
            ),
        )
    end
    @test effort(lm, "Qwen/Qwen3.5-4B", "high") === true
    records = plan(
        lm,
        Request(
            "Qwen/Qwen3.5-4B", user("hi"); config=config(; reasoning=Reasoning(; effort="high"))
        ),
    )
    @test length(records) == 1 && records[1].asked == "high" && records[1].applied == "on"
    for model in ("thinkingmachines/Inkling", "openai/gpt-oss-20b", CK)
        @test effort(lm, model, "low") == "low"
    end
end

@testset "tinker: a checkpoint follows its declared base model" begin
    @test effort(chat(; base_models=Dict(CK => "thinkingmachines/Inkling-Small")), CK, "off") ==
        "none"
    @test effort(chat(; base_models=Dict(CK => "Qwen/Qwen3.5-4B")), CK, "medium") === true
    router = LMRouter(
        RouterConfig(;
            env=Dict("TINKER_API_KEY" => "k"), base_models=Dict(CK => "thinkingmachines/Inkling")
        ),
    )
    @test effort(LM15.lm(router, CK), CK, "off") == "none"
    @test_throws ArgumentError LMRouter(RouterConfig(; base_models=Dict(CK => "")))
end

@testset "tinker: response_format dropped and recorded" begin
    for fmt in (
        Dict("type" => "json_object"),
        Dict("type" => "json_schema", "name" => "x", "schema" => Dict("type" => "object")),
    )
        lm = chat()
        request = Request(
            "thinkingmachines/Inkling", user("hi"); config=config(; response_format=fmt)
        )
        @test !haskey(
            LM15.JSON.parse(String(copy(build_request(lm, request).body))), "response_format"
        )
        @test [r.field for r in plan(lm, request)] == ["config.response_format"]
    end
end

@testset "tinker: MAP-22 the returned stop sequence is cut" begin
    lm = chat()
    request = Request(
        "thinkingmachines/Inkling-Small", user("count"); config=config(; stop=(" 7",))
    )
    reply = """{"id":"x","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"1 2 3 4 5 6 7"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12}}"""
    response = parse_response(
        lm, request, HttpResponse(; status=200, body=Vector{UInt8}(codeunits(reply)))
    )
    @test text(response) == "1 2 3 4 5 6"
    @test response.usage.input_tokens == 5
    plain = ProviderLM("openai-chat"; api_key="k", env=Dict{String,String}())
    other = Request("gpt-4.1-mini", user("x"); config=config(; stop=("END",)))
    body = """{"id":"x","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"a END b"},"finish_reason":"stop"}]}"""
    @test text(
        parse_response(
            plain, other, HttpResponse(; status=200, body=Vector{UInt8}(codeunits(body)))
        ),
    ) == "a END b"
end

@testset "tinker: MAP-21 detail bodies and MAP-15 forms" begin
    lm = chat()
    for (status, body, T) in (
        (401, """{"detail":"Unable to validate api-key"}""", AuthError),
        (404, """{"detail":"Weights not found for model_path $CK"}""", UnsupportedModelError),
        (400, """{"detail":"Sampling is not supported for x. (org)"}""", UnsupportedModelError),
        (
            400,
            """{"detail":"model_path 'tinker://x' is not a valid tinker path. Expected"}""",
            UnsupportedModelError,
        ),
        (
            422,
            """{"detail":"model returned no tool call when tool_choice required one"}""",
            InvalidRequestError,
        ),
    )
        @test LM15.normalize_error(lm, status, body) isa T
    end
    @test LM15.detail_message(
        Dict(
            "detail" => "Validation Error",
            "errors" => [
                Dict("loc" => "body -> messages -> 0 -> role", "msg" => "Input should be 'system'"),
            ],
        ),
    ) == "Validation Error: body -> messages -> 0 -> role: Input should be 'system'"
end

@testset "tinker: MAP-23 the catalog names each checkpoint's base" begin
    body = """{"object":"list","data":[{"id":"$CK","object":"model","created":1,"owned_by":"x","base_model":"Qwen/Qwen3.5-4B"}]}"""
    models = LM15.parse_models_response(
        chat(), HttpResponse(; status=200, body=Vector{UInt8}(codeunits(body)))
    )
    @test length(models) == 1
    @test (models[1].origin.type, models[1].origin.base_model) == ("fine-tune", "Qwen/Qwen3.5-4B")
end

end
