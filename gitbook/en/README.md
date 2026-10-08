---
icon: ghost
---

# Ghost

Draft hints, an item build for this exact match and auto buy for Umbrella (Dota 2). Ghost reads the draft straight from the game, suggests picks against the enemies and with your allies, and in the match shows what to buy next and can buy it for you.

<!-- versions:start -->
**Download:** [draft_helper.lua](https://github.com/gademoffshit/draft-helper/releases/download/v1.3.1/draft_helper.lua) `v1.3.1`, 2026-10-08

<details>

<summary>All versions</summary>

| Version | Date | File |
| --- | --- | --- |
| [`v1.3.1`](https://github.com/gademoffshit/draft-helper/tree/v1.3.1) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/releases/download/v1.3.1/draft_helper.lua) |
| [`v1.3.0`](https://github.com/gademoffshit/draft-helper/tree/v1.3.0) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/releases/download/v1.3.0/draft_helper.lua) |
| [`v1.2.24`](https://github.com/gademoffshit/draft-helper/tree/v1.2.24) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.24/draft_helper.lua) |
| [`v1.2.23`](https://github.com/gademoffshit/draft-helper/tree/v1.2.23) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.23/draft_helper.lua) |
| [`v1.2.22`](https://github.com/gademoffshit/draft-helper/tree/v1.2.22) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.22/draft_helper.lua) |
| [`v1.2.21`](https://github.com/gademoffshit/draft-helper/tree/v1.2.21) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.21/draft_helper.lua) |
| [`v1.2.20`](https://github.com/gademoffshit/draft-helper/tree/v1.2.20) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.20/draft_helper.lua) |
| [`v1.2.19`](https://github.com/gademoffshit/draft-helper/tree/v1.2.19) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.19/draft_helper.lua) |
| [`v1.2.18`](https://github.com/gademoffshit/draft-helper/tree/v1.2.18) | 2026-10-08 | [draft_helper.lua](https://github.com/gademoffshit/draft-helper/raw/v1.2.18/draft_helper.lua) |

</details>
<!-- versions:end -->

![Draft window and build panel](.gitbook/assets/cover.png)

{% hint style="info" %}
The language follows your Umbrella settings: Ghost speaks English and Russian. New versions install themselves between matches.
{% endhint %}

## What it does

<table><thead><tr><th width="220">Section</th><th>What it does</th></tr></thead><tbody><tr><td><a href="features/draft.md">Draft</a></td><td>who to pick and who to ban for this draft, win chance, the final "who beats whom" table</td></tr><tr><td><a href="features/build.md">Build</a></td><td>purchase order, skills, talents and neutrals for your position, the enemies and the state of the game</td></tr><tr><td><a href="features/panel.md">In-game panel</a></td><td>next item, timings and warnings right on the screen</td></tr><tr><td><a href="features/auto-buy.md">Auto buy</a></td><td>buys by parts, courier, buyback, teleport, selling and backpack</td></tr><tr><td><a href="settings.md">Settings</a></td><td>every item of the settings page and what it changes</td></tr></tbody></table>

## Where the data comes from

* Draft: ranked matches from OpenDota, up to 200,000 per rank, and Captains Mode matches. The data refreshes once a day; Ghost downloads it and keeps a cache.
* Build: pro matches on this hero and position, purchase timings from public games, separate models for lineups, enemy items, skills and talents.
* When OpenDota or GitHub is down, Ghost works on the saved data.

## Quick start

1. Download `draft_helper.lua` and put it into the `scripts` folder of Umbrella.
2. Open **Scripts > Ghost**, turn on **Enable** and bind **Open window**.
3. The window opens by itself on hero pick, the build panel shows up in the match.

More: [Install and update](install.md).
