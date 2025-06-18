#!/bin/bash

source src/env.sh

command="$1"

case "$command" in

    "start-dev")
        pk_start_dev
        pk_wait_dev
        ;;
    "wait-dev")
        pk_wait_dev
        ;;
    "clean-dev")
        pk_clean_dev
        ;;
    "install")
        pk_install_dev
        ;;
    "install-dev")
        pk_install_dev
        pk_activate_dev
        pk_install_dev_ui
        ;;


esac