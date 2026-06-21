from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "worko" / "scripts"
SKILL = ROOT / "skills" / "worko" / "SKILL.md"

COMMANDS = ("init", "list", "ask", "start", "stop", "status", "logs", "update")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class WindowsPowerShellScriptsTest(unittest.TestCase):
    def test_every_shell_command_has_matching_powershell_script(self):
        for command in COMMANDS:
            self.assertTrue((SCRIPTS / f"{command}.sh").is_file())
            self.assertTrue((SCRIPTS / f"{command}.ps1").is_file())

    def test_worko_ps1_is_only_a_compatibility_dispatcher(self):
        text = read(SCRIPTS / "worko.ps1")

        for command in COMMANDS:
            self.assertIn(f"{command}.ps1", text)

        self.assertNotIn("function Cmd-", text)
        self.assertNotIn("Invoke-RestMethod", text)
        self.assertNotIn("Start-Process", text)
        self.assertNotIn("while ((Get-Date)", text)
        self.assertNotIn("_gateway", text)

    def test_windows_start_uses_shared_gateway_ts_instead_of_polling_daemon(self):
        text = read(SCRIPTS / "start.ps1")

        self.assertIn("gateway.ts", text)
        self.assertIn("Start-Process", text)
        self.assertIn("WORKO_RUNTIME", text)
        self.assertNotIn("while ((Get-Date)", text)
        self.assertNotIn("/context?thread=", text)

    def test_powershell_scripts_do_not_assign_pid_automatic_variable(self):
        for path in SCRIPTS.glob("*.ps1"):
            text = read(path)
            self.assertNotRegex(text, r"(?i)\$pid\b")
            self.assertNotRegex(text, r"(?im)^\s*\$pid\s*=")
            self.assertNotRegex(text, r"(?i)\[ref\]\s*\$pid\b")

    def test_skill_docs_reference_split_windows_scripts(self):
        text = read(SKILL)

        for command in COMMANDS:
            self.assertIn(f"scripts/{command}.ps1", text)

        self.assertNotIn("worko.ps1 <cmd>", text)
        self.assertNotIn("纯 PowerShell 轮询", text)
