
dehydrated-hook-cloudflare
==========================

Single file, pure Bash [dehydrated](https://github.com/lukas2511/dehydrated) (formely letsencrypt.sh) hook using the [CloudFlare](https://cloudflare.com/) API implementing the [dns-01 ACME challenge](https://tools.ietf.org/html/draft-ietf-acme-acme).

Requirements
------------

 * [Bash](https://www.gnu.org/software/bash/)
 * [mawk](http://invisible-island.net/mawk/mawk.html) or [GNU AWK](https://www.gnu.org/software/gawk/)
 * [jq](https://github.com/stedolan/jq)
 * [publicsuffix](https://packages.debian.org/stable/publicsuffix)
 * [drill](https://nlnetlabs.nl/projects/ldns/about/) or [dig](https://packages.debian.org/stable/dnsutils)

All the packages are available on the latest [Debian](https://debian.org) stable (jessie, at the time of writing), and may be installed using:
```bash
sudo apt-get install bash gawk jq publicsuffix ldnsutils
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

Usage
-----

Instead of editing the `cf-hook.sh` script to inject the authentication variables, I recommend that you instead create a `local-hook.sh` script and call the Cloudflare hook from there after initialising the authentication variables.

  - Create a the `/etc/dehydrated/local-hook.sh` script with, for example:

    ```bash
    #!/bin/bash -e
    
    export CF_TOKEN=<YOUR_TOKEN_GOES_HERE>
    ./cf-hook.sh $*
    
    # On success you can for example reload nginx
    if [ "$1" == deploy_cert ]; then
        systemctl reload nginx
    fi
    ```

  - Make sure it's executable with `chmod 755 /etc/dehydrated/local-hook.sh`.

  - Create a new local configuration file at `/etc/dehydrated/conf.d/local.sh` pointing to the local hook:

    ```bash
    CHALLENGETYPE=dns-01
    HOOK=/etc/dehydrated/local-hook.sh
    ```
