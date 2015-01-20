#CURRENT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
#DOCKER_IMAGE_NAME := "tails$(if $(CURRENT_BRANCH),-$(CURRENT_BRANCH))"
DOCKER_IMAGE_NAME := "tails_builder"
DOCKER_MOUNT := "$(shell pwd):/root/tails"
DOCKER_RUN := docker run --rm --privileged -v $(DOCKER_MOUNT) -t $(DOCKER_IMAGE_NAME)
BUILD_COMMAND := apt-get update && apt-get dist-upgrade && lb clean --all && lb config --cache false && lb build

default: all

all: containers iso_image

iso_image:
	$(DOCKER_RUN) "$(BUILD_COMMAND)"

containers: builder_container

builder_container:
	docker build -t "$(DOCKER_IMAGE_NAME)" .
