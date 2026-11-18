<center>

<h1 align="center"><i>apathy.</i></h1>
<p align="center"><code>'command not found'</code> – you, probably, after writing your prompt into the terminal like an idiot.</p>
<p align="center">
  <a href="https://github.com/sifex/apathy/actions/workflows/ci.yml"><img src="https://github.com/sifex/apathy/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://github.com/sifex/apathy/releases"><img src="https://img.shields.io/static/v1?label=version&color=blue&message=0.1.0" alt="version"></a> <!-- x-release-please-version -->
  <img src="https://img.shields.io/badge/zsh-5.8%2B-blue" alt="zsh 5.8+">
</p>

</center>

<p align="center">
  <a href=".github/media/demo.mp4"><img src=".github/media/demo.gif" alt="apathy demo" width="720"></a>
</p>

<br /><br />

```zsh
ls -la | grep foo >> out.log           # valid command
why did that grep find nothing?        # just your natural language
```

*apathy.* is a terminal-to-agent zsh CLI that converts your pasted LLM prompts into actual invokes of harnesses like OpenCode, Claude Code and more. It manages to tell the difference between commands meant for your terminal, and prompts meant for your agent, as well as retain what you previously typed in your terminal.

It's called *apathy.* because if you seriously use this, you'd have to have really stopped caring. I also tried to shoehorn a tty pun into the name but it didn't really work.

## Getting Started

```zsh
curl -fsSL --create-dirs -o ~/.apathy/apathy.zsh https://cdn.jsdelivr.net/gh/sifex/apathy@latest/.github/release/apathy.zsh
```

```zsh
# ~/.zshrc, before zsh-syntax-highlighting
source ~/.apathy/apathy.zsh
```

Open a new shell and say something. `apathy-update` fetches the latest release later.

That one file is the whole plugin, served by jsDelivr's CDN, since `raw.githubusercontent.com`
increasingly rate-limits. A plugin manager works too, and updates it the usual way:

```zsh
antidote bundle sifex/apathy                 # antidote
zinit light sifex/apathy                     # zinit
git clone https://github.com/sifex/apathy ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/apathy  # then plugins+=(apathy)
```

> [!TIP]
> Want it to run as a prompt even though it starts with a command? Quote it.
> `make the tests pass` runs `make`, but `"make the tests pass"` asks your agent.

