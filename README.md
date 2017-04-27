
dehydrated-hook-cloudflare
==========================

Single file, pure Bash [dehydrated](https://github.com/lukas2511/dehydrated) (formely letsencrypt.sh) hook using the [CloudFlare](https://cloudflare.com/) API implementing the [dns-01 ACME challenge](https://tools.ietf.org/html/draft-ietf-acme-acme).

Requirements
------------

 * [Bash](https://www.gnu.org/software/bash/) (
 * [mawk](http://invisible-island.net/mawk/mawk.html) or [GNU AWK](https://www.gnu.org/software/gawk/)
 * [jq](https://github.com/stedolan/jq)
 * [publicsuffix](https://packages.debian.org/stable/publicsuffix)

All the packages are available on the latest [Debian](https://debian.org) stable (jessie, at the time of writing), and may be installed using:
```bash
sudo apt-get install bash awk jq publicsuffix
```

Configuration
-------------

The scripts expects the following environment variables to be set:
 - `CF_EMAIL`: the e-mail linked to your CloudFlare account
 - `CF_KEY`: your API key. You may get yours at CloudFlare → ["My Account"](https://www.cloudflare.com/a/account/my-account).
