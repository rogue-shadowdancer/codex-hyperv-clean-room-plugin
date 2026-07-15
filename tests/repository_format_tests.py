from __future__ import annotations

import json
import subprocess
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
MOJIBAKE_MARKERS = ("\ufffd", "\u00c3", "\u00c2", "\u9225", "\u951b", "\u9286")


def current_files() -> list[str]:
    completed = subprocess.run(
        [
            "git",
            "-C",
            str(REPO_ROOT),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return sorted(
        item.decode("utf-8", errors="strict").replace("\\", "/")
        for item in completed.stdout.split(b"\0")
        if item
    )


def strict_json(text: str, path: str) -> object:
    def object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
        value: dict[str, object] = {}
        for key, child in pairs:
            if key in value:
                raise AssertionError(f"duplicate JSON key in {path}: {key}")
            value[key] = child
        return value

    return json.loads(text, object_pairs_hook=object_pairs)


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.nodes.MappingNode, deep: bool = False
) -> dict[object, object]:
    loader.flatten_mapping(node)
    result: dict[object, object] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise AssertionError(f"duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


def main() -> int:
    files = current_files()
    json_count = yaml_count = markdown_count = python_count = 0
    for relative in files:
        path = REPO_ROOT / relative
        content = path.read_bytes()
        if content.startswith(b"\xef\xbb\xbf"):
            raise AssertionError(f"UTF-8 BOM found: {relative}")
        try:
            text = content.decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise AssertionError(f"file is not strict UTF-8: {relative}") from error
        for marker in MOJIBAKE_MARKERS:
            if marker in text:
                raise AssertionError(f"mojibake marker found: {relative}")

        suffix = path.suffix.casefold()
        if suffix == ".json":
            strict_json(text, relative)
            json_count += 1
        elif suffix in {".yml", ".yaml"}:
            yaml.load(text, Loader=UniqueKeyLoader)
            yaml_count += 1
        elif suffix == ".py":
            compile(text, relative, "exec")
            python_count += 1
        elif suffix == ".md":
            markdown = text.lstrip()
            if markdown.startswith("---\n"):
                closing = markdown.find("\n---\n", 4)
                if closing < 0:
                    raise AssertionError(
                        f"Markdown front matter is not closed: {relative}"
                    )
                markdown = markdown[closing + 5 :].lstrip()
            if not markdown.startswith("#"):
                raise AssertionError(f"Markdown file has no leading heading: {relative}")
            markdown_count += 1

    print(
        json.dumps(
            {
                "ok": True,
                "strictUtf8Files": len(files),
                "bomFiles": 0,
                "mojibakeFiles": 0,
                "jsonFiles": json_count,
                "yamlFiles": yaml_count,
                "markdownFiles": markdown_count,
                "pythonFilesCompiled": python_count,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
