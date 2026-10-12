cask "agent-chromium" do
  arch arm: "arm64", intel: "x86_64"

  version "154.0.8037.97-1.1"
  sha256 arm:   "474f094cff24ba441ad1e1a2816c4ac057d6a0b7acc189c61a007d58d5752ce7",
         intel: "1ffcbbbac92a036655e91ca6a5d3c98b38bdb75dcd5e51608329370118197475"

  url "https://github.com/ursamageor/homebrew-agent-chromium/releases/download/v#{version}/Agent-Chromium-#{version}-#{arch}.zip"
  name "Agent-Chromium"
  desc "ungoogled-chromium under its own identity, for coding agents to drive via agent-browser"
  homepage "https://github.com/ursamageor/homebrew-agent-chromium"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+-\d+(?:\.\d+)*(?:_\d+)?)$/i)
    strategy :github_latest
  end

  depends_on formula: "agent-browser"
  depends_on macos: :ventura

  app "Agent-Chromium.app"

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
              args:         ["-TERM", "-f", "/Agent-Chromium.app/Contents/MacOS/Chromium( |$)"],
              must_succeed: false,
            }

  zap trash: [
    "~/.agent-chromium",
    "~/.agents/skills/agent-chromium",
    "~/.claude/skills/agent-chromium",
    "~/Library/Application Support/Agent-Chromium",
    "~/Library/Caches/Agent-Chromium",
    "~/Library/Preferences/org.agent-chromium.browser.plist",
    "~/Library/Saved Application State/org.agent-chromium.browser.savedState",
  ]

  caveats <<~EOS
    Agent-Chromium is plain ungoogled-chromium with its own bundle ID and data folder, so it never
    touches a Chromium.app profile. Nothing is bundled and nothing starts at login: agent-browser
    launches it, and ~/.agent-chromium/config.json decides the profile and flags.

    One step left: build ~/.agent-chromium (the latest Bitwarden and chromium-web-store, which
    Chromium installs into the profile on its first start, the seeded profile, config.json, and
    the ~/.agent-browser/config.json symlink to it), and optionally install the agent-chromium
    skill into your coding agents (it asks):

      "$(brew --repository ursamageor/agent-chromium)/scripts/setup-agent-browser.sh"

    It ends by opening the browser on a welcome page with the few settings Chromium will not let
    us preset (switching the extensions on, startup, search, Bitwarden login). Re-run it any time
    to update the extensions. Then:

      agent-browser open https://example.com
  EOS
end
