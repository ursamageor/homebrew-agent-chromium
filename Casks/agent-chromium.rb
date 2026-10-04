cask "agent-chromium" do
  arch arm: "arm64", intel: "x86_64"

  version "154.0.8037.57-1.1"
  sha256 arm:   "2f7d30c5f0a27cacdad0b386d4444929ab1df8d8a5b7d2f7065fddc692fe2e32",
         intel: "3c631654b2f4a82757cd9c7db3673a5c871c110ca859ed480677fc64b7b3174e"

  url "https://github.com/ursamageor/homebrew-agent-chromium/releases/download/v#{version}/Agent-Chromium-#{version}-#{arch}.zip"
  name "Agent-Chromium"
  desc "Chromium for coding agents: ungoogled-chromium, extensions, agent-browser"
  homepage "https://github.com/ursamageor/homebrew-agent-chromium"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+-\d+(?:\.\d+)*(?:_\d+)?)$/i)
    strategy :github_latest
  end

  depends_on formula: "agent-browser"
  depends_on macos: :ventura

  app "Agent-Chromium.app"
  binary "#{appdir}/Agent-Chromium.app/Contents/MacOS/Chromium", target: "agent-chromium"

  # The agent-browser config is written by `agent-chromium setup` (see caveats), not here:
  # postflight steps run in Homebrew's sandbox with a fake $HOME.
  postflight_steps do
    # The bundle is ad-hoc signed; Gatekeeper blocks it while Homebrew's quarantine flag is set.
    run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/Agent-Chromium.app"]
  end

  # quit: and signal: both go through System Events, which needs Automation access the terminal
  # may lack (then the old process keeps running from a replaced bundle). Chromium exits cleanly on
  # SIGTERM, so pkill the main process as a fallback; the pattern spares the helper processes.
  uninstall quit:   "org.agent-chromium.browser",
            signal: ["TERM", "org.agent-chromium.browser"],
            script: {
              executable:   "/usr/bin/pkill",
              args:         ["-TERM", "-f", "/Agent-Chromium.app/Contents/MacOS/Chromium-bin"],
              must_succeed: false,
            }

  zap trash: [
    "~/.agents/skills/agent-chromium",
    "~/.claude/skills/agent-chromium",
    "~/.codex/skills/agent-chromium",
    "~/Library/Application Support/Agent-Chromium",
    "~/Library/Caches/Agent-Chromium",
    "~/Library/Preferences/org.agent-chromium.browser.plist",
    "~/Library/Saved Application State/org.agent-chromium.browser.savedState",
  ]

  caveats <<~EOS
    Agent-Chromium is one browser with one stable profile that you and your coding agents share.
    While it runs it keeps a remote-debugging port on 127.0.0.1:9222; agent-browser attaches to
    it, starting the browser first if needed. Nothing starts at login.

    Bundled extensions: chromium-web-store (enables installs from the Chrome Web Store) and Bitwarden.

    Security hygiene note: while Agent-Chromium is running, debugging port 9222 is open.
    It's reasonable to quit the app when your agent is done using it.

    IMPORTANT: One step left — point agent-browser at this browser. Run:

      agent-chromium setup

    This setup script:
    - writes ~/.agent-browser/config.json (only if you have none)
    - asks [y/n] whether to install the agent-chromium skill in each of:

      1. ~/.agents/skills (Codex CLI, ChatGPT and Codex desktop, most other agents)
      2. ~/.claude/skills (Claude Code CLI)
      3. Claude Desktop (opens the skill in Claude, which shows its install screen)

    Nothing is installed unasked.

    Quick test after setup:

      agent-browser open https://example.com    # opens a tab in your Agent-Chromium window
      agent-chromium status                     # is it running, on which port
  EOS
end
