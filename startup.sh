#!/usr/bin/env bash
# startup.sh - Install Flutter and Dart if missing.
set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_flutter() {
    FLUTTER_DIR="$HOME/flutter"
    echo "Installing Flutter in $FLUTTER_DIR"
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
    export PATH="$PATH:$FLUTTER_DIR/bin"
    if [ -w "$HOME/.bashrc" ]; then
        echo "export PATH=\"\$PATH:$FLUTTER_DIR/bin\"" >> "$HOME/.bashrc"
    fi
}

if ! command_exists flutter; then
    case "$(uname)" in
        Linux|Darwin)
            install_flutter
            ;;
        *)
            echo "Unsupported OS. Please install Flutter manually." >&2
            exit 1
            ;;
    esac
else
    echo "Flutter already installed." 
fi

# Flutter bundles the Dart SDK. If dart is missing but flutter is installed,
# ensure flutter's bin directory is on the PATH.
if ! command_exists dart; then
    if command_exists flutter; then
        echo "Dart not found. Using Dart SDK from Flutter installation."
        flutter --version >/dev/null 2>&1 || true
    else
        echo "Dart not found and Flutter installation failed." >&2
        exit 1
    fi
else
    echo "Dart already installed."
fi

