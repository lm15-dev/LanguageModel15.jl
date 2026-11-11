module EmptyPartsTests
using Test, LanguageModel15
using LanguageModel15: JSON

# MAP-24 (lm15-contract changes/2026-11-11-empty-parts.md, issue #3): a part with nothing for
# a wire writes nothing. The contract's vectors (mapping/empty-parts.json) and the history
# replay pin the bytes for the four dialects through the vet shim. These pin what they do
# not: nothing is recorded, the caller's request is not touched, the state comes back on its
# own dialect.

body(lm, request) = JSON.parse(String(copy(build_request(lm, request).body)))
function canonical(messages...; model, kw...)
    d = Dict{String,Any}("model" => model, "messages" => collect(messages))
    for (key, value) in kw
        d[String(key)] = value
    end
    return LanguageModel15.from_dict(Request, d)
end
text(value) = Dict("type" => "text", "text" => value)
message(role, parts...) = Dict("role" => role, "parts" => collect(parts))

# What lm15 reads from a Responses reasoning item with no summary (MAP-7 rules 9 and 11).
const HIDDEN = Dict(
    "type" => "thinking",
    "text" => "",
    "continuation" => [
        Dict(
            "provider" => "openai",
            "kind" => "reasoning_item",
            "data" => Dict("id" => "rs_1", "encrypted_content" => "gAAAA"),
        ),
    ],
)
const CALL = Dict(
    "type" => "tool_call",
    "id" => "call_1",
    "name" => "delete_program",
    "input" => Dict{String,Any}(),
)
function result(content...)
    return message(
        "tool",
        Dict(
            "type" => "tool_result",
            "id" => "call_1",
            "name" => "delete_program",
            "content" => collect(content),
        ),
    )
end

# The history of issue #3: two steps answered by an OpenAI Responses model with hidden
# reasoning, then a new user message.
function report(model)
    return canonical(
        message("user", text("Delete the test program now.")),
        message("assistant", HIDDEN, CALL),
        result(text("ok")),
        message("assistant", HIDDEN, text("Deleted.")),
        message("user", text("hello"));
        model,
    )
end

claude(; kw...) = AnthropicLM(; api_key="k", env=Dict{String,String}(), kw...)
function adapters()
    return (
        (
            "claude-opus-5-5",
            (; kw...) -> AnthropicLM(; api_key="k", env=Dict{String,String}(), kw...),
        ),
        (
            "gemini-2.5-flash",
            (; kw...) -> GeminiLM(; api_key="k", env=Dict{String,String}(), kw...),
        ),
        ("gpt-5.4", (; kw...) -> OpenAILM(; api_key="k", env=Dict{String,String}(), kw...)),
        ("gpt-5.4", (; kw...) -> OpenAIChatLM(; api_key="k", env=Dict{String,String}(), kw...)),
    )
end

@testset "a part with nothing for a wire writes nothing (MAP-24)" begin
    @testset "the report builds a body Claude accepts" begin
        wire = body(claude(), report("claude-opus-5-5"))["messages"]
        @test [m["role"] for m in wire] == ["user", "assistant", "user", "assistant", "user"]
        @test wire[2]["content"] == [
            Dict(
                "type" => "tool_use",
                "id" => "call_1",
                "name" => "delete_program",
                "input" => Dict(),
            ),
        ]
        @test wire[4]["content"] == [Dict("type" => "text", "text" => "Deleted.")]
        @test !occursin("\"text\":\"\"", JSON.serialize(wire))
    end

    @testset "nothing is recorded under any policy, and the history is not touched" begin
        for (model, make) in adapters()
            request = report(model)
            before = JSON.serialize(LanguageModel15.to_dict(request))
            for policy in ("note", "silent", "refuse")
                lm = make(; adaptations=policy)
                @test isempty([a for a in plan(lm, request) if startswith(a.field, "messages")])
                @test build_request(lm, request) !== nothing  # "refuse" throws on any recorded deviation
            end
            @test JSON.serialize(LanguageModel15.to_dict(request)) == before
        end
    end

    @testset "the state goes back natively on its own dialect" begin
        body(claude(), report("claude-opus-5-5"))
        items = body(OpenAILM(; api_key="k", env=Dict{String,String}()), report("gpt-5.4"))["input"]
        one = Dict(
            "type" => "reasoning", "id" => "rs_1", "encrypted_content" => "gAAAA", "summary" => []
        )
        @test [i for i in items if get(i, "type", nothing) == "reasoning"] == [one, one]
    end

    @testset "an empty thinking part with Claude's signature is still a thinking block" begin
        signed(signature) = Dict(
            "type" => "thinking",
            "text" => "",
            "continuation" => [
                Dict(
                    "provider" => "anthropic",
                    "kind" => "thinking_signature",
                    "data" => Dict("signature" => signature),
                ),
            ],
        )
        kept = body(
            claude(),
            canonical(
                message("user", text("hi")),
                message("assistant", signed("sig"), CALL),
                result(text("ok"));
                model="claude-opus-5-5",
            ),
        )
        @test kept["messages"][2]["content"][1] ==
            Dict("type" => "thinking", "thinking" => "", "signature" => "sig")
    end

    @testset "a cache mark asked on a message left out goes to the one written before it" begin
        # Not pinned by the contract (stated in the change entry): the reference's choice.
        wire = body(
            claude(),
            canonical(
                message("user", text("Here is the manual.")),
                message("assistant", HIDDEN),
                message("user", text("And the appendix."));
                model="claude-opus-5-5",
                config=Dict("cache" => Dict("mode" => "auto", "prefix_until_index" => 1)),
            ),
        )["messages"]
        @test length(wire) == 2
        @test haskey(last(wire[1]["content"]), "cache_control")
        @test !haskey(last(wire[2]["content"]), "cache_control")
    end

    @testset "a tool result keeps its empty output; an empty block beside an image is left out" begin
        image = Dict(
            "type" => "image",
            "media_type" => "image/png",
            "url" => "https://example.com/receipt.png",
        )
        for (content, expected) in (
            ((text(""),), ""),
            (
                (text(""), image),
                [
                    Dict(
                        "type" => "image",
                        "source" =>
                            Dict("type" => "url", "url" => "https://example.com/receipt.png"),
                    ),
                ],
            ),
        )
            wire = body(
                claude(),
                canonical(
                    message("user", text("hi")),
                    message("assistant", CALL),
                    result(content...);
                    model="claude-opus-5-5",
                ),
            )["messages"]
            block = wire[3]["content"][1]
            @test block["type"] == "tool_result"
            @test block["content"] == expected
        end
    end

    @testset "whitespace is content; an assistant data part is its JSON on every wire" begin
        wire = body(
            claude(),
            canonical(
                message("user", text("hi")),
                message("assistant", text("\n")),
                message("user", text("again"));
                model="claude-opus-5-5",
            ),
        )["messages"]
        @test wire[2]["content"] == [Dict("type" => "text", "text" => "\n")]
        data = message("assistant", Dict("type" => "data", "value" => Dict("paid" => true)))
        chat = body(
            OpenAIChatLM(; api_key="k", env=Dict{String,String}()),
            canonical(
                message("user", text("Paid?")),
                data,
                message("user", text("Sure?"));
                model="gpt-5.4",
            ),
        )
        @test chat["messages"][2] == Dict("role" => "assistant", "content" => "{\"paid\":true}")
    end
end

end
