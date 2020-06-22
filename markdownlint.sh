#!/usr/bash
set -e

fix=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "push_strategy" ) | .value' )
config=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "config" ) | .value' )
ignores=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "ignores" ) | .value | join(" --ignore ")' )
labels=$( cat $ATOMIST_PAYLOAD |
  jq -r '.skill.configuration.instances[0].parameters[] | select( .name == "labels" ) | .value' )

# copy matcher
cp /app/markdownlint.matcher.json /atm/output/matchers/

# create the push instructions
if [ -z "$labels" ]
then
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
          labels: $l
        },
        commit: {
          message: "MarkdownLint fixes"
        }
    }'
    )
echo $push > /atm/output/push.json

if ! [ -z "$fix" ]
then
  fix_option="--fix"
fi

if ! [ -z "$config" ] && ! [ -f "/atm/home/.markdownlint.json" ]
then
  echo $config > "/atm/input/markdownlint.config.json"
  config_option="--config /atm/input/markdownlint.config.json"
fi

if ! [ -z "ignores" ]
then
  ignore_option="--ignore $ignores"
fi

echo markdownlint **/*.md $config_option $ignore_option $fix_option
markdownlint **/*.md $config_option $ignore_option $fix_option
