# d2c.sh

The lightweight IPv4/IPv6 dynamic DNS updater for Cloudflare.

---

d2c.sh is a simple Bash script that automatically updates A and AAAA DNS records on Cloudflare for your machine’s public IP.

### Configure

> [!WARNING]
> d2c.sh updates existing records. Make sure to create them in the Cloudflare dashboard before running d2c.sh.

By default, configuration files are read from `/etc/d2c/`. You can override the configuration directory using the `-c`/ `--config` option.

It processes all files in the configuration directory that end with `.toml`, e.g., `/etc/d2c/d2c.toml`, `/etc/d2c/zone1.toml` or `/etc/d2c/zone2.toml`.

> [!WARNING]
> Make sure to create the correct type of record (A or AAAA) according to IPv4 or IPv6, as d2c.sh will ignore misconfigured records.

```toml
[api]
zone-id = "aaa"           # your DNS zone ID
api-key = "bbb"           # your API key with DNS records permissions

[[dns]]
name = "dns1.example.com" # DNS name
proxy = true              # Proxied by Cloudflare?

[[dns]]
name = "dns2.example.com"
proxy = false

[[dns]]
name = "dns6.example.com"
proxy = false
ipv6 = true               # set this entry as ipv6
```

### Usage

#### Method 1: Installing d2c.sh

Clone the repository:

```sh
$ git clone https://github.com/ddries/d2c.sh.git
$ cd d2c.sh
```

Install the script:

```sh
$ sudo chmod +x d2c.sh
$ sudo cp d2c.sh /usr/local/bin
```

Now, you can run d2c.sh from the command-line. If the configuration directoy does not exist, the script will create it for you.

```sh
$ d2c.sh

Created /etc/d2c/. Please, fill the configuration files.
```

Fill the configuration file(s) with your zone id, API key and the desired DNS':

```sh
$ sudo nano /etc/d2c/d2c.toml

[api]
zone-id = "aaa"
api-key = "bbb"
...
```

Finally, you can run manually d2c.sh or set up a cronjob to update periodically:

```sh
$ d2c.sh # manually

[d2c.sh] Processing /etc/d2c/d2c.toml...
[d2c.sh] dns1.example-1.com did not change
[d2c.sh] Processing /etc/d2c/d2c-1.toml...
[d2c.sh] OK dns2.example-2.com

$ crontab -e # set cronjob to run d2c.sh periodically

$ d2c.sh -c /path/to/files # use another config path
```

#### Method 2: Executing from URL

You can also execute d2c.sh avoiding the installation. Note that you must still have valid configuration file(s), e.g. `/etc/d2c/d2c.toml`.

Execute from URL:

```sh
$ bash <(curl -s https://raw.githubusercontent.com/ddries/d2c.sh/master/d2c.sh)

[d2c.sh] Processing /etc/d2c/d2c.toml...
[d2c.sh] dns1.example-1.com did not change
[d2c.sh] Processing /etc/d2c/d2c-1.toml...
[d2c.sh] OK dns2.example-2.com
```

To run periodically without installing, you can write your own script:

```sh
$ nano run_d2c.sh

#!/bin/bash
bash <(curl -s https://raw.githubusercontent.com/ddries/d2c.sh/master/d2c.sh)

$ crontab -e # set cronjob to run periodically
```

#### Method 3: Docker

You can use the provided Dockerfile to build a Docker image of d2c.sh:

```sh
$ git clone https://github.com/ddries/d2c.sh.git
$ cd d2c.sh
$ docker build . -t ddries/d2c.sh:latest
```

Then, you can run it using your own Docker workflow. For instance, using plain Docker:

```sh
$ docker run --rm --network host -v /etc/d2c/:/etc/d2c ddries/d2c.sh:latest
```

> [!WARNING]
> Make sure to set the network driver to `host`, since the container must have the host's IPv4/6 address.

### Notification Support

d2c.sh by default does not use any notification service, but the following are supported and can be enabled:
- [Gotify](https://gotify.net/)
- [Telegram Bot API](https://core.telegram.org/api/bots)
- ...

When DNS records are updated, d2c.sh will send a notification to enabled services. Feel free to submit a pull request to add more notification services.

#### 1. Gotify

To enable Gotify support, add the following configuration to your `toml` file:

```toml
[gotify]
enabled = true
endpoint = "http://gotify.example.com"
token = "ccc"
```

#### 2. Telegram

To enable notifications via Telegram bot, add the following configuration to your `toml` file:

```toml
[telegram]
enabled = true
token = "aaabbb"    # from BotFather
chat_id = "111234"
```

You can get your chat ID by sending a message to the bot and going to this URL to view the chat_id: `https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates`