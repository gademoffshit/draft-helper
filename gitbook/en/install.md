---
icon: download
---

# Install and update

## Install

1. Download `draft_helper.lua` from the [Ghost page](README.md).
2. Put the file into the `scripts` folder next to the cheat.
3. Open **Scripts > Ghost** in the Umbrella menu and turn on **Enable**.
4. Bind **Open window**: that key opens the window at any time.

{% hint style="info" %}
The file is named `draft_helper.lua` so new versions replace the old one. Don't rename it, or an update leaves two copies.
{% endhint %}

## First start

The first time Ghost downloads match statistics; it takes a couple of minutes and the progress shows in the window header. After that everything comes from the cache and refreshes once a day.

## Updates

Ghost checks for new versions and installs them between matches; nothing reloads during a game. The window header shows which version installs after the match. If a download fails, Ghost retries in a few minutes.

## Troubleshooting

* **The window does not open:** check that **Enable** is on and **Open window** has a key.
* **"No connection to OpenDota":** Ghost keeps working on saved data and retries by itself. If it stays that way, check your VPN or proxy.
* **No build for a hero:** its data downloads from OpenDota the first time the hero is picked, it takes a few seconds.
* **Found a bug:** press **Settings > Reports > Log for the author** to send the log and settings to the developer.
