#!/bin/bash
# Ansible vault password client. ansible.cfg points vault_password_file here, and the Mac's job
# scripts export ANSIBLE_VAULT_PASSWORD_FILE to it. A copy of the password is in Apple Passwords.
# - Mac: the login keychain (item "ansible-vault")
# - Backup Pi: ~/.config/homelab/vault-pass (pi, 0600; backup-node-remote-control.yml writes it)
if [ "$(uname)" = Darwin ]; then
  exec /usr/bin/security find-generic-password -s ansible-vault -w
fi
exec cat "$HOME/.config/homelab/vault-pass"
