#!/usr/bin/env sh

# This script helps you keep track of upstream changes in copied files.
# Please consult the accompanying README.md for further details, including usage instructions.

# Quick Reference ###################################################################
#
# checked_version_per_branch: list of space-separated branch-revision pairs
# upstream_path: path to the upstream plugin, absolute or relative to invocation
# upstream_git_url: URL to the upstream git repository
# affected_files: exclusive, space-separated list of paths relative to $upstream_path


set -e

print_help ()
{
	echo '[1mDetects Upstream Changes[22m\n'
	
echo '\033[1mDetects Upstream Changes\033[0m'

	echo 'This script tells you if certain files have been updated since the last time you checked.'
	echo 'It relies on a few variables, which are documented in the accompanying README.md.'
	echo
	echo 'OPTIONS\n'
	echo '[1m-b[22m [3m<branch>[23m'
	echo '  Specify a branch of the upstream repo to compare against.\n  If not provided, all branches in ‘checked_version_per_branch’ will be checked.\n'
	echo '[1m-d[22m'
	echo '  Show changed lines instead of just a short summary.\n'
	echo '[1m-e[22m [3m<file>[23m'
	echo '  Provide path to a file that defines the needed variables (see detect-upstream-changes.env).\n'
	echo '[1m-h[22m'
	echo '  Print this message.'
}

error () { printf '[31m%s[m\n' "$1"; } >&2
warn () { printf '[33m%s[m\n' "$1"; } >&2
success () { printf '[32m%s[m\n' "$1"; }

while getopts b:de:h flag
do
	case $flag in
		b) branch="$OPTARG" ;;
		d) show_diff=true ;;
		e)
			readonly env_file="$OPTARG"
			if ! [ -e "$env_file" ]
			then
				error "‘$env_file’ is not a valid path."
				exit 2
			fi
			. "$env_file" ;;
		h)
			print_help
			exit ;;
		?)
			echo 'Check -h for valid options.'
			exit 2 ;;
	esac
done

readonly affected_files checked_version_per_branch upstream_git_url upstream_path


# We cannot continue if this variable is not defined.
if [ -z "$checked_version_per_branch" ]
then
	error 'Please provide ‘checked_version_per_branch’.'
	warn 'If this is the first check, provide the current version of the plugin that you copied from.'
	exit 2
fi


# Provide some information, may be useful for debugging.
message=''
if [ -n "$upstream_path" ]
then
	if [ -z "$upstream_git_url" ]
	then
		message='a built-in plugin'
	else
		message='an external plugin (which is also installed)'
	fi
elif [ -n "$upstream_git_url" ]
then
	message='an external plugin'
else
	error 'Missing parameters, please provide either:'
	error ' — ‘upstream_path’ if you want to check against a built-in Moodle plugin, and Moodle is installed as git repository.'
	error ' — ‘upstream_path’ and ‘upstream_latest_version’ if you want to check against a built-in Moodle plugin, and Moodle is not installed as git repository.'
	error ' — ‘upstream_git_url’ if you want to check against an external plugin that is not installed at all.'
	exit 2
fi
printf '\nWe are checking for changes in %s.\n' "$message"


# Determine if we have to clone the upstream repo or if a local copy is available.
clone_repo=true
if [ -n "$upstream_path" ]
then
	if [ "$(git rev-parse --is-inside-work-tree)" = 'false' ]
	then
		warn "The provided path does not point to a valid git repository: ‘$upstream_path’"
		warn 'We will clone Moodle ourselves. Proceeding …'
	else
		clone_repo=false
	fi
elif [ -z "$upstream_git_url" ]
then
	warn 'To avoid unnecessary downloads in the future, provide an absolute path to a local Moodle git repository by defining ‘upstream_path’.'
fi
readonly clone_repo


