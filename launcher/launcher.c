// Agent-Chromium main-executable stub.
//
// macOS needs the app's CFBundleExecutable to be a Mach-O binary (codesign and Launch Services
// both insist), so this tiny program is installed as Contents/MacOS/Chromium. All it does is exec
// Contents/Resources/agent-chromium/launch.sh with the same arguments; the script decides the
// flags and then execs the real browser binary (Contents/MacOS/Chromium-bin). exec keeps the PID
// and the inherited file descriptors, so drivers that talk CDP over a pipe (Playwright, and
// therefore agent-browser) work unchanged.
//
// The same binary serves as the `agent-chromium` CLI through a symlink in Homebrew's bin dir;
// realpath() resolves the symlink back into the bundle.

#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  char exe[PATH_MAX];
  uint32_t size = sizeof exe;
  if (_NSGetExecutablePath(exe, &size) != 0) {
    fputs("agent-chromium: executable path too long\n", stderr);
    return 1;
  }

  char resolved[PATH_MAX];
  if (realpath(exe, resolved) == NULL) {
    perror("agent-chromium: realpath");
    return 1;
  }

  // resolved = .../Contents/MacOS/Chromium
  char *macos_dir = dirname(resolved);
  char script[PATH_MAX];
  int n = snprintf(script, sizeof script, "%s/../Resources/agent-chromium/launch.sh", macos_dir);
  if (n < 0 || (size_t)n >= sizeof script) {
    fputs("agent-chromium: launcher path too long\n", stderr);
    return 1;
  }

  char **args = calloc((size_t)argc + 2, sizeof *args);
  if (args == NULL) {
    perror("agent-chromium: calloc");
    return 1;
  }
  args[0] = "/bin/bash";
  args[1] = script;
  for (int i = 1; i < argc; i++) {
    args[i + 1] = argv[i];
  }
  args[argc + 1] = NULL;

  execv("/bin/bash", args);
  perror("agent-chromium: exec launch.sh");
  return 1;
}
