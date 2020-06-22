#!/usr/bash
set -e

##### Extract some skill configuration from the incoming event payload
fix=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "push_strategy" ) | .value' )
config=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "config" ) | .value' )
ignores=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "ignores" ) | .value | join(" --ignore ")' )
labels=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "labels" ) | .value' )
branch=$( cat $ATOMIST_PAYLOAD |
  jq -r '.data.Push[0].branch' )

##### Bail out early if it on a markdownlint branch
if [[ "$branch" =~ ^markdownlint-.* ]]
then
    exit 0
fi

##### Make the problem matcher available to the runtime
cp /app/markdownlint.matcher.json /atm/output/matchers/

##### Create push instructions for the runtime to indicate how changes to the repo should get persisted
if [[ -z "$labels" ]]; then
  labels="[]"
fi
push=$( jq -n \
    --arg s "$fix" \
    --argjson l "$labels" \
    '{
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
    )
echo $push > /atm/output/push.json

##### Prepare command arguments
if ! [[ -z "$fix" ]]; then
  fix_option="--fix"
fi

if ! [[ -z "$config" ]] && ! [[ -f "/atm/home/.markdownlint.json" ]]; then
  echo $config > "/atm/input/markdownlint.config.json"
  config_option="--config /atm/input/markdownlint.config.json"
fi

if ! [[ -z "ignores" ]]; then
  ignore_option="--ignore $ignores"
fi

markdownlint "**/*.md" $config_option $ignore_option $fix_option
