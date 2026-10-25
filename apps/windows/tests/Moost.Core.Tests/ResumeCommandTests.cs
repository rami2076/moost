using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance G2（復帰コマンドのパターン・Windows 版）。
/// macOS の <c>LaunchTests.swift</c> と同じ観点を、PowerShell の表記で検証する。
/// </summary>
public class ResumeCommandTests
{
    private const string Project = "C:\\work\\alpha";
    private const string Session = "s-1";

    [Fact]
    public void ClaudeResume_MovesFirst_ThenRemovesEnv_ThenRunsResume()
    {
        var command = ResumeCommand.ClaudeResume(Project, Session);

        var cdIndex = command.IndexOf("Set-Location -LiteralPath 'C:\\work\\alpha'; ", StringComparison.Ordinal);
        var envIndex = command.IndexOf("Get-ChildItem Env:CLAUDE_*", StringComparison.Ordinal);
        var runIndex = command.IndexOf("claude --resume 's-1'", StringComparison.Ordinal);

        Assert.Equal(0, cdIndex);
        Assert.True(envIndex > 0, command);
        Assert.True(runIndex > envIndex, command);
        Assert.EndsWith("claude --resume 's-1'", command, StringComparison.Ordinal);
    }

    [Fact]
    public void ClaudeNewSession_HasNoResumeFlag()
    {
        var command = ResumeCommand.ClaudeNewSession(Project);

        Assert.EndsWith("claude", command, StringComparison.Ordinal);
        Assert.DoesNotContain("--resume", command);
    }

    [Fact]
    public void CodexResume_UsesResumeSubcommand()
    {
        Assert.EndsWith(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; codex resume 's-1'",
            ResumeCommand.CodexResume(Project, Session),
            StringComparison.Ordinal);
    }

    [Fact]
    public void CodexResume_OmitsSetLocation_WhenProjectPathIsEmpty()
    {
        Assert.Equal("codex resume 's-1'", ResumeCommand.CodexResume("", Session));
    }

    [Fact]
    public void PiResume_AddsProviderAndModelOnlyWhenSpecified()
    {
        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; pi --session 's-1'",
            ResumeCommand.PiResume(Project, Session));

        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; pi --session 's-1' --provider 'dspark' --model 'qwen3'",
            ResumeCommand.PiResume(Project, Session, "dspark", "qwen3"));

        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; pi --session 's-1' --model 'qwen3'",
            ResumeCommand.PiResume(Project, Session, model: "qwen3"));
    }

    [Fact]
    public void PiNewSession_HasNoSessionFlag()
    {
        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; pi --provider 'dspark'",
            ResumeCommand.PiNewSession(Project, "dspark"));
    }

    [Fact]
    public void HermesResume_UsesChatResume()
    {
        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; hermes chat --resume 's-1'",
            ResumeCommand.HermesResume(Project, Session));

        Assert.Equal("hermes chat --resume 's-1'", ResumeCommand.HermesResume(null, Session));
        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\alpha'; hermes chat",
            ResumeCommand.HermesNewSession(Project));
    }

    [Theory]
    [InlineData(ResumeCommand.ClaudeAgentId, "claude --resume 's-1'")]
    [InlineData(ResumeCommand.CodexAgentId, "codex resume 's-1'")]
    [InlineData(ResumeCommand.PiAgentId, "pi --session 's-1'")]
    [InlineData(ResumeCommand.HermesAgentId, "hermes chat --resume 's-1'")]
    public void Resume_ProducesMoveThenResume_ForEveryKnownAgent(string agent, string expectedTail)
    {
        var command = ResumeCommand.Resume(agent, Project, Session);

        Assert.NotNull(command);
        Assert.StartsWith("Set-Location -LiteralPath 'C:\\work\\alpha'; ", command, StringComparison.Ordinal);
        Assert.EndsWith(expectedTail, command, StringComparison.Ordinal);
    }

    [Fact]
    public void Resume_ReturnsNull_ForUnknownAgent()
    {
        Assert.Null(ResumeCommand.Resume("gemini", Project, Session));
        Assert.Null(ResumeCommand.NewSession("gemini", Project));
    }

    [Fact]
    public void GeneratedCommands_ContainNoDoubleQuotes()
    {
        // 端末起動時にコマンドライン引数として渡すため、二重引用符は使わない（二重エスケープの元）
        var commands = new[]
        {
            ResumeCommand.ClaudeResume(Project, Session),
            ResumeCommand.ClaudeNewSession(Project),
            ResumeCommand.CodexResume(Project, Session),
            ResumeCommand.PiResume(Project, Session, "p", "m"),
            ResumeCommand.HermesResume(Project, Session),
        };

        foreach (var command in commands)
        {
            Assert.DoesNotContain("\"", command);
        }
    }

    [Fact]
    public void DangerousProjectPath_IsQuotedAsSingleLiteral()
    {
        const string weird = "C:\\work\\we ird'; Write-Output INJECTED; '$x";
        var command = ResumeCommand.CodexResume(weird, Session);

        // 期待する形（' は '' に二重化され、1 つのリテラルになる）
        Assert.Equal(
            "Set-Location -LiteralPath 'C:\\work\\we ird''; Write-Output INJECTED; ''$x'; codex resume 's-1'",
            command);
    }

    [Fact]
    public void IsInternalEnvVar_MatchesClaudePrefixAndKnownNames()
    {
        Assert.True(ClaudeEnvironment.IsInternalEnvVar("CLAUDE_CODE_CHILD_SESSION"));
        Assert.True(ClaudeEnvironment.IsInternalEnvVar("CLAUDECODE"));
        Assert.True(ClaudeEnvironment.IsInternalEnvVar("AI_AGENT"));
        Assert.False(ClaudeEnvironment.IsInternalEnvVar("CLAUDECODEX"));
        Assert.False(ClaudeEnvironment.IsInternalEnvVar("PATH"));
        Assert.False(ClaudeEnvironment.IsInternalEnvVar("OTHER"));
    }
}
