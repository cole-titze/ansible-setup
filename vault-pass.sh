#!/bin/bash
# Ansible vault password client: prints the vault password from the macOS login keychain
# (item "ansible-vault"). ansible.cfg points vault_password_file here, and weekly-upgrade.sh
# exports ANSIBLE_VAULT_PASSWORD_FILE to it. A copy of the password is in Apple Passwords.
exec /usr/bin/security find-generic-password -s ansible-vault -w
