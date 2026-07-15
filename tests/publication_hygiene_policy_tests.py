from __future__ import annotations

import json
import unittest

import publication_hygiene_tests as hygiene


SENSITIVE_KEY = "pass" + "word"
ALTERNATE_KEY = "sec" + "ret"
SENSITIVE_VALUE = "hunter" + "2"
SAFE_SENTINEL = "must-not-be-" + "accepted"


class PublicationHygienePolicyTests(unittest.TestCase):
    def assert_content_rejected(self, path: str, text: str) -> None:
        with self.assertRaisesRegex(AssertionError, "plaintext"):
            hygiene.scan_content(path, text.encode("utf-8"), "policy regression")

    def assert_content_allowed(self, path: str, text: str) -> None:
        hygiene.scan_content(path, text.encode("utf-8"), "policy regression")

    def test_rejects_json_secret_literals_including_tests(self) -> None:
        self.assert_content_rejected(
            "config.json", json.dumps({SENSITIVE_KEY: SENSITIVE_VALUE})
        )
        self.assert_content_rejected(
            "config.json", json.dumps({SENSITIVE_KEY: 123456})
        )
        self.assert_content_rejected(
            "tests/fixtures/leak.json",
            json.dumps({ALTERNATE_KEY: SENSITIVE_VALUE}),
        )

    def test_rejects_quoted_and_unquoted_yaml_literals(self) -> None:
        self.assert_content_rejected(
            "config.yml", f"{SENSITIVE_KEY}: {SENSITIVE_VALUE}\n"
        )
        self.assert_content_rejected(
            "config.yaml", f'"{ALTERNATE_KEY}": "{SENSITIVE_VALUE}"\n'
        )
        self.assert_content_rejected(
            "config.yaml", f"'{SENSITIVE_KEY}': '{SENSITIVE_VALUE}' # literal\n"
        )

    def test_rejects_quoted_and_unquoted_assignment_literals(self) -> None:
        self.assert_content_rejected(
            "config.ps1", "$" + SENSITIVE_KEY + f" = '{SENSITIVE_VALUE}'\n"
        )
        self.assert_content_rejected(
            "config.env", SENSITIVE_KEY + f"={SENSITIVE_VALUE}\n"
        )
        self.assert_content_rejected(
            "config.txt", ALTERNATE_KEY + f' = "{SENSITIVE_VALUE}"\n'
        )

    def test_allows_redaction_references_and_exact_safe_sentinel(self) -> None:
        environment_reference = "$" + "{PASSWORD}"
        self.assert_content_allowed(
            "config.json", json.dumps({SENSITIVE_KEY: None})
        )
        self.assert_content_allowed(
            "config.json", json.dumps({SENSITIVE_KEY: environment_reference})
        )
        self.assert_content_allowed(
            "config.yml", f"{SENSITIVE_KEY}: <redacted>\n"
        )
        self.assert_content_allowed(
            "config.ps1", "$" + SENSITIVE_KEY + " = $env:PASSWORD\n"
        )
        self.assert_content_allowed(
            "tests/gate2-runtime.tests.ps1",
            SENSITIVE_KEY + f" = '{SAFE_SENTINEL}'\n",
        )

    def test_allows_non_key_prose_and_identifier_suffixes(self) -> None:
        self.assert_content_allowed(
            "notes.md", f"The {SENSITIVE_KEY} field must never contain plaintext.\n"
        )
        self.assert_content_allowed(
            "config.ps1", SENSITIVE_KEY + f"Pattern = '{SENSITIVE_VALUE}'\n"
        )
        self.assert_content_allowed(
            "config.json",
            json.dumps({SENSITIVE_KEY + "Pattern": SENSITIVE_VALUE}),
        )

    def test_rejects_nested_state_and_virtualization_paths(self) -> None:
        rejected = (
            "docs/Birdsgone/profile.json",
            "cache/result.txt",
            ".cache/result.txt",
            "artifacts/output.txt",
            "nested/checkpoints/stock/state.txt",
            "nested/vm/owned/state.txt",
            "logs/run.txt",
            "installed-copy/control.txt",
            "install-state/current.json",
            "artifacts/evidence.json",
            "artifacts/inventory.json",
            "vm/disk.avhdx",
            "vm/state.vmcx",
            "vm/state.vmrs",
            "vm/state.vmgs",
            "vm/state.vsv",
        )
        for path in rejected:
            with self.subTest(path=path):
                with self.assertRaises(AssertionError):
                    hygiene.assert_publishable_path(path, "policy regression")

    def test_allows_documentation_and_schema_names(self) -> None:
        for path in (
            "docs/evidence.md",
            "docs/cachebuster.md",
            "hyperv-clean-room/schemas/evidence.schema.json",
        ):
            with self.subTest(path=path):
                hygiene.assert_publishable_path(path, "policy regression")

    def test_rejects_credentialed_urls_nonpublic_email_and_mojibake(self) -> None:
        credentialed_url = (
            "https://" + "user:" + "value" + "@example.test/repo"
        )
        nonpublic_email = "person" + "@example.test"
        with self.assertRaisesRegex(AssertionError, "credentialed URL"):
            self.assert_content_allowed("notes.txt", credentialed_url)
        with self.assertRaisesRegex(AssertionError, "non-public email"):
            self.assert_content_allowed("notes.txt", nonpublic_email)
        with self.assertRaisesRegex(AssertionError, "mojibake"):
            self.assert_content_allowed("notes.txt", chr(0xFFFD))

    def test_allows_only_the_structured_handoff_project_path(self) -> None:
        project_path = "E:" + "\\study\\great_projects\\plugin"
        field = f"`projectPath: {project_path}`\n"
        self.assert_content_allowed("TASK_HANDOFF.md", field)
        with self.assertRaisesRegex(AssertionError, "workspace-specific path"):
            self.assert_content_allowed("notes.md", field)
        with self.assertRaisesRegex(AssertionError, "workspace-specific path"):
            self.assert_content_allowed(
                "TASK_HANDOFF.md", field + f"workspace: {project_path}\n"
            )
        with self.assertRaisesRegex(AssertionError, "multiple projectPath"):
            self.assert_content_allowed("TASK_HANDOFF.md", field + field)
        token_path = project_path + "\\" + "ghp_" + ("A" * 20)
        with self.assertRaisesRegex(AssertionError, "GitHub token"):
            self.assert_content_allowed(
                "TASK_HANDOFF.md", f"`projectPath: {token_path}`\n"
            )

    @staticmethod
    def synthetic_commit(name: str, email: str, message: str) -> bytes:
        lines = [
            "tree " + ("0" * 40),
            f"author {name} <{email}> 1 +0000",
            f"committer {name} <{email}> 1 +0000",
            "",
            message,
            "",
        ]
        return "\n".join(lines).encode("utf-8")

    def test_commit_identity_and_message_policy_fails_closed(self) -> None:
        public = self.synthetic_commit(
            hygiene.PUBLIC_COMMIT_NAME,
            hygiene.PUBLIC_COMMIT_EMAIL,
            "release candidate",
        )
        self.assertEqual(
            hygiene.assert_commit_metadata_safe("a" * 40, public),
            "public-noreply",
        )

        legacy_email = "person" + "@example.test"
        legacy = self.synthetic_commit("Legacy Person", legacy_email, "old change")
        with self.assertRaisesRegex(AssertionError, "unexpected author/committer"):
            hygiene.assert_commit_metadata_safe("b" * 40, legacy)

        private_path = "E:" + "\\study\\private"
        unsafe_message = self.synthetic_commit(
            hygiene.PUBLIC_COMMIT_NAME,
            hygiene.PUBLIC_COMMIT_EMAIL,
            "mentions " + private_path,
        )
        with self.assertRaisesRegex(AssertionError, "workspace-specific path"):
            hygiene.assert_commit_metadata_safe("c" * 40, unsafe_message)

    def test_pull_request_scans_base_history_not_synthetic_merge_history(self) -> None:
        self.assertEqual(
            hygiene.select_history_revision("pull_request", "master"),
            "origin/master",
        )
        self.assertEqual(
            hygiene.select_history_revision("push", "master"),
            "HEAD",
        )
        self.assertEqual(
            hygiene.select_history_revision("", ""),
            "HEAD",
        )
        for unsafe in ("", "../master", "/master", "-master", "main^{}"):
            with self.subTest(unsafe=unsafe):
                with self.assertRaisesRegex(AssertionError, "unsafe base ref"):
                    hygiene.select_history_revision("pull_request", unsafe)

        contributor_email = "contributor" + "@example.test"
        contributor_commit = self.synthetic_commit(
            "Public Contributor", contributor_email, "safe pull request change"
        )
        with self.assertRaisesRegex(AssertionError, "unexpected author/committer"):
            hygiene.assert_commit_metadata_safe("d" * 40, contributor_commit)


if __name__ == "__main__":
    unittest.main()
