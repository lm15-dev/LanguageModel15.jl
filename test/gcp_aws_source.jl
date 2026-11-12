# Google external_account with an AWS source (lm15-contract spec/auth.md AUTH-1 gcp-chain,
# amended 2026-11-12; changes/2026-11-12-gcp-aws-source.md). The subject token is pinned byte
# for byte by auth/token-vectors.json (computed by google-auth); these walk the acquisition:
# where the AWS identity comes from, then STS, then impersonation.

using LanguageModel15: ChainContext, gcp_info, NotConfiguredError, HTTP

const AWS_AUDIENCE = "//iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p/providers/aws"
const AWS_IMPERSONATE = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/sa@p.iam.gserviceaccount.com:generateAccessToken"
const AWS_NOW = 1_789_862_400.0  # 2026-09-20T00:00:00Z

aws_source(; extra...) = Dict{String,Any}(
    "environment_id" => "aws1",
    "region_url" => "http://169.254.169.254/latest/meta-data/placement/availability-zone",
    "url" => "http://169.254.169.254/latest/meta-data/iam/security-credentials",
    "regional_cred_verification_url" => "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15",
    (String(k) => v for (k, v) in extra)...,
)
aws_info(source) = Dict{String,Any}(
    "type" => "external_account", "audience" => AWS_AUDIENCE,
    "subject_token_type" => "urn:ietf:params:aws:token-type:aws4_request",
    "token_url" => "https://sts.googleapis.com/v1/token", "credential_source" => source,
    "service_account_impersonation_url" => AWS_IMPERSONATE,
)
const AWS_GOOGLE = [
    "https://sts.googleapis.com/" => """{"access_token":"federated","expires_in":3600,"token_type":"Bearer"}""",
    "https://iamcredentials.googleapis.com/" => """{"accessToken":"sa-token","expireTime":"2026-09-20T01:00:00Z"}""",
]
function aws_ctx(env, answers)
    calls = Any[]
    http = function (method, url, headers, body, timeout)
        push!(calls, (method, url, Dict(headers), body))
        for (prefix, reply) in answers
            startswith(url, prefix) && return 200, Dict{String,String}(), Vector{UInt8}(codeunits(reply))
        end
        error("unexpected request $method $url")
    end
    return calls, ChainContext(; env=Dict{String,String}(env), home="/h", files=Dict{String,String}(), clock=() -> AWS_NOW, http)
end
function aws_signed(calls)
    sts = calls[findfirst(c -> startswith(c[2], "https://sts.googleapis.com/"), calls)]
    body = JSON.parse(String(copy(sts[4] isa AbstractString ? codeunits(sts[4]) : sts[4])))
    @test body["subjectTokenType"] == "urn:ietf:params:aws:token-type:aws4_request"
    signed = JSON.parse(HTTP.URIs.unescapeuri(body["subjectToken"]))
    return signed["url"], Dict(h["key"] => h["value"] for h in signed["headers"])
end

@testset "GCP external_account with an AWS source" begin
    @testset "on ECS the task role signs, then STS, then impersonation" begin
        calls, ctx = aws_ctx(
            ["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" => "/v2/credentials/abc", "AWS_REGION" => "us-east-2"],
            ["http://169.254.170.2/v2/credentials/abc" => """{"AccessKeyId":"ASIATASK","SecretAccessKey":"s","Token":"task-session","Expiration":"2026-09-20T06:00:00Z"}""", AWS_GOOGLE...],
        )
        @test gcp_info(ctx, aws_info(aws_source())).value == "sa-token"
        @test [c[2] for c in calls] == ["http://169.254.170.2/v2/credentials/abc", "https://sts.googleapis.com/v1/token", AWS_IMPERSONATE]
        url, h = aws_signed(calls)
        @test url == "https://sts.us-east-2.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15"
        @test startswith(h["Authorization"], "AWS4-HMAC-SHA256 Credential=ASIATASK/20260920/us-east-2/sts/aws4_request, SignedHeaders=host;x-amz-date;x-amz-security-token, ")
        @test h["x-amz-security-token"] == "task-session"
        @test h["x-goog-cloud-target-resource"] == AWS_AUDIENCE
        @test any(((k, v),) -> lowercase(k) == "authorization" && v == "Bearer federated", calls[3][3])
    end
    @testset "on EC2 IMDSv2 once, the zone's region, the role's credentials" begin
        calls, ctx = aws_ctx(String[], [
            "http://169.254.169.254/latest/api/token" => "imds-session",
            "http://169.254.169.254/latest/meta-data/placement/availability-zone" => "eu-west-1b",
            "http://169.254.169.254/latest/meta-data/iam/security-credentials/web" => """{"Code":"Success","AccessKeyId":"ASIAEC2","SecretAccessKey":"s","Token":"t"}""",
            "http://169.254.169.254/latest/meta-data/iam/security-credentials" => "web\n",
            AWS_GOOGLE...,
        ])
        @test gcp_info(ctx, aws_info(aws_source(; imdsv2_session_token_url="http://169.254.169.254/latest/api/token"))).value == "sa-token"
        @test count(c -> c[1] == "PUT", calls) == 1
        @test calls[1][3]["X-aws-ec2-metadata-token-ttl-seconds"] == "300"
        @test all(c -> get(c[3], "X-aws-ec2-metadata-token", nothing) == "imds-session", calls[2:4])
        @test startswith(aws_signed(calls)[1], "https://sts.eu-west-1.amazonaws.com?")
    end
    @testset "the environment's keys win and no endpoint is asked" begin
        calls, ctx = aws_ctx(["AWS_ACCESS_KEY_ID" => "AKIDENV", "AWS_SECRET_ACCESS_KEY" => "s", "AWS_DEFAULT_REGION" => "ca-central-1", "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" => "/v2/credentials/abc"], AWS_GOOGLE)
        gcp_info(ctx, aws_info(aws_source()))
        _, h = aws_signed(calls)
        @test !haskey(h, "x-amz-security-token")
        @test occursin("AKIDENV/20260920/ca-central-1/sts", h["Authorization"])
        @test length(calls) == 2
    end
    @testset "a malformed source or no AWS identity is refused before any request" begin
        for (source, why) in [
            (Dict{String,Any}("environment_id" => "aws2", "regional_cred_verification_url" => "https://sts.{region}.amazonaws.com"), "only aws1"),
            (Dict{String,Any}("environment_id" => "aws1"), "regional_cred_verification_url"),
            (Dict{String,Any}("environment_id" => "azure1", "regional_cred_verification_url" => "https://x"), "environment_id"),
        ]
            calls, ctx = aws_ctx(["AWS_REGION" => "us-east-1", "AWS_ACCESS_KEY_ID" => "a", "AWS_SECRET_ACCESS_KEY" => "s"], Pair{String,String}[])
            err = try gcp_info(ctx, aws_info(source)); nothing catch e; e end
            @test err isa NotConfiguredError && occursin(why, sprint(showerror, err))
            @test isempty(calls)
        end
        source = aws_source(); delete!(source, "url")
        calls, ctx = aws_ctx(["AWS_REGION" => "us-east-1"], Pair{String,String}[])
        err = try gcp_info(ctx, aws_info(source)); nothing catch e; e end
        @test err isa NotConfiguredError && occursin("AWS_ACCESS_KEY_ID nor a container endpoint", sprint(showerror, err))
    end
end
