#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh — 把 ~/.agents 里的 AGENTS.md 与 skills/ 软链到各个 agent 的全局目录
#
#   真源（唯一需要维护的地方）:
#     ~/.agents/AGENTS.md     全局指令
#     ~/.agents/skills/       全局技能（<name>/SKILL.md）
#
#   各 agent 的全局目录（软链目标）:
#     claude    ~/.claude/CLAUDE.md          ~/.claude/skills/
#     codex     ~/.codex/AGENTS.md           ~/.codex/skills/
#     codebuddy ~/.codebuddy/CODEBUDDY.md    ~/.codebuddy/skills/
#     opencode  ~/.config/opencode/AGENTS.md ~/.config/opencode/skills/
#     copilot   ~/.copilot/AGENTS.md         ~/.copilot/skills/   （目录不存在时跳过）
#
#   用法:
#     ./bootstrap.sh              # 建立/修正软链
#     ./bootstrap.sh --check      # 只看状态，不改任何东西
#     ./bootstrap.sh --dry-run    # 预演
#     ./bootstrap.sh --force      # 覆盖同名真实文件（原文件备份为 .bak-<时间戳>）
#     ./bootstrap.sh --agent claude,codex   # 只处理指定 agent
# ==============================================================================
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
SRC_INSTRUCTIONS="$AGENTS_HOME/AGENTS.md"
SRC_SKILLS="$AGENTS_HOME/skills"

# name|global dir|instruction filename|skills dir name|optional(1/0)
TARGETS=(
  "claude|$HOME/.claude|CLAUDE.md|skills|0"
  "codex|$HOME/.codex|AGENTS.md|skills|0"
  "codebuddy|$HOME/.codebuddy|CODEBUDDY.md|skills|0"
  "opencode|$HOME/.config/opencode|AGENTS.md|skills|0"
  "copilot|$HOME/.copilot|AGENTS.md|skills|1"
)

MODE="apply"   # apply | check | dry-run
FORCE=0
ONLY_AGENTS=""

# ------------------------------------------------------------------------------
# 输出
# ------------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_SKIP=$'\033[33m'
  C_WARN=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_OK=""; C_SKIP=""; C_WARN=""; C_DIM=""; C_BOLD=""
fi

ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; }
skip() { printf '  %s—%s %s\n' "$C_SKIP" "$C_RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
dim()  { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { printf '%serror:%s %s\n' "$C_WARN" "$C_RESET" "$1" >&2; exit 1; }

# ------------------------------------------------------------------------------
# 参数
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   MODE="check" ;;
    --dry-run) MODE="dry-run" ;;
    --force)   FORCE=1 ;;
    --agent)   shift; ONLY_AGENTS="${1:-}" ;;
    --agent=*) ONLY_AGENTS="${1#*=}" ;;
    -h|--help) usage 0 ;;
    *) die "未知参数: $1（--help 查看用法）" ;;
  esac
  shift
done

agent_selected() {
  [[ -z "$ONLY_AGENTS" ]] && return 0
  [[ ",$ONLY_AGENTS," == *",$1,"* ]]
}

# ------------------------------------------------------------------------------
# 软链工具
# ------------------------------------------------------------------------------

# 目标路径 -> 相对链接路径（尽量用相对路径，换机器/换 home 也不会失效）
rel_target() {
  local target="$1" link_dir="$2" rel
  target="$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")"
  rel="$(realpath --relative-to="$link_dir" "$target" 2>/dev/null || true)"
  [[ -n "$rel" ]] && printf '%s' "$rel" || printf '%s' "$target"
}

