#!/usr/bin/env python3
"""Agent entrypoint: prepare, commit, push, dispatch, wait and verify a release.

Write docs/releases/<version>.md from the reviewed changes before invoking this
command. It performs a real publication; tests substitute GitHub and Git I/O.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

if __package__:
    from .commit_preflight import area_trailers
    from .validate_release_notes import ROOT, validate_release
    from .release_version import PROJECT, project_version, appcast_version, require_newer
else:
    from commit_preflight import area_trailers
    from validate_release_notes import ROOT, validate_release
    from release_version import PROJECT, project_version, appcast_version, require_newer


def run(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def release_areas(commit_messages: list[str]) -> list[str]:
    """Read optional Area trailers for reviewed release-note grouping, without publishing."""
    return sorted({area for message in commit_messages for area in area_trailers(message)})


def publish(version: str, test_scope: str = "release") -> None:
    if test_scope not in {"release", "all"}:
        raise ValueError("发布测试范围必须是 release 或 all")
    notes = validate_release(ROOT, version)
    if run("git", "branch", "--show-current") != "main":
        raise ValueError("请先将已审核的发布内容集成到 main；不要直接发布未合并的工作分支。")
    # A release includes committed source only. Do not absorb parallel edits.
    allowed = {f"docs/releases/{version}.md"}
    dirty = set(run("git", "diff", "HEAD", "--name-only").splitlines())
    dirty.update(run("git", "ls-files", "--others", "--exclude-standard").splitlines())
    if dirty - allowed:
        raise ValueError(f"先提交本批代码或使用隔离的 main 检出；保留其他改动：{sorted(dirty - allowed)}")
    # Bind GitHub operations to the same origin we push, regardless of gh's saved default.
    origin = run("git", "remote", "get-url", "origin")
    os.environ["GH_REPO"] = run("gh", "repo", "view", origin, "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    run("gh", "auth", "status")
    run("git", "fetch", "origin", "main", "--tags")
    run("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
    validate_release(ROOT, version, check_tags=True)
    # The published feed can have a higher build than old source versions.
    with tempfile.TemporaryDirectory(prefix="mwx-release-version-") as temporary:
        run("gh", "release", "download", "update-feed", "--pattern", "appcast.xml", "--dir", temporary)
        published = appcast_version((Path(temporary) / "appcast.xml").read_bytes())
    run("bash", "script/prepare_release_version.sh", version, str(published[1]))
    expected_version = project_version((ROOT / PROJECT).read_text())
    if expected_version[0] != version:
        raise ValueError("Prepared project version differs from requested release")
    require_newer(expected_version, published)
    paths = ["MyWallpaperX.xcodeproj/project.pbxproj", f"docs/releases/{version}.md"]
    run("git", "add", "--", *paths)
    run("git", "commit", "--only", "-m", f"Prepare MyWallpaperX {version} release and notes", "--", *paths)
    sha = run("git", "rev-parse", "HEAD")
    run("git", "push", "origin", "HEAD:refs/heads/main")
    remote = run("git", "ls-remote", "origin", "refs/heads/main").split()
    if not remote or remote[0] != sha:
        raise ValueError("远程 main 已变化，停止触发；重新核对待发布提交。")
    remote_project = run("git", "show", f"{remote[0]}:{PROJECT.as_posix()}")
    if project_version(remote_project) != expected_version:
        raise ValueError("Remote source version differs from prepared local version")
    # API 2026-03-10 returns this dispatch's run ID, avoiding a race-prone run-list search.
    result = json.loads(run(
        "gh", "api", "--method", "POST", "-H", "X-GitHub-Api-Version: 2026-03-10",
        "repos/{owner}/{repo}/actions/workflows/build.yml/dispatches",
        "-f", "ref=main", "-f", f"inputs[version]={version}", "-f", f"inputs[source_sha]={sha}",
        "-f", f"inputs[test_scope]={test_scope}",
    ))
    run_id = str(result["workflow_run_id"])
    print(f"发布任务：{result['html_url']}", flush=True)
    subprocess.run(["gh", "run", "watch", run_id, "--exit-status", "--interval", "15"], cwd=ROOT, check=True)
    release = json.loads(run("gh", "api", f"repos/{{owner}}/{{repo}}/releases/tags/build-{version}"))
    if release["draft"] or release["prerelease"] or release["target_commitish"] != sha:
        raise ValueError("Release 状态或源码提交与本次发布不一致。")
    if release["body"].strip() != notes.read_text(encoding="utf-8").strip():
        raise ValueError("公开发布日志与仓库中的日志不一致。")
    package = f"MyWallpaperX-{version}-{sha[:7]}"
    expected = {f"{package}.dmg", f"{package}.dmg.sha256", f"{package}.dSYM.zip", "appcast.xml"}
    uploaded = {asset["name"] for asset in release["assets"] if asset["state"] == "uploaded" and asset["size"] > 0}
    if not expected <= uploaded:
        raise ValueError(f"发布附件不完整：{sorted(expected - uploaded)}")
    latest = json.loads(run("gh", "api", "repos/{owner}/{repo}/releases/latest"))
    if latest["tag_name"] != f"build-{version}":
        raise ValueError("本次版本不是 Latest；检查是否有另一发布任务已完成。")
    with tempfile.TemporaryDirectory(prefix="mwx-release-verify-") as temporary:
        destination = Path(temporary)
        for tag, folder in ((f"build-{version}", "release"), ("update-feed", "feed")):
            run("gh", "release", "download", tag, "--pattern", "appcast.xml", "--dir", str(destination / folder))
        if appcast_version((destination / "release/appcast.xml").read_bytes()) != expected_version:
            raise ValueError("Published version/build differs from committed local project")
        if (destination / "release/appcast.xml").read_bytes() != (destination / "feed/appcast.xml").read_bytes():
            raise ValueError("自动更新源尚未与正式 Release 同步。")
    print(f"发布完成并核对日志、附件及更新源：{release['html_url']}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--test-scope", choices=("release", "all"), default="release")
    args = parser.parse_args()
    try:
        publish(args.version, args.test_scope)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"发布未完成：{error}\n保留现场；不要自动覆盖已公开版本或重复触发任务。\n")
