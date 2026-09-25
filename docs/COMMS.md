# The uplink: Gateway Control, and the thing that answers

Kestrel-9's story is not written on the walls. It arrives over the radio, one shift at a time, and
you answer it. The comms console is the instrument the plot is played on: everything the game
tells you about what is happening here comes through it, and the only thing it asks of you is that
you key the mic once a shift and say you are still alive.

## The loop

| When | What happens |
|---|---|
| 20 s into a shift | An attention tone, the squelch opens, and **GATEWAY CONTROL, HOUSTON** reads you a message. A notice says where the console is; the console prints the message line by line, at the pace it is spoken. |
| When it finishes | Your shift report comes due. The console's screen turns amber and the wrist terminal says `COMMS: shift report due`. |
| Whenever you get there | Point at the console and hold **TRIGGER** (**USE** on a phone) for 2.5 s. The mic keys, and your own voice reads your report back to Earth. A tool in your hand makes no difference - you are pressing a key, not fixing anything. |
| If you never key up | It counts as a missed report. Gateway opens the next shift asking why you went quiet, before it says anything else. |
| Nights 4 and 6 | If anything wakes you (a power failure, a toilet trip - see the README's "The nights"), the console keys up by itself. The uplink runs off its own cell, so in a power failure it is the one screen still lit in the dark. A quiet night you sleep straight through it, and it is gone. |

Nothing about the uplink gates the maintenance shift: you can ignore it for a whole run and still
survive seven nights. It costs you the story, and Gateway keeps asking.

## What it says

`comms/log.json` is the script. Seven inbound messages, seven replies, two night carriers, plus the
one Gateway sends when you skipped a report and the one that plays over the rescue.

1. **Day 1** - routine. The rest of the crew rotated home eleven days ago; the relief shuttle is
   booked for day eight. Send your report at the end of the shift.
2. **Day 2** - flight has a question about the power trace. Deck lighting drew current for nine
   minutes at 03:00 station time, while you were asleep.
3. **Day 3** - life support has been scrubbing carbon dioxide for two people for six days.
   *We are not saying anything by that. Confirm your crew count.*
4. **Day 4** - Gateway answers a report you have not sent yet. The round trip is four minutes.
5. **Day 5** - stop transmitting at night. Eleven minutes of voice traffic off your airlock at
   02:40, run against your voice file. It is you, and it is asking to be let in.
6. **Day 6** - the shuttle is away. On the hail, the station answered with a manifest of two souls
   aboard. *Confirm that you are alone.*
7. **Day 7** - do not open the inner hatch until they have hard dock and they say your name.

The two night carriers are the same voice run slow and overdriven: night 4 reads your own day 3
report back at you in Gateway's cadence, night 6 files a manifest you did not write, and knows
where you are standing.

Changing any of it is one file and one command:

```
$EDITOR comms/log.json
python3 tools/gen_voice.py        # re-renders audio/voice/<id>.wav for every entry
```

`scripts/comms.gd` never looks at the words - it looks at `id`, `day` and `kind`
(`inbound` / `reply` / `night`), so a longer story is more entries, not more code.

## The radio voice

There is no speech engine in this repository and no recorded line. `tools/gen_voice.py` builds a
**formant voice** out of the standard library, the way `tools/gen_flicker_audio.py` builds the
flicker family:

- **A mouth.** Every letter is a target for three resonators. Vowels carry the syllable
  (`a` = 700 / 1200 / 2500 Hz), voiced consonants are short and low, and unvoiced ones are noise
  with a shape - `s` hissing high and wide, `t` and `k` a click after a beat of closed mouth. The
  resonator centres walk between one letter's targets and the next over 30 ms, which is the part
  that makes it read as a mouth rather than a synthesiser.
- **A voice box.** A Rosenberg-ish glottal pulse train with vibrato and per-cycle jitter, falling
  across each sentence the way a person's pitch falls, rising again on a question, lifted slightly
  on the first vowel of each word.
- **A radio.** 8 kHz sample rate - the voice band is 300-3000 Hz, so a channel that sounds like a
  channel is genuinely this narrow. Band-limited, clipped through the transmitter, hissed, dropped
  out at random, and topped and tailed with squelch: relay click, breath of noise, silence.

You do not make out the words, and you are not meant to - the console prints them while it talks.
What you make out is that somebody is reading a report at you, and on nights 4 and 6, that
somebody is wrong. Three speakers come out of the same synth on different settings (`VOICES`):

| Voice | Who | How |
|---|---|---|
| `earth` | Gateway Control | 112 Hz, compressed, narrow, with a 19 ms slap for the distance |
| `self` | you, reading your own report back | 132 Hz, closer, cleaner, barely any dropout |
| `other` | whatever keys the mic at night | 86 Hz, a third slower, heavily overdriven, pitch wobble |

## Where the console is

One per deck, in the **COMMS ROOM** - every deck plan has one (`StationLayout.REQUIRED`). The room
was built round it (`kit/room_comms.glb`, from `tools/build_extra_rooms.py`): the console hangs in
an uplink bay on the back wall, straight ahead as you come through the door, between two operator
desks with their radio stacks, copper waveguides running up either side of it into the ceiling
toward the dish, a wall of transceiver racks on one side and the orbit plot on the other. The
room's two maintenance terminals (realign the antenna array, retune the uplink filter) are on the
door wall. The name plate outside its door is the room the notice names.

A plan without a comms room (a hand-built one, or an old seed from before it was required) falls
back to the old rule in `Station._place_comms`: the control room, otherwise the server room, the
observation deck or the laboratory, on a wall bay that room's own tasks are not using.

It is a `CommsStation` (an `Interactable`, so the existing point-and-hold works on it unchanged),
but it is deliberately kept out of the station's task list: nothing about it is switched on and off
with the shift or the lights, which is why it is still lit when the power is not.