# ensure_symlink <link> <target> <label>
# 返回 0=已就绪 1=新建 2=已修正 3=冲突(跳过) 4=已备份覆盖
ensure_symlink() {
  local link="$1" target="$2" label="$3"
  local link_dir target_abs cur

  link_dir="$(dirname -- "$link")"
  if [[ ! -d "$link_dir" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p -- "$link_dir"
    else
      skip "$label 所在目录不存在（$link_dir）"
      return 3
    fi
  fi

  if [[ -L "$link" ]]; then
    cur="$(readlink -f -- "$link" 2>/dev/null || printf '%s' "$(readlink -- "$link")")"
    target_abs="$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")"
    if [[ "$cur" == "$target_abs" ]]; then
      ok "$label -> $(rel_target "$target" "$link_dir")"
      return 0
    fi
    if [[ "$MODE" == "check" ]]; then
      warn "$label 指向错误: $cur"
      return 3
    fi
    if [[ "$MODE" == "dry-run" ]]; then
      ok "$label 会改指向 $(rel_target "$target" "$link_dir")"
      return 2
    fi
    rm -f -- "$link"
    ln -s -- "$(rel_target "$target" "$link_dir")" "$link"
    ok "$label -> $(rel_target "$target" "$link_dir")（已改指向）"
    return 2
  fi

  if [[ -e "$link" ]]; then
    # 已存在真实文件/目录：不擅自覆盖
    if [[ "$FORCE" == "1" && "$MODE" == "apply" ]]; then
      local backup="${link}.bak-$(date +%Y%m%d%H%M%S)"
      mv -- "$link" "$backup"
      ln -s -- "$(rel_target "$target" "$link_dir")" "$link"
      warn "$label -> $(rel_target "$target" "$link_dir")（原文件备份为 $(basename "$backup")）"
      return 4
    fi
    if [[ "$MODE" == "check" || "$MODE" == "dry-run" ]]; then
      warn "$label 已存在且不是软链，跳过（--force 可备份后覆盖）"
      return 3
    fi
    warn "$label 已存在且不是软链，跳过（--force 可备份后覆盖）"
    return 3
  fi

  if [[ "$MODE" == "check" ]]; then
    skip "$label 未创建"
    return 3
  fi
  if [[ "$MODE" == "dry-run" ]]; then
    ok "$label 会创建 -> $(rel_target "$target" "$link_dir")"
    return 1
  fi
  ln -s -- "$(rel_target "$target" "$link_dir")" "$link"
  ok "$label -> $(rel_target "$target" "$link_dir")"
  return 1
}

# ------------------------------------------------------------------------------
# 真源准备
# ------------------------------------------------------------------------------
prepare_source() {
  if [[ ! -d "$AGENTS_HOME" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p -- "$AGENTS_HOME"
      ok "已创建 $AGENTS_HOME/"
    else
      warn "$AGENTS_HOME 不存在"
      return 0
    fi
  fi

  if [[ ! -f "$SRC_INSTRUCTIONS" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      printf '%s# AGENTS.md\n\n全局指令。修改这里，所有 agent 同步生效。\n' > "$SRC_INSTRUCTIONS"
      ok "已创建 $SRC_INSTRUCTIONS"
    else
      warn "$SRC_INSTRUCTIONS 不存在"
    fi
  fi

  if [[ ! -d "$SRC_SKILLS" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p -- "$SRC_SKILLS"
      ok "已创建 $SRC_SKILLS/"
    else
      warn "$SRC_SKILLS 不存在"
    fi
  fi

  if [[ -d "$SRC_SKILLS" && ! -f "$SRC_SKILLS/README.md" && "$MODE" == "apply" ]]; then
    cat > "$SRC_SKILLS/README.md" <<'EOF'
# skills

全局技能目录。每个技能是一个子目录，内含 `SKILL.md`（YAML frontmatter + 正文）。

    skills/<skill-name>/SKILL.md
    skills/<skill-name>/scripts/    # 可选，辅助脚本

`bootstrap.sh` 会把本目录软链到各 agent 的全局 skills 目录。
EOF
  fi
}

# ------------------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------------------
main() {
  printf '%sbootstrap%s %s(%s)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$MODE" "$C_RESET"

  prepare_source

  local entry name dir instr skills_dir optional
  local n_ok=0 n_new=0 n_fixed=0 n_conflict=0 n_skip=0

  for entry in "${TARGETS[@]}"; do
    IFS='|' read -r name dir instr skills_dir optional <<< "$entry"

    if ! agent_selected "$name"; then
      continue
    fi

    printf '\n%s%s%s  %s\n' "$C_BOLD" "$name" "$C_RESET" "$dir"

    if [[ "$optional" == "1" && ! -d "$dir" ]]; then
      skip "全局目录不存在，先跑一次该 agent 再重新执行本脚本"
      n_skip=$((n_skip + 1))
      continue
    fi

    if [[ ! -d "$dir" ]]; then
      if [[ "$MODE" == "apply" ]]; then
        mkdir -p -- "$dir"
        ok "创建全局目录"
      else
        skip "全局目录不存在"
      fi
    fi

    local rc=0
    ensure_symlink "$dir/$instr" "$SRC_INSTRUCTIONS" "$instr" || rc=$?
    case $rc in
      0) n_ok=$((n_ok + 1)) ;;
      1) n_new=$((n_new + 1)) ;;
      2|4) n_fixed=$((n_fixed + 1)) ;;
      3) n_conflict=$((n_conflict + 1)) ;;
    esac

    rc=0
    ensure_symlink "$dir/$skills_dir" "$SRC_SKILLS" "$skills_dir/" || rc=$?
    case $rc in
      0) n_ok=$((n_ok + 1)) ;;
      1) n_new=$((n_new + 1)) ;;
      2|4) n_fixed=$((n_fixed + 1)) ;;
      3) n_conflict=$((n_conflict + 1)) ;;
    esac
  done

  printf '\n%s汇总%s  就绪 %d  新建 %d  修正 %d  冲突 %d  跳过 %d\n' \
    "$C_BOLD" "$C_RESET" "$n_ok" "$n_new" "$n_fixed" "$n_conflict" "$n_skip"

  if [[ "$n_conflict" -gt 0 && "$MODE" == "apply" ]]; then
    dim "冲突项：目标已存在真实文件/目录。确认无用后加 --force 覆盖（会先备份）。"
  fi
}

main "$@"
