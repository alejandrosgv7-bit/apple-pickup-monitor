# Apple Store pickup monitor

Get a push notification on your phone the moment an iPhone becomes available for in-store
pickup at a nearby Apple Store.

It ships configured for the **iPhone 18 Pro Max** (16 variants) at the **12 Apple Stores in
New York City**, but works for any product and any US area by editing two dictionaries
(see [Adapting it](#adapting-it-to-other-models-or-cities)).

- One Python file, standard library only. No browser, no cookies, no login.
- Alerts via [ntfy](https://ntfy.sh) (free, no account) and/or Telegram, with "Buy" buttons.
- Smart alerting: one alert per new (store, model), a "gone" message with how long it lasted,
  a single summary during big restocks, and a heads-up if the monitor itself stops working.

> In practice stock showed up one unit at a time and was gone in **4 to 6 minutes**, so poll
> often and have the Apple Store app signed in with Apple Pay ready.

## Quick start

```sh
cp .env.example .env            # set NTFY_TOPIC to a long random name
set -a; . ./.env; set +a
python3 monitor.py --once       # single check, prints what's available
python3 monitor.py              # keep polling
```

Install the ntfy app ([iOS](https://apps.apple.com/app/ntfy/id1625396347) /
[Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)) and subscribe to
the same topic. Anyone who knows the topic name can read it, so keep it random.

Requires Python 3.9+.

## How it works

```
GET https://www.apple.com/shop/retail/pickup-message?pl=true&location=<zip>&parts.0=<part>&parts.1=<part>...
```

Returns the ~12 stores nearest to `<zip>`, each with `partsAvailability[<part>].pickupDisplay`
(`available` / `unavailable`). No auth needed.

- `/shop/fulfillment-messages`, the endpoint most older scripts use, now returns HTTP 541. Don't use it.
- `LOCATIONS` lists the zips to query; results are filtered to `STORES`.
  `10001` covers every NYC store except Staten Island, which needs `10314` too.
- An alert fires when a (store, model) pair goes from unavailable to available. Once it has been
  missing for 2 consecutive checks, a "no longer available" message says how long it lasted.
- **Wave mode:** if 6+ pairs are available at once, or 3 alerts fire within 10 min, you get one
  urgent summary grouped by model, then silence until availability drops to 2 or fewer.
- **Health alerts:** one message after 10 min without a successful check (at least 2 failed
  checks), at most one per hour, and a quiet "back to normal" afterwards. A response missing more
  than half the watched stores counts as a failure, so a silently broken response can't hide stock.

## Proxy (needed on cloud hosts)

From a home connection it works as is. **Apple answers HTTP 541 to datacenter IPs** (Fly.io was
blocked within hours), so on any cloud host set `PROXY_URL`. It is used only for Apple requests;
notifications go out directly.

[Webshare](https://www.webshare.io)'s free plan (10 proxies, 1 GB) was accepted by Apple. Use
its rotating endpoint: the username needs the `-rotate` suffix, otherwise you get HTTP 407.

```sh
PROXY_URL=http://<user>-rotate:<pass>@p.webshare.io:80/
```

**Bandwidth:** Apple doesn't compress this response, so each zip costs ~145 KB per check
(16 models: ~230 KB). One zip every 30 s is ~420 MB/day. To stretch a small allowance, poll
less at night with `NIGHT_INTERVAL` + `ACTIVE_HOURS`, and watch fewer models with `CAPACITIES`.

## Deploy to Fly.io

```sh
fly auth login
fly apps create <your-app-name>           # then set `app` in fly.toml
fly secrets set NTFY_TOPIC=<topic> PROXY_URL=<proxy-url>
fly deploy --ha=false
fly logs                                  # "ok stores=11 available=0 ..." on every check
```

`fly.toml` is tuned for a 1 GB proxy budget over about four days. Tear it down when you're
done: `fly apps destroy <your-app-name>`.

Any Docker host works too:

```sh
docker build -t pickup-monitor .
docker run -d --restart=always --env-file .env pickup-monitor
```

## Configuration

All settings are environment variables.

| Var | Default | |
|---|---|---|
| `NTFY_TOPIC` / `NTFY_SERVER` | – / `https://ntfy.sh` | ntfy topic to publish to |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | – | optional, in addition to or instead of ntfy |
| `PROXY_URL` | – | `http://user:pass@host:port`, for Apple requests only |
| `INTERVAL` | `60` | seconds between checks (±15% jitter) |
| `NIGHT_INTERVAL` | `INTERVAL` | seconds between checks outside `ACTIVE_HOURS` |
| `ACTIVE_HOURS` | `0-24` | `start-end` hours in `STORE_TZ`, e.g. `8-22` |
| `STORE_TZ` | `America/New_York` | time zone for `ACTIVE_HOURS` |
| `CAPACITIES` | `ALL` | e.g. `256gb,512gb` |
| `LOCATIONS` | `10001,10314` | zips to query |
| `STORES` | all NYC stores | comma-separated store numbers, or `ALL` for every store returned |
| `GONE_AFTER_CHECKS` | `2` | consecutive misses before a "no longer available" message |
| `WAVE_START_ITEMS` / `WAVE_START_ALERTS` / `WAVE_WINDOW_MINUTES` / `WAVE_END_ITEMS` | `6` / `3` / `10` / `2` | wave mode tuning |
| `FAIL_ALERT_MINUTES` | `10` | alert after this long without a successful check |
| `FAIL_ALERT_COOLDOWN_MINUTES` | `60` | minimum gap between health alerts |

## Adapting it to other models or cities

Edit two dictionaries at the top of `monitor.py`:

- **`PARTS`** maps Apple part numbers to `(capacity, color)`. To find them, open the product's buy
  page on apple.com, pick a model, click "Check availability" for pickup, and look for the
  `pickup-message` request in your browser's DevTools Network tab: the part number is in
  `parts.0` (e.g. `MJW44LL/A`). US part numbers are the same for every carrier and unlocked.
  Also update `product_url()`, which builds the "Buy" link.
- **`NYC_STORES`** maps store numbers to names. List the stores near a zip with:

  ```sh
  curl -s 'https://www.apple.com/shop/retail/pickup-message?pl=true&location=<zip>&parts.0=MJW44LL/A' \
    | python3 -c "import json,sys; [print(s['storeNumber'], s['storeName']) for s in json.load(sys.stdin)['body']['stores']]"
  ```

Then set `LOCATIONS` to one or more zips that cover those stores.

## Disclaimer

Unofficial and not affiliated with Apple. It uses an undocumented endpoint that can change or
disappear at any time. Keep the polling rate reasonable, and use it only to know when to buy,
not to automate purchases.

## License

[MIT](LICENSE)
