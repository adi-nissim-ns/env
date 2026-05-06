RTK-AI — Usage Guide
====================

RTK (Rust Token Killer) wraps Bash tool calls made by Claude Code and
compresses their output before it reaches the LLM context window, saving
60-90% of tokens on shell commands like git, ls, grep, etc.

Note: Claude Code's built-in tools (Read, Grep, Glob) bypass Bash entirely
and are not affected by rtk.


INSTALLATION
------------
Run the installer directly — no manual unpacking needed:

    bash install.sh --install rtk-linux-x86_64.tar.gz

If install.sh and the tarball are in the same directory, the tarball
argument can be omitted:

    bash install.sh --install

To uninstall:

    bash install.sh --uninstall


TURNING IT ON AND OFF
---------------------
Per-command (skip rtk for one command):

    RTK_DISABLED=1 git status

Globally off:

    rtk init -g --uninstall

Globally on (re-install hook):

    rtk init -g
    # If it defaults to N in non-interactive mode, manually add to
    # ~/.claude/settings.json — see the install script for the exact block.

The hook lives in ~/.claude/settings.json. You can also just remove or
restore the "hooks" block there directly.


CHECKING TOKEN SAVINGS
----------------------
Overall savings across all sessions:

    rtk gain
    rtk gain --daily     # detailed daily breakdown
    rtk gain --weekly    # weekly breakdown
    rtk gain --monthly   # monthly breakdown

Per Claude Code session breakdown:

    rtk session

Dollar-value estimate (cross-references Claude Code spend vs rtk savings):

    rtk cc-economics


VSCODE REMOTE SSH
-----------------
No extra steps needed. The hook uses an absolute path to the rtk binary so
it works regardless of what PATH VS Code inherits from the SSH session.
Both the Claude CLI and the VS Code Claude extension read the same
~/.claude/settings.json.


BUILDING FROM SOURCE
--------------------
If you want to rebuild from source instead of using the pre-compiled binary
(e.g. after an upstream rtk release), run on a build server:

    bash build-package.sh

Requires: Rust >= 1.86 (run `rustup update stable` if older).
On these servers cargo also needs: LD_LIBRARY_PATH=/tools/common/pkgs/openssl11/lib


CLAUDE CODE SKILL
-----------------
A Claude Code skill file is provided at:

    .claude/skills/install-rtk.md

Copy it to ~/.claude/skills/ on any machine that has Claude Code, then
invoke with /install-rtk to have Claude walk through the full installation
including source audit, build, and hook setup.
