#!/bin/bash
set -e

#Bulk Docker image building
#
#First builds the parent images (which depend on something from the docker repository)
#and then build those ones which depend on the images built at the first stage.
#
#The first argument is:
#	- the path to a directory containing subfolders with Dockerfile files.
#	  The script loops through the subfolders and builds docker images images using 
#	  the dockerfiles from them
#	- the path to a particular Dockerfile for building just one image
#
#The remaining arguments are considered as build args

#the base directory to look up subdirectories with dockerfiles in
IMAGES_DIR=$1

#filtered dockerfile paths
DOCKERFILE_PATHS=()

#the tags of the base images
BASE_IMAGE_TAGS=()

#the rest of args is build args
shift 1

#build args passed to docker build
BUILD_ARGS="$@"

#print line
function print {
    local RED='\033[0;31m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'

    local text=$2

    case $1 in
        'info' )
            echo -e "${BLUE}${text}${NC}" ;;

        'warn' )
            echo -e "${YELLOW}${text}${NC}" ;;

        'error' )
            echo -e "${RED}${text}${NC}" ;;

        *)
        echo $2;
    esac
}

if [[ -d $IMAGES_DIR ]]; then
    print warn "Building multiple images"
	SUBDIRECTORIES=$(find ${IMAGES_DIR} -mindepth 1 -maxdepth 1 -type d)
elif [[ -f $IMAGES_DIR ]]; then
    echo "Building single image"
	SUBDIRECTORIES=( $(realpath $(dirname .)) )
else
    echo "$IMAGES_DIR is not valid"
    exit 1
fi

#build a docker image
function buildImage {
	if [ ${#BUILD_ARGS[@]} -eq 0 ]; then
    		docker build -t "$1" "$2"
	else
    		print info "Using build args: ${BUILD_ARGS[@]}";
    		docker build ${BUILD_ARGS[@]} -t "$1" "$2"
	fi
}

#checks whether the image tag is a child image
function isChildImage {
    if [[ ${BASE_IMAGE_TAGS[*]} =~ ${1} ]] ; then
        echo false;
    else
        echo true;
    fi
}

#builds docker images
function buildImages {
    case $1 in
        parent )
            print warn "Building parent images..." ;;

        child )
            print warn "Building child images..." ;;

        *)
        print error "Usage: buildImages {parent|child}"
        exit 1
    esac

    for CONTEXT in ${DOCKERFILE_PATHS[@]} ; do
        DOCKERFILE="${CONTEXT}/Dockerfile"

	#find the image tag in the dockerfile
        CHILD_IMAGE_TAG=$(sed -rn 's/tag="(.+)"/\1/p' ${DOCKERFILE} |  tr -d ' ')

        if [ -z ${CHILD_IMAGE_TAG} ]; then
            print error "Dockerfile ${DOCKERFILE} lacks the child image tag"
            exit 1;
        else
            IS_CHILD_IMAGE=$(isChildImage ${CHILD_IMAGE_TAG})

            case $1 in
                parent )
                    if [ ${IS_CHILD_IMAGE} = false ] ; then
                        print info "Building parent image from ${DOCKERFILE} tagged as ${CHILD_IMAGE_TAG}..."
                        buildImage ${CHILD_IMAGE_TAG} ${CONTEXT}
                    fi
                    ;;

                child )
                    if [ ${IS_CHILD_IMAGE} = true ] ; then
                        print info "Building child image from ${DOCKERFILE} tagged as ${CHILD_IMAGE_TAG}..."
                        buildImage ${CHILD_IMAGE_TAG} ${CONTEXT}
                    fi
                    ;;
            esac
        fi
    done
}

print warn "Looking up Dockerfile files..."

#filter the dockerfile paths and gather the base image tags
for SUBDIRECTORY in ${SUBDIRECTORIES[@]} ; do
    DOCKERFILE="${SUBDIRECTORY}/Dockerfile"

    if [ -f ${DOCKERFILE} ]; then
        BASE_IMAGE_TAG=$(sed -rn 's/FROM\s+([^:]+)(:.*)?/\1/p' ${DOCKERFILE} |  tr -d ' ')

        if [ -z ${BASE_IMAGE_TAG} ]; then
            print error "Dockerfile ${DOCKERFILE} lacks the base image tag"
            exit 1;
        else
            print info "Dockerfile found at ${SUBDIRECTORY}, base image tag ${BASE_IMAGE_TAG}"
            DOCKERFILE_PATHS+=(${SUBDIRECTORY})
            BASE_IMAGE_TAGS+=(${BASE_IMAGE_TAG})
        fi
    fi
done

#First build parent and then child images
buildImages parent
buildImages child

print warn "Finished"

exit 0;
