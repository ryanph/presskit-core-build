#!/bin/bash

source src/env.sh

command="$1"

case "$command" in
    "build")
        pk_build_wordpress
        pk_wait_wordpress
        ;;
    "clean")
        pk_clean_build
        ;;
    "build-wordpress")
        pk_build_wordpress
        ;;
    "check-wordpress")
        pk_wait_wordpress
        ;;
    "install-core")
        pk_install_core
        pk_install_core_ui
        pk_activate_core
        ;;
    "activate-core")
        pk_activate_core
        ;;
esac