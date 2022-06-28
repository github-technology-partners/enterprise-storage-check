#!/bin/bash
#/ Usage: ghe-storage-test.sh [-pcvh]
#/
#/ Runs storage provider tests for the provider blob storage endpoint.
#/
#/ If no parameters are specified it opens interactive shell. Only use this
#/ mode if directed by GitHub Enterprise support.
#/
#/ OPTIONS:
#/   -p | --provider    Storage provider, one of 's3' or 'azure'
#/   -c | --connection-string    Connection string to the blob storage
#/   -v | --version     GHES version (e.g. '3.3'), if omitted uses the latest released one
#/   -h | --help        Show this message
#/
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
tag="latest"
command=
provider=
connection_string=
pwsh_params=()
docker_params=()
env_vars=()

usage() {
    grep '^#/' < "$0" | cut -c 4-
    exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--provider)
      provider="$2"
      shift 2
      ;;
    -c|--connection-string)
      connection_string="$2"
      shift 2
      ;;
    -v|--version)
      tag="ghes-$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      >&2 echo "Unrecognized argument: $1"
      usage
      ;;
  esac
done

image="ghcr.io/github-technology-partners/enterprise-storage-check/actions-console:$tag"

if [[ -z "$connection_string" ]]; then
  pwsh_params+=("-NoExit")
  docker_params+=("-it")
else
  if [[ -z "$provider" ]]; then
    echo -e "${RED}Storage provider must be specified with '-p' parameter${NC}"
    exit 1
  fi
  command="Test-StorageConnection -OverrideBlobProvider $provider -OverrideConnectionString '$connection_string'"
fi

docker_params+=("--mount" "type=tmpfs,destination=/home/actions/.actions-dev")
docker_params+=("--mount" "type=tmpfs,destination=/LR/Logs")

# Configure Application settings
env_vars+=("ApplicationSettings__DeploymentType=OnPremises")
env_vars+=("ApplicationSettings__DeploymentEnvironment=Ghes")

# Create a protected temp file to store the env vars.
temp_file="$(mktemp)"

function cleanup {
    rm -f "$temp_file"
}

trap cleanup EXIT
( IFS=$'\n'; echo "${env_vars[*]}" ) > "$temp_file"

docker_run() {
  docker run \
    --rm \
    --entrypoint pwsh \
    --network host \
    --env-file "$temp_file" \
    "${docker_params[@]}" \
    "$image" \
    "${pwsh_params[@]}" Invoke-LightRail.ps1 -Initial "Actions/OnPrem" -Command "$1"
}

# Launch the Actions console.
if [[ -z "$command" ]]; then
  echo -e "${ORANGE}Starting interactive shell...${NC}"
  docker_run "$command"
else
  echo -e "${GREEN}Running storage tests...${NC}"
  check_warning_command="help Test-StorageConnection  | grep 'TreatWarningAsErrors'"
  warning_check=$(docker_run "$check_warning_command")
  if [[ ! -z "$warning_check" ]]; then
    command="${command} -TreatWarningAsErrors"
  fi
  # sed commands make the LightRail output more readable.
  docker_run "$command" | sed 's/      \+/\n/g' | sed 's/    //g' | sed "s/^/LR actions> /"
  exit "${PIPESTATUS[0]}"
fi
