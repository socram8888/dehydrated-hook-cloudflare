
dehydrated-hook-cloudflare
==========================

Single file, pure Bash [dehydrated](https://github.com/lukas2511/dehydrated) (formely letsencrypt.sh) hook using the [CloudFlare](https://cloudflare.com/) API implementing the [dns-01 ACME challenge](https://tools.ietf.org/html/draft-ietf-acme-acme).

Requirements
------------

 * [Bash](https://www.gnu.org/software/bash/)
 * [mawk](http://invisible-island.net/mawk/mawk.html) or [GNU AWK](https://www.gnu.org/software/gawk/)
 * [jq](https://github.com/stedolan/jq)
 * [publicsuffix](https://packages.debian.org/stable/publicsuffix)

All the packages are available on the latest [Debian](https://debian.org) stable (jessie, at the time of writing), and may be installed using:
```bash
sudo apt-get install bash awk jq publicsuffix
```

Configuration
-------------

This hook supports authenticating using either a bearer token or the global API key. Both can be obtained at the ["API tokens"](https://dash.cloudflare.com/profile/api-tokens) section.

### Bearer token

This is the preferred method, as the allowed operations can be limited to updating a single DNS zone.

For this method, you'd need to `export` the `CF_TOKEN` variable, with a suitable token that has read/write access to the DNS zone for which you want to issue certificates.

### API key

This method is less secure, as if someone were capable of reading these keys they'd have full access to your account.

For this method, you'd need to `export` the `CF_EMAIL` and `CF_KEY` variables with your CloudFlare email and API key respectively.
