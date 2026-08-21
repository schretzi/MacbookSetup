import shutil
import subprocess

# omt comes from the schretzi/tap cask, so it normally sits in the Homebrew
# prefix. offlineimap can run from a LaunchAgent with a stripped PATH, hence
# the explicit fallback.
OMT = shutil.which("omt") or "/opt/homebrew/bin/omt"


def get_token(email_address):
    """Return a valid OAuth2 access token for email_address via omt.

    omt owns the entire OAuth lifecycle (authorization, refresh, keyring
    storage); this just asks it for whatever's currently valid and hands
    the bearer token straight to offlineimap's XOAUTH2 eval.
    """
    result = subprocess.run(
        [OMT, "token", email_address],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"omt token {email_address} failed (exit {result.returncode}): "
            f"{result.stderr.strip()}"
        )
    return result.stdout.strip()
