# Author Time Challenge

A time-attack challenge for **Ballest of Them All**. Race a random mix of game tracks and Workshop maps, beat their author times, and score as many points as possible before time runs out.

## Features

- **Random tracks:** Mix built-in game tracks with Workshop maps.
- **Score points:** Beat a track's author time to earn **1 point**.
- **Gold gives you a free skip:** Beat gold without beating the author time, and you can move on for free—or keep trying for the point.
- **Limited skips:** Skipping normally costs one free skip. When you run out, you need to beat the author time to move on.
- **Loading time doesn't count:** The challenge timer pauses while tracks are loading or downloading.
- **Compact HUD:** Keep an eye on your remaining time, score, skips, and the track's gold (`G:`) and author (`A:`) times.
- **Personal bests:** Your best score is saved for each time-limit, free-skip, and track-pool setup.

## Getting Started

### Requirements

- **Ballest of Them All**
- **Ballest Plugin Manager**, with host version `0.26.0` or newer  (https://github.com/AnythingGoes-ballest/ballest-plugin-manager)

### Install

1. Download this repository.
2. Copy the `author-time-challenge` folder—which contains `info.toml` and `main.as`—into the plugin manager's `plugins` folder.
3. Start the game and open the main menu so the built-in track list can load.
4. Select **Challenge** from the footer, choose your options, and press **Start**.

The plugins folder is inside the game's `Ballest\Binaries\Win64` directory. You can also open the plugin manager's menu in-game and use its option to open the plugins folder.

## Options

| Option | Default | Description |
|---|---:|---|
| Time limit | 10 minutes | How long the challenge lasts. |
| Free skips | 3 | Skips available even when you haven't earned gold. |
| Track pool | Game tracks + subscribed Workshop maps | Choose subscribed Workshop maps or a wider pool of top-rated Workshop maps. |
| Skip key | `K` | Key used to skip the current track; configurable in the Challenge menu. |
| Delay after author time | 3 seconds | Wait time before the next track starts after earning a point. |

### Track pool choices

- **Game tracks + subscribed Workshop maps:** Uses your subscribed maps. Maps that aren't already downloaded are skipped instead of being downloaded during the challenge.
- **Game tracks + any Workshop map:** Uses top-rated Workshop maps, which may need to download before they can be played.

## How Scoring Works

- **Beat the author time:** Earn 1 point. The next track starts after the configured delay.
- **Beat gold, but not the author time:** You can skip the track for free or keep trying for the point.
- **Skip a track:** Press the configured skip key or use the **Skip track** button. This costs one free skip unless you've earned gold on that track.
- **No author time available:** The challenge skips that track for free.
- **Time runs out:** The challenge ends and displays your score.

The HUD shows the remaining challenge time, score, skips left, current track, gold time (`G:`), and author time (`A:`).

## Notes

- Visit the main menu before starting a challenge so the game can provide its built-in track list.
- Third-party custom campaigns are not currently guaranteed to appear in the random pool; their tracks must be exposed through the game's track list to be available.
