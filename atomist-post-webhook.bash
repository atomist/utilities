#!/bin/bash
# post webhook payloads to Atomist webhook endpoints
# usage: atomist-post-webhook TYPE WORKSPACE [...]

declare Pkg=atomist-post-webhook
declare Version=0.1.0

# print message to standard output
# usage: msg MESSAGE...
function msg () {
    echo "$Pkg: $*"
}

# print error message standard error
# usage: err MESSAGE...
function err () {
    msg "$*" 1>&2
}

# post payload to Atomist webhook
# usage: post-payload TYPE WORKSPACE PAYLOAD
function post-payload () {
    local type=$1
    if [[ ! $type ]]; then
        err "post-payload: missing required argument: TYPE WORKSPACE PAYLOAD"
        return 10
    fi
    shift
    local workspace=$1
    if [[ ! $workspace ]]; then
        err "post-payload: missing required argument: WORKSPACE PAYLOAD"
        return 10
    fi
    shift
    local payload=$1
    if [[ ! $payload ]]; then
        err "post-payload: missing required argument: PAYLOAD"
        return 10
    fi
    shift

    local base_url=${ATOMIST_WEBHOOK_BASEURL:-https://webhook.atomist.com}
    local url=$base_url/atomist/$type/teams/$workspace

    msg "posting payload to '$url': '$payload'"
    if ! curl -s -f -X POST -H "Content-Type: application/json" --data-binary "$payload" "$url" > /dev/null 2>&1
    then
        err "failed to post payload '$payload' to '$url'"
        return 1
    fi
}

# post CodeShip build status, one of "started", "failed", "error", "passed", "canceled"
# usage: post-build-codeship WORKSPACE STATUS
function post-build-codeship () {
    local workspace=$1
    if [[ ! $workspace ]]; then
        err "post-build-codeship: missing required argument: WORKSPACE TRIGGER STATUS"
        return 10
    fi
    shift
    local status=$1
    if [[ ! $status ]]; then
        err "post-build-codeship: missing required argument: STATUS"
        return 10
    fi
    shift

    local owner=${CI_REPO_NAME%/*}
    local repo=${CI_REPO_NAME#*/}
    local sha=$CI_COMMIT_ID
    local type=push pr
    if [[ $CI_PULL_REQUEST != false ]]; then
        type=pull_request
        printf -v pr ',"pull_request_number":%d' "$CI_PULL_REQUEST"
    fi
    local number=$CI_BUILD_NUMBER
    local id=codeship-$CI_REPO_NAME-$CI_BUILD_ID
    local name=$CI_REPO_NAME-$CI_BUILD_ID
    local url=$CI_BUILD_URL
    local branch=$CI_BRANCH
    local payload
    printf -v payload '{"repository":{"owner_name":"%s","name":"%s"},"commit":"%s","status":"%s","type":"%s","number":%d,"id":"%s","name":"%s","build_url":"%s","branch":"%s","provider":"codeship"%s}' \
           "$owner" "$repo" "$sha" "$status" "$type" "$number" "$id" "$name" "$url" "$branch" "$pr"

    post-payload build "$workspace" "$payload"
}

# create a link between a docker image and a commit
# usage: link-image-codeship WORKSPACE DOCKER_IMAGE
function link-image-codeship () {
    local workspace=$1
    if [[ ! $workspace ]]; then
        err "missing required argument: WORKSPACE DOCKER_IMAGE"
        return 10
    fi
    shift
    local image=$1
    if [[ ! $image ]]; then
        err "link-image: missing required argument: DOCKER_IMAGE"
        return 10
    fi
    shift

    local owner=${CI_REPO_NAME%/*}
    local repo=${CI_REPO_NAME#*/}
    local sha=$CI_COMMIT_ID
    local payload
    printf -v payload '{"git":{"owner":"%s","repo":"%s","sha":"%s"},"docker":{"image":"%s"},"type":"link-image"}' \
           "$owner" "$repo" "$sha" "$image"

    post-payload link-image "$workspace" "$payload"
}

# main function
# usage: main "$@"
function main () {
    local type=$1
    if [[ ! $type ]]; then
        err "missing required argument: TYPE WORKSPACE"
        return 10
    fi
    shift
    local workspace=$1
    if [[ ! $workspace ]]; then
        err "missing required argument: WORKSPACE"
        return 10
    fi
    shift

    if [[ $CODESHIP ]]; then
        case "$type" in
            link-image)
                if ! link-image-codeship "$workspace" "$@"; then
                    return 1
                fi
                ;;
            build)
                if ! post-build-codeship "$workspace" "$@"; then
                    return 1
                fi
                ;;
        esac
    else
        err "unsupported CI platform"
        return 2
    fi
}

main "$@" || exit 1
exit 0
