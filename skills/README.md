# skills

全局技能目录。每个技能是一个子目录，内含 `SKILL.md`（YAML frontmatter + 正文）。

    skills/<skill-name>/SKILL.md
    skills/<skill-name>/scripts/    # 可选，辅助脚本

`bootstrap.sh` 会把本目录软链到各 agent 的全局 skills 目录。
