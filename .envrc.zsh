#!/usr/bin/env zsh
# Nexus zsh-specific configuration
# This file is sourced by direnv when using zsh

# Add .bin to fpath for completion lookup
if [[ ! "${fpath[*]}" =~ ".bin" ]]; then
    fpath=("${PWD}/.bin" $fpath)
fi

# Source the nx completion file
if [[ -f "${PWD}/.bin/_nx_completion.zsh" ]]; then
    source "${PWD}/.bin/_nx_completion.zsh"
fi
