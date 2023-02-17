#
#  Task Library for Bash
# ----------------------- -  *
#  author: Satoshi Soma (https://amekusa.com)
# ============================================

_TASKS="$BASE/.tasks"
[ -f "$_TASKS" ] || touch "$_TASKS"

_CURRENT_TASK=

task() {
	local task="$1"; shift
	[ -n "$task" ] || _err "argument missing"
	[ -z "$_CURRENT_TASK" ] || _err "the task:$_CURRENT_TASK is not done yet"
	[ -z "$_ARG_TASK" ] || [ "$_ARG_TASK" = "$task" ] || return 1

	# check task status
	is-task "$task" DONE NEVER && return 1

	# check dependencies
	if [ "$1" = "-d" ]; then shift
		local arg
		for arg in "$@"; do
			is-task "$arg" DONE || return 1
		done
	fi

	# prompt
	if $MODE_PROMPT; then
		local answer
		while true; do
			read -n 1 -p "Run task:$task? [ (R)un / (S)kip / (N)ever / (D)one already ] " answer; echo
			case "$answer" in
				[Rr]) echo " > Run";          break ;;
				[Ss]) echo " > Skip";         return 1 ;;
				[Nn]) echo " > Never";        set-task "$task" NEVER; return 1 ;;
				[Dd]) echo " > Done already"; set-task "$task" DONE;  return 1 ;;
			esac
		done
	fi

	echo
	echo "TASK: $task ..."
	_CURRENT_TASK="$task"
}

ksat() {
	[ -n "$_CURRENT_TASK" ] || _err "no active task"
	_save-var "$_CURRENT_TASK" DONE "$_TASKS" || _err "failed to write: $_TASKS"
	echo "TASK: $_CURRENT_TASK > DONE"
	_CURRENT_TASK=""
}

x() {
	echo "TASK: $_CURRENT_TASK > ERROR!"
	[ -z "$*" ] || echo " > $*"
	_save-var "$_CURRENT_TASK" FAILED "$_TASKS"
	exit 1
}

is-task() {
	local task="$1"; shift
	local status="$(_load-var "$task" "$_TASKS")"
	local arg
	for arg in "$@"; do
		[ "$arg" = "$status" ] && return 0
	done
	return 1
}

set-task() {
	local task="$1"
	local status="$2"
	_save-var "$task" "$status" "$_TASKS" || _err "failed to write: $_TASKS"
}

reset-task() {
	set-task "$1" RESET
}

reset-tasks() {
	echo "" > "$_TASKS"
}

[ -z "$1" ] || reset-task "$1" || _err "cannot reset task:$1"
_ARG_TASK="$1"
