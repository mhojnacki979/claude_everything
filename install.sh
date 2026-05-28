#!/bin/bash
# MFH Holdings Claude Skills Installer
# Run from the directory containing this script

SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"

echo "Installing skills to $SKILLS_DIR..."

for skill in skills/user/*/; do
    name=$(basename "$skill")
    cp -r "$skill" "$SKILLS_DIR/"
    echo "  ✓ Installed: $name"
done

echo ""
echo "Done. Skills installed:"
ls "$SKILLS_DIR"
