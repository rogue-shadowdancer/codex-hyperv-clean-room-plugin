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


if __name__ == "__main__":
    unittest.main()
