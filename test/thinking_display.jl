module ThinkingDisplayTests
using Test, LanguageModel15

# MAP-7 rule 7 (amended 2026-11-07): a summary asked for on Claude is thinking.display
# "summarized"; Opus 4.7, 4.8 and every Claude 5 hide the thinking without it. The contract
# pins the adaptive and budget wires (anthropic.reasoning_summary, ..._budget); these pin what
# its cases do not: no summary, no knob; other servers of the wire, no knob.

thinking(lm, model, reasoning) =
    get(LanguageModel15.JSON.parse(String(copy(build_request(lm, Request(model, user("q"); config=Config(; reasoning))).body))),
        "thinking", nothing)
claude() = AnthropicLM(; api_key="k", env=Dict{String,String}())

@testset "thinking display (MAP-7 rule 7, amended 2026-11-07)" begin
    @test thinking(claude(), "claude-opus-5-5", Reasoning(; effort="high", summary="auto")) ==
          Dict("type" => "adaptive", "display" => "summarized")
    @test thinking(claude(), "claude-opus-5-5", Reasoning(; effort="high", summary="detailed")) ==
          Dict("type" => "adaptive", "display" => "summarized")
    @test thinking(claude(), "claude-haiku-4-5-20251001", Reasoning(; effort="low", summary="auto")) ==
          Dict("type" => "enabled", "budget_tokens" => 2048, "display" => "summarized")
    @test thinking(claude(), "claude-opus-5-5", Reasoning(; effort="high")) == Dict("type" => "adaptive")
    for (compat, model) in (("deepseek", "deepseek-v4-flash"), ("meta", "muse-spark-1.3"), ("moonshotai", "kimi-k3"))
        lm = AnthropicLM(; compat, api_key="k", env=Dict{String,String}())
        @test !occursin("display", repr(thinking(lm, model, Reasoning(; effort="high", summary="auto"))))
    end
end

end
