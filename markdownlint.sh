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

# print message to stdout prefixed by package name.
# usage: msg MESSAGE
function msg () {
    echo "$Pkg: $*"
}

# print message to stderr prefixed by package name.
# usage: err MESSAGE
function err () {
    msg "$*" 1>&2
}

function main () {
    # Extract some skill configuration from the incoming event payload
    local fix config ignores labels branch
    fix=$( < "$ATOMIST_PAYLOAD" \
             jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "push_strategy" ) | .value' )
    if [[ $? -ne 0 ]]; then
        err "Failed to extract push_strategy parameter"
        return 1
    fi
    config=$( < "$ATOMIST_PAYLOAD" \
                  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "config" ) | .value' )
    if [[ $? -ne 0 ]]; then
        err "Failed to extract config parameter"
        return 1
    fi
    ignores=$( < "$ATOMIST_PAYLOAD" \
                   jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "ignores" ) | .value[]' )
    if [[ $? -ne 0 ]]; then
        err "Failed to extract ignores parameter"
        return 1
    fi
    labels=$( < "$ATOMIST_PAYLOAD" \
                  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "labels" ) | .value' )
    if [[ $? -ne 0 ]]; then
        err "Failed to extract labels parameter"
        return 1
    fi
    branch=$( < "$ATOMIST_PAYLOAD" jq -r '.data.Push[0].branch' )
    if [[ $? -ne 0 ]]; then
        err "Failed to extract branch of push"
        return 1
    fi

    # Bail out early if it on a markdownlint branch
    if [[ $branch == markdownlint-* ]]; then
        exit 0
    fi

    local outdir=${ATOMIST_OUTPUT_DIR:-/atm/output}

    # Make the problem matcher available to the runtime
    local matcher_outdir=$outdir/matchers
    if ! mkdir -p "$matcher_outdir"; then
        err "Failed to create matcher output directory: $matcher_outdir"
        return 1
    fi
    if ! cp /app/markdownlint.matcher.json "$matcher_outdir"; then
        err "Failed to copy markdownlink.matcher.json to $matcher_outdir"
        return 1
    fi

    # Create push instructions for the runtime to indicate how changes to the repo should get persisted
    if [[ ! $labels ]]; then
        labels="[]"
    fi

    if ! > "$outdir/push.json" jq -n --arg s "$fix" --argjson l "$labels" '{
    strategy: $s,
    pullRequest: {
      title: "MarkdownLint fixes",
      body: "MarkdownLint fixed warnings and/or errors",
      branchPrefix: "markdownlint",
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
        err "failed to write $outdir/push.json"
        return 1
    fi

    # Prepare command arguments
    local fix_option=
    if [[ $fix ]]; then
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
        if ! echo "$ignores" > "$ignore_file"; then
            err "Failed to create MarkdownLint ignore file $ignore_file"
            return 1
        fi
        ignore_option="--ignore-path $ignore_file"
    fi

    exec markdownlint "**/*.md" $config_option $ignore_option $fix_option
}

main "$@"