# Clone the repo to a temporary directory, if necessary.
if $clone_repo
then
	readonly upstream_path=$(mktemp -d)

	# Make sure to delete the temporary directory in case of early termination.
	cleanup () { rm -rf "$upstream_path"; }
	trap cleanup 0 1 2 3 9 15

	echo # blank line
	git clone ${upstream_git_url:-https://github.com/moodle/moodle.git} "$upstream_path"
fi


cd "$upstream_path"


# Check if the specified affected files actually exist.
echo "Affected files:" 
echo $affected_files
if [ -n "$affected_files" ]
then
	for file in $affected_files
	do
			echo "Files"
			echo
		if [ ! -e "$file" ]
		then
			# This ugly quote constellation is necessary because of an apparent unicode bug in bash.
			error '‘'"$file"'’ does not exist! Check if you set ‘affected_files’ correctly.'
			exit 2
		fi
	done
fi
echo


# Define the flags that will be provided to the diff command.
if ! "${show_diff:-false}"
	then readonly git_flags='--compact-summary'
fi


# Check if the specified revisions (branch name, hash, tag, …) exist.
verify_revisions ()
{
	local current_revision deepen_count depth
	depth=50 # The initial step for deepening a shallow repo.
	deepen_count=0 # Track how often a shallow repo has been deepend.
	for current_revision in "$@"
	do
		while ! git rev-parse --quiet --verify "$current_revision^{object}" >/dev/null
		do
			# It is likely that a revision cannot be found because the repo is shallow.
			# In that case we deepen it three times in exponential steps until we give in and unshallow completely.
			if [ $(git rev-parse --is-shallow-repository) = 'true' ]
			then
				while [ $deepen_count -lt 3 ]
				do
					git fetch --quiet --deepen=$depth
					deepen_count=$((deepen_count + 1))
					depth=$((depth * 2))
					continue 2
				done
				git fetch --quiet --unshallow
			fi
			error "‘$current_revision’ is not a valid revision (branch name, tag name, hash, …)."
			exit 2
		done
	done
}

# Print latest human readable version for the provided branch.
# As this is only called inside of detect_changes, we reuse its $branch variable instead of passing it.
# Unfortunately, nested readonly variables with the same name are not possible with shell script.
print_latest_version ()
{
	local latest_version
	readonly latest_version="$(git describe --always --tags --long $branch)"
	printf 'The latest version for branch ‘%s’ is: [1m%s[22m\n' "$branch" "$latest_version"
}

# Provide a branch name and a revision (hash, tag, …).
detect_changes ()
{
	local branch revision
	readonly branch="$1"
	readonly revision="$2"
	echo "Revision"
	echo $revision

	echo "● Comparing branch ‘[1m$branch[22m’ with revision ‘$revision’."

	verify_revisions $branch $revision

	if ! git diff --quiet $revision $branch -- ${affected_files:-.}
	then
		echo
		git --no-pager diff $git_flags $revision $branch -- ${affected_files:-.}
		echo
		error 'There have been changes to the upstream plugin. Make sure to update the affected files if necessary.'
		warn 'Also update ‘checked_version_per_branch’.'
		print_latest_version
		exit 1
	fi

	success '✓ No changes detected, everything is up-to-date.'
	if [ "$(git rev-parse $revision)" != "$(git rev-parse $branch)" ]
	then
		warn 'Don’t forget to update ‘checked_version_per_branch’, though.'
		print_latest_version
	fi
	echo
}


# Provide branch name as argument to get the last checked version from ‘checked_version_per_branch’.
pick_branch ()
{
	local branch line pick revision
	readonly pick="$1" # the branch we want the revision for

	readonly revision="$(
		echo "$checked_version_per_branch" \
		| sed -n "s/^[[:blank:]]*$pick[[:blank:]]*\([[:graph:]]*\)[[:blank:]]*$/\1/p";
	)"

	if [ -z "$revision" ]
	then
		error "There is no entry for branch ‘$pick’ in ‘checked_version_per_branch’."
		exit 2
	fi

	echo "$revision"
}


# These are needed later for iterating over lines.
readonly default_ifs="$IFS"
readonly newline='
'

if [ -n "$branch" ] # -b flag is set
then
	detect_changes "$branch" "$(pick_branch $branch)"
else
	IFS="$newline" # necessary to iterate over lines
	echo $checked_version_per_branch
	for entry in $checked_version_per_branch
	do
		echo
		echo "in checked_version_per_branch"
		echo
		IFS="$default_ifs" # restore IFS to split $entry into two parameters
		echo $entry
		detect_changes $entry
	done
fi
