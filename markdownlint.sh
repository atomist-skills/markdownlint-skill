#! /bin/bash
#
# Copyright © 2020 Atomist, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

declare Pkg=markdownlint
declare Version=0.1.0

set -o pipefail

# Print message to stdout prefixed by package name.
# usage: msg MESSAGE
function msg () {
    echo "$Pkg: $*"
}

# Print message to stderr prefixed by package name.
# usage: err MESSAGE
function err () {
    msg "$*" 1>&2
    status 1 "$*"
}

# Write status to output location.
# usage: status CODE MESSAGE
function status () {
    local code=$1
    if [[ ! $code ]]; then
        err "status: Missing required argument: CODE"
        return 1
    fi
    shift
    local reason=$2

    local status_file=${ATOMIST_STATUS:-/atm/output/status.json}
    if ! printf '{"code":%d,"reason":"%s"}\n' "$code" "$reason" > "$status_file"; then
        err "status: Failed to write status to $status_file"
        return 1
    fi
}

# Extract parameters from payload and run markdownlint.
# usage: main "$@"
function main () {
    # Extract some skill configuration from the incoming event payload
    local payload=${ATOMIST_PAYLOAD:-/atm/payload.json}
    local config ignores labels push_strategy
    eval "$(jq -r ".skill.configuration.parameters[] | select(.value) | \"\\(.name)='\\(.value)';\"" "$payload")"
    if [[ $? -ne 0 ]]; then
        err "Failed to extract parameters from payload"
        return 1
    fi

    local branch
    branch=$(jq -r '.data.Push[0].branch' "$payload")
    if [[ $? -ne 0 ]]; then
        err "Failed to extract branch of push"
        return 1
    fi
    # Bail out early if it on a markdownlint branch
    if [[ $branch == markdownlint-* ]]; then
        exit 0
    fi
    local commitMsg
    commitMsg=$(jq -r '.data.Push[0].after.message' "$payload")
    if [[ $? -ne 0 ]]; then
        err "Failed to extract commit message of push"
        return 1
    fi
    # Bail out early if linting own commit
    if [[ $commitMsg == *"[atomist:generated]"* ]]; then
        exit 0
    fi
    # Bail if no Markdown files exists in current project
    if [[ -z $(find . -name '*.md') ]]; then 
        exit 0
    fi


    local outdir=${ATOMIST_OUTPUT_DIR:-/atm/output}

    # Make the problem matcher available to the runtime
    local matchers_dir=${ATOMIST_MATCHERS_DIR:-$outdir/matchers}
    if ! mkdir -p "$matchers_dir"; then
        err "Failed to create matcher output directory: $matchers_dir"
        return 1
    fi
    if ! cp /app/markdownlint.matcher.json "$matchers_dir"; then
        err "Failed to copy markdownlink.matcher.json to $matchers_dir"
        return 1
    fi

    # Create push instructions for the runtime to indicate how changes to the repo should get persisted
    if [[ ! $labels ]]; then
        labels="[]"
    fi

    local push_file=${ATOMIST_PUSH:-$outdir/push.json}
    if ! > "$push_file" jq -n --arg s "$push_strategy" --argjson l "$labels" '{
    strategy: $s,
    pullRequest: {
      title: "MarkdownLint fixes",
      body: "MarkdownLint fixed warnings and/or errors",
      branchPrefix: "atomist/markdownlint",
      labels: $l,
      close: {
        stale: true,
        message: "Closing pull request because all fixable warnings and/or errors have been fixed in base branch"
      }
    },
    commit: {
      message: "MarkdownLint fixes"
    }
}'
    then
        err "failed to write $push_file"
        return 1
    fi

    # Prepare command arguments
    local fix_option=
    if [[ $push_strategy ]]; then
        fix_option=--fix
    fi
    local homedir=${ATOMIST_HOME:-/atm/home}
    local inputdir=${ATOMIST_INPUT_DIR:-/atm/input}
    local config_option=
    if [[ $config && ! -f "$homedir/.markdownlint.json" ]]; then
        local config_file=$inputdir/markdownlint.config.json
        if ! echo "$config" > "$config_file"; then
            err "Failed to create MarkdownLint configuration file $config_file"
            return 1
        fi
        config_option="--config $config_file"
    fi
    local ignore_option=
    if [[ $ignores ]]; then
        local ignore_file=$inputdir/markdownlint.ignore
        if ! echo "$ignores" | jq -r '.[]' > "$ignore_file"; then
            err "Failed to create MarkdownLint ignore file $ignore_file"
            return 1
        fi
        ignore_option="--ignore-path $ignore_file"
    fi

    markdownlint "**/*.md" $config_option $ignore_option $fix_option
    local mdl_rv=$?
    local code reason rv
    case "$mdl_rv" in
        0)
            code=0
            reason="No errors or warnings found"
            rv=0
            ;;
        1)
            code=0
            reason="One or more errors found"
            rv=0
            ;;
        2)
            code=0
            reason="Unable to write output file"
            rv=1
            ;;
        3)
            code=0
            reason="Unable to load custom rule"
            rv=1
            ;;
        *)
            code=1
            reason="Unknown markdownlint exit code"
            rv=$mdl_rv
            ;;
    esac
    if ! status "$code" "$reason"; then
        return 1
    fi

    return "$rv"
}

main "$@"
