---
name: openclaw-cn-gpt54-patch
description: "Reapply GPT-5.4 support to OpenClaw-CN after package updates on Windows with WSL. Use when OpenClaw-CN updates overwrite the manual GPT-5.4 patch, the UI gets stuck in queue after an update, or logs show `Unknown model: openai-codex/gpt-5.4`."
---

# OpenClaw-CN GPT-5.4 Patch

在 OpenClaw-CN 更新后，如果 `GPT-5.4` 支持被覆盖掉，就用这个 skill 重新补回去。  
Use this skill to reapply the manual `openai-codex/gpt-5.4` patch after an OpenClaw-CN update removes GPT-5.4 support.

## Workflow

1. 确认症状。  
Confirm the symptom.

常见触发条件 / Common triggers:

- `Unknown model: openai-codex/gpt-5.4`
- OpenClaw-CN 更新后，Web UI 一直卡在队列中  
  Web UI stays stuck in queue right after an OpenClaw-CN update

示例检查命令 / Example check:

```powershell
wsl -d <distro> -- bash -lc "journalctl -u openclaw-gateway.service -n 80 --no-pager | tail -n 20"
```

2. 运行附带的 PowerShell 脚本。  
Run the bundled PowerShell script.

在 skill 目录中执行 / Run from the skill folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reapply-openclaw-gpt54.ps1
```

可选：手动指定发行版 / Optional override:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reapply-openclaw-gpt54.ps1 -Distro Ubuntu
```

3. 验证结果。  
Verify the result.

```powershell
curl.exe -I http://127.0.0.1:18789/
wsl -d <distro> -- bash -lc "journalctl -u openclaw-gateway.service -n 40 --no-pager | tail -n 20"
```

成功标志 / Success looks like:

- HTTP `200`
- 日志出现 `agent model: openai-codex/gpt-5.4`  
  The log shows `agent model: openai-codex/gpt-5.4`
- 不再出现新的 `Unknown model: openai-codex/gpt-5.4`  
  No fresh `Unknown model: openai-codex/gpt-5.4`

## What The Script Changes

脚本会自动探测 WSL 发行版、Linux 用户、OpenClaw-CN 安装目录和 `openclaw.json`，然后补丁以下位置：  
The script auto-detects the WSL distro, Linux user, OpenClaw-CN install path, and `openclaw.json`, then patches:

- default Codex model
- live model filter
- high-thinking model list
- model catalog fallback
- embedded runner fallback
- `~/.openclaw/openclaw.json` primary model

## Boundaries

- 不要把这个 skill 用在代理故障、飞书配对失败、WSL 启动异常这些问题上。  
  Do not use this skill for proxy failures, Feishu pairing, or WSL startup issues.
- 如果 WSL 里 `which openclaw-cn` 指向 `/mnt/c/...`，先修 WSL 路径污染。  
  If `which openclaw-cn` inside WSL points to `/mnt/c/...`, repair the WSL path first.
- 以后再次更新 `openclaw-cn`，这个补丁仍然可能被覆盖。  
  Expect later `openclaw-cn` updates to overwrite this patch.
