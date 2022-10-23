#
#  Task Library for Bash
# ----------------------- -  *
#  author: Satoshi Soma (https://amekusa.com)
# ============================================

_TASKS="$BASE/.tasks"
[ -f "$_TASKS" ] || touch "$_TASKS"

_CURRENT_TASK=

task-done() {
	[ "$(_load-var "$1" "$_TASKS")" = DONE ]
}

task() {
	local task="$1"; shift
	[ -n "$task" ] || _err "argument missing"
	[ -z "$_CURRENT_TASK" ] || _err "the task:$_CURRENT_TASK is not done yet"
	[ -z "$_ARG_TASK" ] || [ "$_ARG_TASK" = "$task" ] || return 1
	# check dependencies
	if [ "$1" = "-d" ]; then shift
		local each
		for each in "$@"; do
			task-done "$each" || return 1
		done
	fi
	task-done "$task" && return 1
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
	[ -z "$1" ] || echo " > $1"
	_save-var "$_CURRENT_TASK" FAILED "$_TASKS"
	exit 1
}

reset-task() {
	_save-var "$1" RESET "$_TASKS"
}

reset-tasks() {
	echo "" > "$_TASKS"
}

[ -z "$1" ] || reset-task "$1" || _err "cannot reset task:$1"
_ARG_TASK="$1"