For a prompt over several lines, end a line with `\`, or press Ctrl+J, or Shift+Enter where your
terminal sends `^J` for it (as it does after Claude Code's `/terminal-setup`). On a command they
work as they always have.

## Which agent?

apathy uses the first one it finds, or whichever you set with `APATHY_AGENT`.

| | OpenCode | Claude Code | Codex |
|---|:---:|:---:|:---:|
| `APATHY_AGENT=` | `opencode` | `claude` | `codex` |
| Command variable | `APATHY_OPENCODE` | `APATHY_CLAUDE` | `APATHY_CODEX` |
| Runs | `opencode run --format json`, rendered by `jq` without the `> build · model` header (plain output if there's no `jq`) | `claude -p` | `codex exec` |
| Model | guessed from your `opencode models` ([how](#how-the-default-model-is-guessed)) | `haiku` (latest Haiku) | your Codex default |
| Auto-approves | `--auto` | `--permission-mode auto` | `--approve-for-me` |
| Session per pane | `--session ses_apathy<pane>` | `--session-id`, then `--resume` | `exec resume <thread>` |
| Prefers [`opencode-native`](https://github.com/simonklee/opencode-native-preview) (`~/.apathy/bin/`, then `PATH`) | ✅ | | |

> [!WARNING]
> **apathy runs your agent with permissions auto-approved**, in whatever directory you're in.
> OpenCode approves everything your config doesn't deny. Claude's `auto` mode and Codex's
> `--approve-for-me` approve what their safety reviewer allows, and Codex stays inside its
> workspace-write sandbox. To be asked first, override the command, for example
> `APATHY_CLAUDE='claude -p'`.

## Pick a model

```zsh
apathy-model                             # fzf picker: OpenCode's model list, or haiku/sonnet/opus for Claude
apathy-model anthropic/claude-sonnet-4-5  # set it directly
apathy-model ''                          # no model flag: use the agent's own default
```

This changes the model for the current shell only. To make it permanent, set `APATHY_MODEL` in `~/.zshrc`.
Switching models keeps the conversation, because the session belongs to the pane, not the model.

## Give it some attitude

apathy answers in its bundled persona, curt, sarcastic and mildly disgusted with you, unless you say otherwise:

```zsh
APATHY_PERSONA=~/pirate.md     # any file of instructions instead
APATHY_PERSONA=                # a plain, polite agent
```

```text
❯ Can you create a README.md?
→ write README.md
You know the `touch` command exists... right?
❯ This feels cursed... Is this cursed?
Like piping your shell into an LLM? Fucking cursed.
```

The instructions go in front of every message, for every agent, so switching persona takes effect
immediately, even in an existing session. Bundled personas live in [`lib/personas/`](lib/personas/).

## It remembers this pane

Each terminal pane gets its own agent session, so "and now?" keeps the conversation going.
The session ID comes from the pane, so apathy has **no state file**:

| Where you are | Pane identity |
|---|---|
| tmux | tmux server PID + pane number |
| iTerm2, Terminal.app | the tab or pane UUID from `$ITERM_SESSION_ID` / `$TERM_SESSION_ID` |
| WezTerm | GUI PID + `$WEZTERM_PANE` |
| kitty | `$KITTY_PID` + `$KITTY_WINDOW_ID` |
| anywhere else | the shell's PID (one session per shell) |

Claude can't create the same session ID twice, so apathy uses `--session-id` until Claude's own transcript
exists, then `--resume`. Codex picks its own thread IDs, so apathy reads the one Codex just
created and keeps it in a shell variable. A new shell starts a new Codex thread.

## It sees your screen

Every prompt includes what happened in this pane **since your previous prompt**, so "why did that
fail?" just works. Nothing is stored: it's read live, or kept in shell memory, and thrown away.

Where the terminal can be read, apathy sends the scrollback:

| Terminal | How | Cost |
|---|---|---|
| tmux (inside any terminal) | `tmux capture-pane` | ~5ms |
| iTerm2 | AppleScript `contents`, focused tab first | ~130ms |
| Terminal.app | AppleScript `history`, focused tab first | ~180ms |
| WezTerm | `wezterm cli get-text` | fast |
| kitty | `kitty @ get-text`, needs `allow_remote_control` | fast |

The echo of the prompt you just typed is cut out, even if it wrapped.

**Everywhere else** (Ghostty, VS Code, Zed, SSH sessions…), zsh's own hooks record each command you ran,
its exit code, how long it took and the directory it ran in:

```text
$ make test  # exit 2, 4.1s, ~/src/app
$ git status  # exit 0, 0.1s, ~/src/app
```

> [!TIP]
> Want the error text too? `APATHY_CAPTURE_STDERR=1` sends each command's stderr to your screen through
> `tee` and keeps the last 4KB in a pipe in memory. stdout is untouched. The catch: programs that check
> whether stderr is a terminal lose their progress bars and spinners (git, curl, docker, tqdm), and a
> command that leaves a background job running adds 0.2s before the next prompt.

> [!CAUTION]
> Everything in the pane goes to the model, including any secrets you've printed there.
> Set `APATHY_CONTEXT_LINES=0` to turn this off.

## How it decides

The line is tokenised by zsh's own lexer (`${(z)}`), so quotes, pipes, `>`, `>>` and `2>&1`
are read exactly as zsh reads them. After skipping `VAR=value` assignments and the modifiers `time`,
`noglob`, `nocorrect`, `command`, `builtin` and `exec`, it's a **command** if the first word:

- starts with shell syntax: `> >> < ( { [[ (( ! $ ~ / . \ # ^ - =` or a backtick
- is an alias, function, builtin, command on `PATH`, or a reserved word such as `export`
- is a suffix alias, an executable path, or a directory when `AUTO_CD` is set
- is a control keyword (`if for while case repeat …`) **and** the line contains `; & | ( ) { } < > $` or a backtick

Anything else is a **prompt**. Lines continuing a previous one are never touched.

| You type | apathy says |
|---|---|
| `cat notes.txt \| grep x >> out.log` | command |
| `>> notes.txt` | command |
| `FOO=1 time noglob git log` | command |
| `if true; then ls; fi` | command |
| `what's up` | prompt (the unmatched apostrophe makes the whole line one word, and that's not a command) |
| `if I rename this, what breaks?` | prompt |
| `time to refactor this` | prompt |
| `write a test for foo` | prompt (`what` and `write` are in `APATHY_PROMPT_WORDS`) |
| `yes please`, `read the README`, `test it` | prompt (`yes`, `read` and `test` run only with shell syntax or a flag: `yes \| head`, `test -f x`) |
| `make the tests pass` | command 🤷 |

> [!NOTE]
> The line stays on screen and in history exactly as typed. A leading space keeps it out of
> history under `HIST_IGNORE_SPACE`. It never reaches the zsh parser, so `$(…)` and backticks in a
> prompt are sent literally, not run. `$?` afterwards is the agent's exit status, except in a
> non-UTF-8 locale, where it's always 1. [Atuin](https://atuin.sh) records the prompt too.

## Configuration

| Variable | Default | |
|---|---|---|
| `APATHY_AGENT` | first of `opencode`, `claude`, `codex` on `PATH` | Which agent to use |
| `APATHY_MODEL` | guessed for OpenCode, `haiku` for Claude, Codex's own | Model for the active agent. Empty passes no model flag |
| `APATHY_OPENCODE` / `APATHY_CLAUDE` / `APATHY_CODEX` | see [Which agent?](#which-agent) | The command, without model, session flags or prompt |
| `APATHY_CONTEXT_LINES` | `100` | Maximum lines of context sent; `0` turns it off |
| `APATHY_CAPTURE_STDERR` | unset | `1` captures stderr where the terminal can't be read ([details](#it-sees-your-screen)) |
| `APATHY_PERSONA` | `apathy` | A bundled persona or a file of instructions; empty turns it off ([details](#give-it-some-attitude)) |
| `APATHY_PROMPT_WORDS` | `(what write)` | First words that always mean a prompt, even though they're commands (`/usr/bin/what`, `/usr/bin/write`) |

## How the default model is guessed

OpenCode can offer dozens of models. The first time you prompt in a shell, apathy lists yours with
`opencode models` and picks the one most likely to answer fastest, by name alone:

- **Skipped:** local providers (LM Studio, Ollama, llama.cpp), `auto`, paid speed or batch tiers
  (`-fast`, `-ultrafast`, `-flex`, `-batch`, `-priority`) that often aren't enabled, and non-chat
  models (embeddings, speech, images, realtime).
- **Preferred:** small tiers. `nano`/`lite` beat `haiku`/`mini`/`flash`/`small`, which beat everything
  else. `opus`, `pro`, `ultra`, `large`, `max` and reasoning models rank last, previews just below.
- **Ties:** the newest version wins.

It's a guess. `apathy-model` shows what it picked, and setting `APATHY_MODEL` skips it.
`opencode-native` also helps: it starts in about 15ms, against about 60ms for the TypeScript client.

## Development

```zsh
make test                 # everything: end-to-end tests per agent, for both builds
make test AGENTS=claude   # just one agent's end-to-end runs
make bench                # fails above APATHY_BENCH_MAX_US (default 100µs)
```

The end-to-end tests drive a real interactive zsh (zpty) and a real tmux server against fake
`opencode`, `claude` and `codex` binaries that behave like the real ones: same command lines,
JSON output, exit codes and session files. CI runs them on Ubuntu 22.04 and 24.04 (zsh 5.8, 5.9)
and macOS 15 and 26, for each agent, with and without `jq`, and again with zsh-autosuggestions and
zsh-syntax-highlighting loaded.

### Releases

Versions come from [conventional commits](https://www.conventionalcommits.org): `fix:` bumps the
patch, `feat:` the minor, and `feat!:` or a `BREAKING CHANGE:` footer the major (before 1.0,
just the minor). After each green run on `main`, [release-please](https://github.com/googleapis/release-please)
keeps a release PR open with the next version and its entry in `.github/release/CHANGELOG.md`.
Merging it tags `vX.Y.Z` and publishes the GitHub release. A loaded plugin reports its version
in `$APATHY_VERSION`.

`make bundle` builds `.github/release/apathy.zsh`, the one-file plugin that installs and
`apathy-update` download from jsDelivr. It's committed, since jsDelivr serves tagged files, and
`make lint` fails if it's stale. The end-to-end tests run against it as well as the source tree.

## Source Guide

- `lib/classify.zsh`: `apathy-classify`, the fork-free command-or-prompt decision.
- `lib/models.zsh`: `apathy-guess-model`, the default model guess.
- `lib/personas/`: bundled personas for `APATHY_PERSONA`.
- `apathy.plugin.zsh`: the Enter widget, screen readers, command log and stderr capture, pane sessions and the agent runners.
- `.github/release/`: release-please config, `bundle.zsh` and the `apathy.zsh` it builds.
- `.github/demo/`: the shell for recording the demo (`make demo`).
- `test/`: table-driven classifier and model cases, then end-to-end tests through zpty, tmux and the fake agents in `test/helpers.zsh`.
