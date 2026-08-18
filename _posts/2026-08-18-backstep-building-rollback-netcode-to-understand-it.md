---
layout: post
title: "Backstep: Building Rollback Netcode to Understand It"
description: A lab note about implementing rollback netcode in Rust, driving a 1998 Neo Geo arcade game with it, and measuring what it costs across three continents.
date: '2026-08-18 23:30:00 +0200'
category: [Engineering]
image: /assets/img/posts/backstep/rollback-last.png
alt: The Last Blade 2 on a CRT beside a monitor showing live session telemetry, with an arcade stick and a notebook of diagrams on the desk.
tags: [rollback-netcode, netcode, rust, emulation, libretro, aws, elasticsearch]
---

Some topics only really click for me when I build a small version of them and watch where they break. That happened again here, except the small version stopped being small somewhere around the third continent.

I wanted to understand rollback netcode. Not the elevator pitch, which I already knew and which every fighting-game video will give you in thirty seconds: *the game guesses what your opponent pressed, keeps running, and rewinds to fix it when the real input arrives*. That sentence is true and it explains nothing. How often is the guess right? How deep does the rewind go? What actually happens when your opponent is on another continent instead of in the next city?

Those are questions with numbers attached, and the only way I could think of to get the numbers was to build the thing and measure it.

Before the lab, some references. These are much better introductions to the concept than anything I would write, and a couple of them are what got me interested in the first place:

- [Analysis: Why Rollback Netcode Is Better](https://youtu.be/0NLe4IpdS1w) - Core-A Gaming, the video most people start with
- [Rollback Netcode Explained in 3 Minutes](https://youtu.be/7yVrUcav6DI)
- [Rollback Netcode: Quick Basic Concepts for Beginners](https://youtu.be/883pxh7UMK0)
- [Talking Rollback Netcode With Adam "Keits" Heart](https://youtu.be/1RI5scXYhK0) - a developer's perspective, longer and worth it
- [Como funciona o ROLLBACK NETCODE?! O Netcode presente em Guilty Gear Strive](https://youtu.be/gcFfQd859Cg) - in Portuguese
- [O QUE É ROLLBACK NETCODE? (react a @AstroJogos) Tecnologia e Classe](https://youtu.be/_1mQfOO9B48) - also in Portuguese

The project is here:

[https://github.com/clivoa/backstep](https://github.com/clivoa/backstep)

The name is a fighting-game move. A backstep is what you do to undo a commitment you have already made. So is a rollback.

---

## A Note About Street Fighter Alpha 3

The original plan was Street Fighter Alpha 3. I love that game, it has one of the more interesting rollback stories in the community because of Fightcade, and it felt like the obvious subject.

It did not happen.

FBNeo supports SFA3 and the driver lists 21 files. Twenty of them matched the romset I had. The twenty-first was `sfa3.key`, the 20-byte CPS-2 decryption key, and it was missing. That is not a "find another revision" problem: in `src/burn/drv/capcom/d_cps2.cpp` the entry is

```c
{ "sfa3.key", 0x000014, 0x54fa39c6, CPS2_ENCRYPTION_KEY }
```

and it does not carry the `BRF_OPT` flag, which is what marks a file optional. FBNeo counts every non-optional entry as required and refuses to initialise the driver without it. All eleven SFA3 variants in FBNeo need a key file, including the supposedly pre-decrypted one, which asks for `phoenix.key` instead. Injecting a dummy does not work either, because validation is by CRC.

The symptom, before I understood any of that, was `retro_serialize_size()` returning zero. No error, no message, just a zero-byte savestate for a machine that had apparently loaded fine.

So the measurements are of **The Last Blade 2**, a 1998 Neo Geo fighting game, which runs on the same emulator core through the same interface under the same engine. Nothing being demonstrated changed. I just did not get to use the game I wanted.

I mention this because it is the kind of thing that gets quietly edited out of write-ups, and it was two days of work.

---

## What I Wanted To Build

A small but complete loop:

- a rollback engine that knows nothing about any specific game;
- a tiny 2D arena where I can audit every byte of state, to prove the engine works;
- a real arcade emulator driven by **the same engine**, to prove the abstraction is not a lie;
- two peers exchanging only inputs, over a real network, authenticated;
- enough telemetry that every claim in this post has a number behind it;
- infrastructure I can destroy completely when I am done.

That last point mattered more than I expected, and I will come back to it.

---

## Starting From Zero: The Frame

Everything in this post is measured in **frames**, so it is worth being precise about what one is.

A fighting game advances in fixed steps. Sixty times a second, it reads what the players are holding, computes the next state of the world from the current one, and draws the result. One of those steps is a frame, and at 60 Hz you get **16.7 milliseconds** to finish all of it: read the pad, send it over the network, simulate, draw. Miss the budget and the game visibly stutters.

The frame is also the unit of everything else. Inputs are stamped with the frame they belong to. Saved states are stamped with a frame. Checksums are compared per frame. When I write "depth 8" later, I mean eight of these steps.

The simulation itself is a pure function, at least in principle:

```text
next_state = simulate(current_state, [p1_input, p2_input])
```

Give it the same state and the same two inputs and it must produce the same next state. Always, on any machine. Hold on to that sentence, because most of the difficulty in this project comes from it.

An input, incidentally, is tiny. In this lab it is a single `u16`: sixteen bits, one per button. That is what crosses the network. Not positions, not health, not animation frames.

---

## The Problem A Network Creates

Both players need **both** inputs to simulate a frame. Yours is available immediately. Your opponent's has to travel.

At 50 ms round trip, their input for frame 100 physically cannot reach you until roughly frame 103. At 267 ms, not until frame 116. So at the moment you must simulate frame 100, you are missing half of what you need.

There are three ways out, and they are all trades:

| Family | How it handles delay | What it costs you |
| ------------- | ------------------------------------------------- | --------------------------------------- |
| Lockstep | waits for the opponent's input before simulating | the game hitches whenever the network does |
| Delay-based | adds fixed delay to your own input to hide the gap | your own commands always respond late |
| Rollback | guesses the opponent's input, corrects afterwards | extra CPU, and occasional visible corrections |

**Lockstep** is the honest one: do not simulate until you have everything. The whole game freezes for as long as the network is late, which is why old online fighting games stuttered constantly.

**Delay-based** hides the gap by making *your* input late too. If your button press only takes effect three frames from now, there are three frames of grace for the opponent's input to arrive. Nothing ever stutters, but everything you do responds late, permanently, whether the network is having a bad moment or not.

**Rollback** refuses both. Your input applies immediately, and the opponent's is *guessed*.

---

## What Rollback Actually Does

The guess is embarrassingly simple: **assume they are still holding whatever they were holding last.**

That works because fighting-game inputs are *held*, not tapped. You walk forward holding a direction. You crouch-block for the better part of a second. You hold back while deciding what to do. Across every experiment in this project, that guess was right about **93%** of the time.

The other 7% is where the interesting machinery lives. Here is a real correction, laid out frame by frame. P1 is guessing about P2:

```text
frame 100   P2's input hasn't arrived. Guess "still holding back".
            Save a snapshot of the whole game, then simulate. Draw it.
frame 101   Same. Guess, snapshot, simulate, draw.
frame 102   Same.
frame 103   Same. We are now 4 frames ahead of what we can prove.

            <- P2's real inputs for frames 100..103 arrive here

            Compare what we guessed against what actually happened:
              frame 100: guessed "back", they held "back"     -> fine
              frame 101: guessed "back", they pressed PUNCH   -> WRONG

            ROLLBACK, depth 3:
              load the snapshot saved at frame 101
              re-simulate 101 with the real input
              re-simulate 102 with the real input
              re-simulate 103 with the real input
              (video and audio discarded for all three)

            We are back at frame 103, now with a corrected world.

frame 104   Carry on normally. Draw it.
```

Two things about that are worth stopping on.

**All of it happens inside one display frame.** The rollback and the three re-simulations are not spread over the following frames; they happen in the 16.7 ms budget of frame 104. This is why there is a limit on how far ahead the game will guess: eight re-simulations plus a normal frame still has to fit.

**The player sees frames 101, 102 and 103 exactly once**, in their corrected form or not at all. The re-simulated versions are computed and thrown away. If they were drawn, you would see the picture jump backwards and hear a burst of audio.

And that is the whole trick. Your inputs never wait. Your opponent's punch appears a few frames after they threw it, in a version of the world that has been quietly rebuilt to include it.

---

## The Vocabulary, In One Place

These terms appear constantly from here on, so here they are together:

**Confirmed frame** - a frame where *both* players' real inputs have arrived. It is settled history and cannot change. Everything after it is speculation.

**Prediction depth** - how many frames you have simulated past the last confirmed one. In the example above, depth reached 4. This is the single most important number in the project: it governs how deep a correction can be, how much CPU one costs, and whether the game has to stop.

**Prediction limit** - how far the game is *willing* to guess before it gives up. Here: **8 frames**, which is 133 ms. It exists because re-simulation costs CPU and because you must keep a snapshot for every frame you might roll back to.

**Stall** - what happens when prediction depth hits the limit. The simulation simply stops and waits for the opponent. The player sees a brief freeze. An occasional stall is the limit doing its job; continuous stalls mean the link is worse than the configuration was built for.

**Rollback depth** - how many frames one correction had to re-simulate. Depth 1 is invisible. Depth 8 during a trade is not.

**Re-simulation ratio** - frames the CPU ran that nobody ever saw, as a multiple of the frames that were displayed. A ratio of 1.0 means the machine simulated every frame *twice*: once speculatively, once again to fix it. This is rollback's real cost, and it does not show up as lag, it shows up as heat.

**Desync** - the two machines stopped agreeing about the state of the game. From that moment the two players are watching different matches and nothing that follows means anything. Rollback does not tolerate desync better than any other netcode. It *depends* on re-simulation reproducing exactly what would have happened.

**Snapshot (savestate)** - a copy of the entire simulation state, so it can be returned to. In the toy arena that is 204 bytes. In the arcade emulator it is 415,155 bytes, and it has to be taken **every single frame**, because any frame might be the one you need to go back to.

---

## Why UDP And Not TCP

A small aside that took me a while to properly appreciate.

TCP guarantees delivery and ordering, and it achieves that by **waiting**. Lose one packet and everything behind it sits in a buffer until the retransmission arrives, a behaviour called head-of-line blocking. For a 60 Hz game that is precisely the wrong trade: a late input is worthless, because the frame it belonged to has already been simulated and corrected.

UDP just sends datagrams and makes no promises. Some arrive, some do not, some arrive out of order. The protocol here handles that by **repeating the last eight inputs in every datagram**. A lost packet's contents arrive again 16.7 ms later in the next one, and by then nothing has been waiting on it.

The measured cost of that redundancy is about 35 kbit/s. Which is nothing, and buys immunity to exactly the failure mode TCP handles worst.

---

## The Requirement Underneath Everything

One assumption holds the entire structure up, and it is easy to say and hard to keep: **both machines must simulate identically, forever.**

Not approximately. Not "close enough that nobody notices". Bit for bit, for every frame, on different CPUs and different operating systems, indefinitely.

Think about what re-simulation demands. When P1 rolls back to frame 101 and replays it, the result must be *identical* to what P2 computed for frame 101 on the other side of the world. If it differs by one pixel of position, the two games drift apart and nothing after that is a shared match.

This is why "make it deterministic" turns out to be most of the work, and it is where the second half of this post spends its time.

---

## The Shape Of It

```text
Madrid (my desk)                                AWS (three regions)
+-------------------------+                     +-------------------------+
| rollback-client (SDL2)  |                     | rollback-bot (headless) |
|   human on P1           |                     |   scripted state machine on P2    |
+-----------+-------------+                     +------------+------------+
            |                                                |
   +--------v---------+                              +-------v----------+
   | RollbackSession  |  <== UDP/7000, HMAC-SHA256 ==>| RollbackSession  |
   |  predict         |         INPUTS ONLY           |  the same code   |
   |  save state      |                               |                  |
   |  re-simulate     |                               |                  |
   +--------+---------+                              +-------+----------+
            |                                                |
   +--------v---------+                              +-------v----------+
   | Simulation:      |                              | Simulation:      |
   |  arena, or FBNeo |                              |  identical build |
   +------------------+                              +------------------+
```

Two things in that picture do the heavy lifting.

**`RollbackSession` is the same code on both sides.** There is no server. Both peers are equal and both simulate the entire game.

**Only inputs cross the wire.** No positions, no health, no sprites. Everything you see is recomputed locally from the same inputs. That is the whole reason the two machines must agree bit for bit.

---

## The Boundary That Makes It Work

The engine talks to the game through exactly four methods:

```rust
pub trait Simulation {
    fn save_state(&self) -> Vec<u8>;
    fn load_state(&mut self, data: &[u8]) -> Result<(), SimulationError>;
    fn advance_frame(&mut self, inputs: [PlayerInput; 2], output_mode: OutputMode);
    fn checksum(&self) -> u64;
}
```

That is the entire surface. And it is the project's actual argument, because two very different things implement it:

| | Arena | The Last Blade 2 |
| ----------------- | ----------------- | -------------------------- |
| What it is | ~500 lines I wrote | a 1998 arcade board, emulated |
| Snapshot size | **204 bytes** | **415,155 bytes** |
| Can I read it? | every byte | not one |

The same `RollbackSession` drives both. If the engine needed to know where the players were or how much health they had, it could not drive an emulator whose state is an opaque blob. It does not, so it can.

`OutputMode` is the one subtlety. Each frame is either `Present` (the player will see it) or `Resimulate` (this is a correction replay, throw the video and audio away). The contract is strict: **it may change output, never state.** A depth-8 rollback runs eight `advance_frame` calls inside one display frame; without discarding, you would see eight frames flash past and hear a burst of audio. But if it changed *state*, the peers would diverge outright, because they re-simulate different frames at different times.

Three tests hold that line, one per layer. It is the kind of invariant that is obvious once written down and very easy to break by accident.

### The Bot Is A Player, Not Part Of The Game

One design decision here took me a while to see the importance of.

Most sessions in this project are bot against bot, so there is a small state machine choosing what P2 does. The tempting place to put that is inside the simulation, where it has access to everything. That would be a mistake.

The bot produces one `PlayerInput` per frame and hands it to the session exactly as a controller would, and that input travels the wire like any other. It is a **player**, sitting outside the simulation and pressing buttons at it.

The reason is determinism again. If the bot lived inside the simulation, both machines would have to run it identically, and its random number generator would become one more way to desync. Because it is a player, its randomness is *irrelevant* to synchronisation: whatever it decides gets transmitted, and both sides use the transmitted value. It only has to be reproducible from a seed so that a benchmark is an experiment rather than an anecdote.

There is a second restriction that matters for honesty about what was measured. The scripted bot **reads nothing from the game**. It cannot, without ROM memory offsets, which this lab deliberately refuses: those are per-game, per-revision, and would make the bot a memory-reading cheat rather than a player. It plays a fixed list of moves on a timer, chain combos and quarter-circles and guards and parries, and it knows which way it is facing. That is all.

So it is not a good opponent. It is a *reproducible* one, which is what an experiment needs.

---

## How A 1998 Arcade Board Ends Up In A Rust Program

This part took me longer to internalise than the netcode did.

The Last Blade 2 was written for a **Neo Geo MVS**: a Motorola 68000 at 12 MHz for game logic, a Z80 for sound, a custom video chip, a YM2610 for audio. The game is machine code for a processor my laptop does not have, talking to chips my laptop does not have.

An emulator is a program that pretends to be that hardware. In ordinary memory it keeps a variable for the 68000's program counter, sixteen more for its registers, an array standing in for work RAM, another for video RAM, counters for the sound chip. Then it loops:

```text
forever:
    instruction = rom[program_counter]     # fetch
    decode it                              # what does 0x4E71 mean?
    apply it to those variables            # execute
    advance program_counter
```

The game writes a sprite's coordinates to an address; the emulator notices the address belongs to the video chip and updates its own sprite table. The game cannot tell the difference. There is no hardware behind those addresses any more, only arrays and a switch statement.

Timing matters more than you would expect. The Neo Geo's two processors run *simultaneously* and pass messages through shared addresses. Run a thousand 68000 instructions before letting the Z80 catch up and the sound desynchronises from the action. Worse, the original programmers counted machine cycles and relied on real timings, so an emulator that is fast in the wrong place breaks code that was correct on hardware. FBNeo interleaves the chips cycle by cycle, which is most of why emulation is expensive.

### The Plug The Emulator Fits Into

I could have embedded FBNeo directly, but then every emulator would need its own integration. There is a standard for this, and it is what makes the whole project tractable.

**libretro** is a small C interface that splits an emulator in two:

- a **core** implements the machine: FBNeo, and hundreds of others for other systems;
- a **frontend** supplies the window, the gamepad, the audio device, and the loop that drives it.

RetroArch is the frontend most people have seen. The contract between them is about a dozen functions: the frontend calls `retro_run()` once, the core simulates exactly one frame and calls back with the video and audio it produced.

This lab is a frontend. An unusual one, because instead of drawing every frame it sometimes runs several and throws them away, but a frontend nonetheless. It loads the core with `dlopen` at runtime and calls into it through that C interface.

That is why the same rollback engine can drive an arcade emulator and a 204-byte toy arena without knowing which is which: both end up behind the same four methods.

And the reason all of this matters to rollback:

```c
size_t retro_serialize_size(void);
bool   retro_serialize(void *data, size_t size);
bool   retro_unserialize(const void *data, size_t size);
```

Because the machine "is" those arrays, you can copy them. That copy is a savestate, and those three functions are `save_state` and `load_state` in the trait above. **The engine rewinds a game it cannot read.** It has no idea where the fighters are or whether a projectile is in flight. It copies 415,155 opaque bytes, and that is enough.

There is one more piece people forget: a Neo Geo cartridge is not a whole program. The board carries a **BIOS** that boots the machine, draws the SNK logo, and handles coins. The game calls into it constantly. That is why the lab needs `neogeo.zip` alongside the game, and why both are hashed into the handshake. Half the code that runs is code the game did not ship with.

---

## Determinism Is A Property You Maintain

This is the part where the lab stopped being theoretical.

FBNeo, as shipped, does two things that make it non-deterministic across machines:

- it seeds its random number generator from `time(NULL)`;
- it feeds the host's calendar into the Neo Geo's real-time clock chip, which the BIOS reads at boot.

Two peers starting in different wall-clock *seconds* therefore begin with different state, and diverge before the first input is pressed. FBNeo already carries the fix, because Fightcade needs it too: a `kNetGame` flag. The build patches it on and records the patch in the artefact's provenance.

I did not take this on faith. There is a check that runs the core in two separate processes, deliberately in different wall-clock seconds, and compares checksums:

```bash
just check-determinism /path/lastbld2.zip
```

Unpatched, the two processes disagree. Patched, they agree for the whole run.

The broader lesson generalises well past emulation: **any clock, any address, any hash seed, any thread scheduling decision that leaks into the simulation will eventually desync two machines running identical code.**

The arena is my own code, so it is where the rules had to be applied deliberately. Four of them, and each is worth explaining because none is obvious until it bites:

**No floating point.** `0.1 + 0.2` does not produce the same bits everywhere. Compilers are allowed to contract a multiply-and-add into a single fused instruction on one machine and not another, x87 registers historically carried extra precision, and transcendental functions like `sin` are not specified to the last bit. The differences are microscopic, but rollback amplifies them: a position that differs in the last bit becomes a hit that lands on one machine and misses on the other. So the arena uses **fixed point**, integers with an implied decimal place. Q23.8 here, meaning the low 8 bits are the fraction. Integer arithmetic is exactly specified, so two machines cannot disagree.

**No `HashMap` anywhere in the simulation.** Rust seeds its default hasher randomly *per process*, which is a good security decision and a fatal one here: iterating the same map produces a different order in each process. If anything in the simulation loop iterates a map and the order affects the result, the two peers diverge. `BTreeMap` is ordered by key, so iteration is identical everywhere.

**No `DefaultHasher` for checksums.** Same reason, one level up. Rust explicitly does not guarantee its default hasher is stable across versions or platforms, so a checksum built on it would report desyncs between two perfectly synchronised machines running different Rust releases. The lab uses a hand-rolled FNV-1a, which is forty lines and fully specified.

**Overflow checks stay on in release builds.** By default Rust wraps integer overflow silently in release and panics in debug. That means a bug could produce one result on a developer's debug build and another in production, which is exactly the class of difference that desyncs a session. Turning the checks on in release costs a little speed and converts a silent divergence into a loud crash.

None of that could be validated on one machine. Two processes of one binary on one CPU would have agreed even if every one of those decisions had been wrong, because they share a CPU, a libc, a compiler and a rounding mode. Which is why the lab eventually had to leave my desk.

---

## The Protocol

Deliberately small. UDP on port 7000, a versioned binary format, 1,200 bytes maximum so nothing fragments, and HMAC-SHA256 on every datagram with an ephemeral per-session key.

Six message types: `Hello`, `HelloAck`, `InputBatch`, `Checksum`, `TelemetrySummary`, `Disconnect`.

Two design choices are worth pulling out.

**Every `InputBatch` repeats the last eight inputs.** There is no retransmission and no acknowledgement of individual inputs. A lost datagram is simply covered by the next one, which arrives 16.7 ms later and carries the same data again. Bandwidth is about 35 kbit/s, so redundancy is far cheaper than a retransmit round trip.

**The handshake refuses anything that could desync.** It compares protocol version, app commit, simulation, seed, input delay, prediction limit, state history, and SHA-256 hashes of both the emulator core and the ROM set. Any mismatch is a refused session rather than a slow-motion divergence.

That check is stricter than it sounds, and it bit me later in a way I will get to.

Authentication is HMAC-SHA256 with a key generated fresh for each session. Every datagram carries a 32-byte tag computed over its contents with that key, and a datagram whose tag does not verify is dropped without being parsed at all. This is not about privacy, since the payload is a handful of button states nobody would want. It is about **not letting a stranger inject inputs into my match**, which on a plain UDP port would otherwise be trivial: the port is open, the format is documented in the repository, and forging a datagram would take about ten lines.

### Noticing When It Has Already Gone Wrong

Everything so far assumes the two machines stay in agreement. Something has to check.

Every 60 confirmed frames, each peer computes a **checksum** of its entire simulation state, a 64-bit FNV-1a over the snapshot, and sends it to the other. The other compares it against its own for that frame. Agreement means the two machines are still running the same match. Disagreement means a desync, and the session ends immediately rather than letting two people play out a fight they are no longer both watching.

Two details in there turned out to matter.

**Only confirmed frames are compared.** A speculative frame is about to be rewritten by a rollback, so comparing it would report a desync that does not exist. And because the two peers run independent frame clocks, a checksum often arrives *before* the local side has confirmed that frame. Those get parked and compared later. My first implementation discarded them instead, which quietly made detection one-directional: one peer compared ten checksums and the other compared zero, and the tests were perfectly happy.

**The emulator needed an exclusion.** On The Last Blade 2 the checksum ignores the first 2,048 bytes of the savestate, because FBNeo *recomputes* rather than restores about twenty bytes of sound and timer bookkeeping. Those bytes differ after a rollback even when the game state is identical, and without the exclusion the detector reported a desync on the first correction of every session. Finding that took a while, mostly because "the desync detector is wrong" is the last hypothesis you reach for.

The final tally across everything in this project: **2,997 checksum comparisons, zero disagreements.**

---

## Watching It Work

The first real result was on loopback with synthetic impairment: two processes on one machine, with delay and jitter and loss injected into each side's outgoing datagrams.

![The Last Blade 2 under rollback with 20 ms of injected one-way delay, telemetry burned into the frame](/assets/img/posts/backstep/rollback-delay20.gif)

The band across the top is the session's own telemetry, burned in from its log: 142 rollbacks so far, 18.5% of a frame's work being re-simulated, and `ROLLBACK -5` firing on the exact frame it happened.

Look at the game underneath. It does not stutter. That is the entire point of rollback and also what makes it so hard to reason about: **when it is working, there is nothing to see.** The overlay exists because I could not otherwise tell a session doing a thousand corrections from one doing none.

Five synthetic profiles, 180 seconds each, fixed seed:

| Profile | Delay | Jitter | Loss | Measured RTT |
| ------------ | ------ | ------ | ---- | ------------ |
| `natural` | - | - | - | 16.6 ms |
| `delay20` | 20 ms | - | - | 70 ms |
| `jitter30` | 30 ms | ±15 ms | - | 84-88 ms |
| `loss2` | - | - | 2% | 27 ms |
| `combined` | 40 ms | ±20 ms | 2% | 97-105 ms |

Three words in that table are worth defining, because the rest of the post leans on them.

**Latency** is how long a datagram takes to get there. **RTT** (round-trip time) is there and back, and it is what you can actually measure without synchronised clocks: you note when you sent something and when the reply came back. One-way latency is roughly half of it, and I say "roughly" because the internet is not symmetric. This project never reports one-way latency as a measurement, only as an estimate, for that reason.

**Jitter** is the *variation* in latency, and for rollback it matters more than latency itself. A steady 100 ms link is a configuration problem: you know how far ahead to guess, you set it once, done. A link that swings between 40 ms and 160 ms is a much harder problem, because the amount of speculation you need changes constantly and you have to size for the worst case. This is the difference between "far away" and "unstable", and they are not the same thing at all.

**Loss** is datagrams that never arrive. Here it is inferred from gaps in the sequence numbers, which means a merely *late* datagram counts as lost until it shows up.

One detail about how the impairment is applied: each peer adds delay to its own **outgoing** datagrams. So a profile configured with 20 ms of one-way delay produces roughly 40 ms of extra round trip, plus whatever the real link contributes. That is why `delay20` measures 70 ms rather than 20.

The first useful surprise came from comparing `loss2` against `delay20`. Two percent packet loss produced **19 rollbacks** in four minutes. Twenty milliseconds of delay produced **1,006**.

Rollback is almost completely insensitive to loss and extremely sensitive to latency. The eight-input redundancy means a lost datagram's contents arrive again 16.7 ms later, well before they are needed. Delay cannot be covered that way, because the information genuinely is not there yet. Losing a packet costs you nothing if the same data is already on its way again; waiting for information that has not been transmitted yet costs you a correction.

---

## Leaving The Desk

Loopback proves the engine works. It cannot prove determinism across machines, which was the project's biggest open gap, so the next step was AWS: a `t3.small` in Frankfurt running the same headless peer, and my desktop in Madrid on the other end.

The infrastructure is one Terraform stack, and the design constraint was that the entire attack surface should be **one UDP port from one IP address**:

```text
VPC 10.42.0.0/16
 +- public subnet
     +- EC2 t3.small, Ubuntu 24.04
         +- security group    UDP/7000, from one /32, nothing else
         +- IMDSv2 required
         +- shutdown -h +4h, with terminate-on-shutdown
S3 bucket        private, encrypted, 7-day lifecycle
SSM SecureString /rollback-netcode/session-key
```

No SSH. No key pair, no port 22, no bastion. Administration goes through SSM Session Manager, whose agent dials out and needs no inbound rule at all. A lab that opens 22 "just for debugging" is a lab with a permanent hole in it.

Terraform refuses `0.0.0.0/0` outright:

```hcl
validation {
  condition     = var.allowed_cidr != "0.0.0.0/0"
  error_message = "Refusing to open the game port to the whole internet."
}
```

The session key never enters Terraform state, never becomes a command-line argument (arguments are visible in `ps` to every user on the box), and never goes into a systemd `Environment=` (readable through `systemctl show`). It lives in SSM as a SecureString, is fetched in the service's `ExecStartPre`, and the local copy is deleted at teardown.

**Five things only a real `apply` found.** Terraform passed `validate`, the scripts passed `shellcheck`, and the first session still took five attempts:

1. An apostrophe in a security group description. The AWS API permits a fixed character set; `terraform validate` is perfectly happy with it.
2. SSM runs `/bin/sh`, which on Ubuntu is dash. `set -euo pipefail` and `source` both died.
3. Ubuntu 24.04 dropped the `awscli` package. Under `set -e` that killed `user_data` on its first command and left an instance that **boots, answers SSM, and has nothing installed**.
4. SSM reporting `Online` does not mean cloud-init finished. Waiting for the ping and then sending commands races the bootstrap.
5. `printf %s` does not interpret `\n`, so a script generated three quoting layers deep landed on a single line. `systemctl is-active` reported **active** the whole time while `env` tried to execute a program whose name contained newlines.

Four of those five failed *silently or with apparent success*. The bring-up script now waits for a marker file the bootstrap writes when it genuinely finishes, and verifies with `ss -lun | grep :7000` that the peer is actually listening.

---

## Madrid To Frankfurt

50 ms round trip, over the public internet, no synthetic impairment.

![Both peers side by side on the real Madrid to Frankfurt link](/assets/img/posts/backstep/rollback-real-link.gif)

| Metric | P1 (Madrid) | P2 (Frankfurt) |
| ------------------- | ----------- | -------------- |
| Effective FPS | 60.01 | 60.01 |
| Rollbacks | 1,280 | 31 |
| Max rollback depth | 4 | 2 |
| Prediction accuracy | 92.9% | 92.4% |
| Stalls | 0 | 0 |
| Checksums compared | 300 | 300 |
| Desyncs | **0** | **0** |
| Loss | 0.000% | 0.000% |

449 checksum comparisons agreeing across an i7-10750H running Arch and an EC2 instance running Ubuntu, with different CPUs, different operating systems and different libcs. That is the result the whole determinism discipline exists for, and one machine could never have produced it.

Two things I did not expect.

**The synthetic profiles were pessimistic in every dimension.** The real link had 0.37 ms of RTT variation and lost **zero** of 18,602 datagrams. `jitter30` describes bad Wi-Fi, not a route between European datacentres. Erring pessimistic is the right direction, but it is worth knowing which direction you erred.

**Real rollback depth was far shallower than simulated depth** at comparable latency: mean depth fell from 6.53 to 2.04. Part of the reason is that on loopback the two peers *share one CPU*, and scheduling contention adds phase drift that does not exist when each peer has its own machine. Some of what my bench measured was the bench, not the rollback.

Full session on YouTube: [Madrid to Frankfurt, both peers side by side](https://youtu.be/kEijE-A6mHY).

---

## Then I Went Further Away

Frankfurt answers "does this work over the internet". It cannot answer "what happens when your opponent is far away", because 50 ms is close. So the same two simulations ran again against **São Paulo** and **Tokyo**.

<iframe width="100%" height="400" src="https://www.youtube.com/embed/oE1ovIjDDGE" title="Madrid to Tokyo under rollback, both peers" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

Both measured **267 ms**. Madrid to São Paulo is 8,500 km westward, Madrid to Tokyo is 9,700 km eastward, and they came out within a millisecond of each other, which turned the second region into an independent repeat of the first rather than a new data point.

| From Madrid to | SRTT | Max depth | Stalls | FPS |
| -------------- | ------ | -------------- | ------ | ----- |
| Frankfurt | 50 ms | 3 | 0 | 60.01 |
| São Paulo | 272 ms | **8** (the limit) | 827 | 57.37 |
| Tokyo | 267 ms | **8** (the limit) | 1,283 | 56.01 |

![Kibana dashboard: round-trip time against stalls, and max rollback depth against the limit](/assets/img/posts/backstep/dash-2-distance.png)

The scatter on the left is two clusters and nothing in between. That is not a coincidence, it is arithmetic:

```text
prediction_limit = 8 frames
8 frames at 60 Hz = 133 ms
Madrid to Tokyo one way = 133 ms
```

**The prediction window and the link are exactly the same size.** An input cannot possibly arrive before the window that needs it has already filled, so the session hits the limit on essentially every frame, refuses to speculate further, and waits. Frankfurt has almost six times the headroom and never waits at all.

This is the design working correctly. The session would rather freeze briefly than speculate past what it can undo. But it does mean the default configuration is tuned for a continent, not a planet.

Here is a single frame from the Tokyo run:

![A frame from the Tokyo session: the fight looks normal while the telemetry counts 423 rollbacks and 360 stalls](/assets/img/posts/backstep/tokyo-telemetry.png)

Frame 7199. 423 rollbacks. Depth 5 right now, 8 at its worst. 39.8% of the machine's work being re-simulated and thrown away. 360 stalls. And the fight underneath looks completely ordinary.

---

## Three Findings I Did Not Expect

### The heavier game degrades first

Same link, same distance, two simulations:

| | Arena (204 B) | The Last Blade 2 (415 KB) |
| ----------------- | ------------- | ------------------------- |
| FPS at Tokyo | 59.56 | 56.01 |
| Stalls, Tokyo P1 | 68 | 1,283 |

The network is identical. What differs is that recovering from a stall means re-simulating up to eight frames, and eight frames of an emulator with a 415 KB state costs what eight frames of a 204-byte arena does not.

Latency and state size **compound**. Each is survivable alone. Together they were the only configuration in the whole project that missed 60 Hz.

### The asymmetry between peers, and where it goes

Rollback counts are routinely lopsided. On one Frankfurt run Madrid paid 1,280 rollbacks against Frankfurt's 31. Fifteen minutes later, on the arena over the same route, **Frankfurt paid 601 against Madrid's 19**.

Nothing about the network changed. What changed was who completed the handshake first.

The host finishes the handshake as soon as it receives the client's hello; the client finishes one one-way delay later, when the reply arrives. So their frame clocks start at slightly different moments, and **whoever is ahead is the one doing all the speculating**. Their opponent's inputs are still in flight when they simulate. The peer behind receives inputs that are already due and barely predicts at all.

Which means "how many rollbacks does my client do" measures **starting phase, not connection quality**.

And then it disappears. At 267 ms the two peers landed within 4% of each other. The asymmetry needs slack in the window to exist; once both peers saturate, both stall, and stalling is what re-couples their clocks. The mechanism that limits the damage also distributes it.

### Prediction accuracy does not care about any of this

92.2% to 95.5%. Across 50 ms and 267 ms, two simulations, three continents, loopback and real internet.

The one number that stayed flat through every experiment is the one rollback's entire premise rests on. Distance changes how *often* you must correct and how *deep* the correction goes. It does not change how often the guess was right, because the guess depends on the player's hands, not on the network.

The prediction rule, by the way, is this whole thing:

```rust
fn predict_remote(&self) -> PlayerInput {
    self.remote_inputs
        .get(&self.remote_confirmed_through)
        .copied()
        .unwrap_or(PlayerInput::NEUTRAL)
}
```

Repeat the last confirmed input. That is it. Right about 93% of the time.

---

## So How Do You Fix A Link That Is Too Long?

The three-region runs proved the window saturates at 267 ms. They could not show how to fix it, because each configuration would have meant another instance-hour on another continent.

So I brought the measured link home. A network profile of 133 ms one-way with ±5 ms of jitter reproduces the real 267 ms round trip closely enough to stand in for it, and then the tuning question costs nothing but CPU.

There are only two knobs, and it is worth understanding what each one actually does before looking at the results.

**Raising the prediction limit** means allowing the game to guess further ahead before it gives up. If eight frames of speculation is not enough at this distance, allow twenty. The stalls disappear, because the window is now wider than the link is long. But every extra frame of speculation is an extra frame that might need re-simulating, and an extra snapshot that must be kept, so the CPU cost grows with the square of nothing in particular but grows steadily. Nobody's input lag changes.

**Raising the input delay** means something quite different, and it is the least intuitive idea in this whole post. You deliberately make *your own* button presses take effect later.

Say you set an input delay of 8. When you press punch on frame 100, the game files that input for frame **108** and does nothing visible for eight frames. That sounds strictly bad, and for the player it is: 8 frames at 60 Hz is 133 ms of lag between your hand and the screen.

What it buys is that your input is now on its way to the opponent **eight frames before anyone needs it**. Their machine receives it early, so it does not have to guess. Every frame of input delay is one less frame of prediction:

```text
input delay 1:   press on frame 100 -> applies on 101
                 opponent needs it by 101, it arrives around 108
                 -> 7 frames must be guessed

input delay 8:   press on frame 100 -> applies on 108
                 opponent needs it by 108, it arrives around 108
                 -> nothing must be guessed
```

So the two knobs solve the same problem by charging different people. One spends CPU to keep guessing further. The other spends the player's reaction time to stop guessing at all.

Four configurations, same link:

| Configuration | Input delay | Limit | FPS | Stalls | Re-simulation | Input lag |
| ------------------ | ----------- | ----- | ----- | ------ | ------------- | --------- |
| baseline | 1 | 8 | 56.94 | 269 | 0.56x | 17 ms |
| wide-window | 1 | 20 | 60.11 | 0 | **1.17x** | 17 ms |
| input-delay-8 | 8 | 8 | 59.94 | 3 | 0.50x | **133 ms** |
| both | 6 | 16 | 60.11 | 0 | 0.85x | 100 ms |

![Kibana dashboard: input lag against re-simulation, bubble size is stalls](/assets/img/posts/backstep/dash-4-tuning.png)

The horizontal axis is what the player feels. The vertical axis is what the CPU pays. Bottom-left is what everyone wants and nobody can have at this distance.

**Widening the prediction window removes every stall and appears free.** Input lag does not move. But depth rises from 8 to 18 and re-simulation reaches 1.17x, meaning the machine simulates more than twice the frames it displays. On a 204-byte arena that is affordable. On a 415 KB emulator state where `save_state` alone costs 2.27 ms of a 16.7 ms frame, it does not fit, which is exactly why the game fell to 56 fps at Tokyo while the arena held 59.5.

**Buying the same result with input delay charges the player instead.** Eight frames of delay also removes the stalls and halves the re-simulation. The price is 133 ms of input lag, which in a fighting game is roughly the difference between a move you can react to and one you cannot.

The trade is not between good and bad configurations. It is a choice of **who pays for the distance**: the CPU, through deeper speculation, or the player, through lag. The window sets the split, and there is no setting that makes 267 ms feel like 50 ms.

What tuning buys is a smooth 60 Hz with honest input lag instead of 56 Hz with unpredictable freezes. The second is worse to play even though its average latency is lower.

---

## The Bug The Cloud Could Not Find

The tuning sweep did not run the first time. Both peers connected, both filled the prediction window, both stalled, and both sat at `depth=8` forever.

The frame loop skipped `transport.pump()` on the stalled path, on the entirely reasonable-sounding logic that a stalled peer should "do no local work at all". But `pump` is what moves the network emulator's delay queue onto the socket. A datagram already handed to `send` is **in flight**, and a real network delivers it whether or not the sender does anything else. Modelling flight as a queue that only advances when the sender acts is fine right up until the sender stops, and the sender stops precisely when it is starving for what is in that queue.

Each peer was holding the other's inputs hostage.

It needs one-way delay to exceed the prediction window before it can bite, which is why no profile up to `combined` (40 ms against a 133 ms window) ever showed it. And the AWS runs could not have found it, because there the delay is the real network, which needs no pumping.

**A deliberately simplified model found a bug that the real thing structurally could not.** That is the best argument I have for keeping both.

The regression test deadlocks against the old code and passes against the new one. I checked that by reverting the fix and watching it fail, because a regression test that passes both ways proves nothing.

---

## Then A Person Played

Every session up to this point had been bot against bot. That left the question rollback exists to answer completely unmeasured, so eventually I sat down and played: 480 seconds of The Last Blade 2 on P1, against the scripted bot in Frankfurt, over the real internet.

<iframe width="100%" height="400" src="https://www.youtube.com/embed/4lm7mr2wblk" title="A human playing The Last Blade 2 on P1 against a bot in Frankfurt" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

![A frame from the played session: 172 rollbacks, 35.2 ms round trip](/assets/img/posts/backstep/human-telemetry.png)

It played fine. Which was the least interesting thing about it, because the numbers contradicted something I had written into my own documentation.

I had assumed bot-measured accuracy was a **floor**. Bots change input on a regular cadence; people hold directions much longer; therefore a human should be *easier* to predict.

![Kibana dashboard: prediction accuracy for the human session against the bot sessions](/assets/img/posts/backstep/dash-5-human.png)

| Predicting | Accuracy |
| ----------------------------- | -------- |
| **a human** | **89.9%** |
| the bot, same session | 93.7% |
| the bot, bot-vs-bot sessions | 91.5% - 92.4% |

Predicting me was *harder* than predicting the bot, and worse than every bot-versus-bot figure in the dataset. In hindsight it is obvious: the bot plays a fixed move list with held inputs by construction. I mashed, changed direction erratically, and left gaps.

One player, one session, video recording on. It is enough to retire the "floor" claim and not nearly enough to replace it with anything. But I liked that the lab was able to tell me I was wrong.

---

## Three Bugs That Only A Human Could Find

Getting that session to happen exposed three defects that had been invisible for the entire project, because every run until then was launched by a single script that got all three right by accident.

**The remote peer waited 120 seconds for a handshake, then exited.** That is right for an automated benchmark, where a script starts both peers seconds apart. It is wrong for a person, who has to read the output and sit down. The failure mode is nasty: the instance stays up, keeps billing, keeps answering SSM, and `systemctl is-active` reports `active` right up until it does not. From the client it looks like a handshake that hangs for no reason.

**`just play` passed none of the configuration the handshake checks.** The bring-up script defaults the seed to 4242; the client's built-in default is `0x123456789ABCDEF0`. They could never agree. So the documented path of `just aws-up` followed by `just play` **always failed**, and nobody had noticed because every previous session had both peers launched from the same script.

**A refused handshake killed the host.** Fix your flag, retry, find nothing listening.

Each one made the next harder to see. The fixes were a configurable handshake timeout, a `session.env` file that the bring-up writes and the play command reads so both sides agree by construction rather than by both hard-coding the same numbers, and a host that logs the refusal with both identities and **keeps listening**.

That last one changed a test, and I think the diff is a nice summary of what I learned:

```rust
// was: the host reports the rejection and exits
assert!(matches!(host_err, HandshakeError::Rejected(r) if r.contains("seed")));

// now: the host tells the client why, and stays up
assert!(
    matches!(host_err, HandshakeError::Timeout(_)),
    "a refused peer must not take the host down; got {host_err:?}"
);
```

---

## Where A Frame Actually Goes

Every claim above has a per-frame cost behind it. Measured on The Last Blade 2:

| | microseconds | share of a 16,667 us frame |
| ---------------- | ------------ | -------------------------- |
| `advance_frame` | 3,948 | 24% |
| `save_state` | 2,271 | 14% |
| `load_state` | 17 | 0.1% |

Emulating the machine costs a quarter of the budget. Snapshotting it costs another seventh, **every single frame**, because rollback needs a restore point for every frame it might have to return to.

Restoring is nearly free. That asymmetry is the reason rollback is affordable at all: you pay for the snapshot constantly and for the rewind rarely.

There is one optimisation in there worth mentioning because it is invisible until you need it. The engine calls `save_state()` and `checksum()` on the same frame, and a naive implementation costs two full `retro_serialize` calls. Caching the snapshot's checksum as it is taken halves the most expensive operation in the loop. At 60 Hz with 415 KB, that is the difference between fitting in the budget and not.

---

## Making It Queryable

`summary.csv` answers "what was the average depth". It cannot answer "show me every correction deeper than six frames and what the round trip was at that moment".

So every session writes JSONL with one document per event, and there is a loader that indexes it into Elasticsearch, six Kibana dashboards, and a set of ES|QL queries kept as plain text so they can be pasted straight into Discover.

The one that settles the headline result:

```sql
FROM rollback-metrics
| WHERE mode IN ("frankfurt", "saopaulo", "tokyo")
| EVAL one_way_ms = `derived.srtt_ms` / 2,
       window_ms = prediction_limit * 1000.0 / 60
| STATS one_way = ROUND(AVG(one_way_ms), 0),
        window = ROUND(AVG(window_ms), 0),
        depth = MAX(`local.max_rollback_depth`),
        stalls = MAX(`local.stalls`)
    BY mode
| EVAL fits_in_window = one_way < window
| SORT one_way
```

| one_way | window | depth | stalls | mode | fits_in_window |
| ------- | ------ | ----- | ------ | --------- | -------------- |
| 23 | 133 | 3 | 0 | frankfurt | true |
| 133 | 133 | 8 | 1283 | tokyo | false |
| 134 | 133 | 8 | 827 | saopaulo | false |

The entire multi-region experiment, in six rows.

Two things I learned building the dashboards, both of which cost me real time:

**A panel whose query returns nothing renders as an empty box**, and an empty box is indistinguishable from a genuine result of zero. So the build script executes every query first and refuses to publish a panel that would come back empty, with one deliberate exception: the desync panel, which is empty on purpose and is the most important panel in the set.

**Kibana only renders panels that have scrolled into view.** A screenshot of a tall dashboard captures its lower panels blank. I chased one "broken" chart for far too long before working that out.

---

## What It Cost

Six sessions across three AWS regions, plus the human one. Every session brings the infrastructure up, runs, collects, and destroys it.

Under **US$ 0.30** in total. A `t3.small` is about US$ 0.021 per hour and the sessions are minutes long; the elastic IP and the S3 bucket round to nothing at this scale.

The expensive failure mode is not the instance, it is the **forgotten** instance. There are two guards: `instance_initiated_shutdown_behavior = "terminate"` paired with a `shutdown -h +4h` armed at boot, so a forgotten instance terminates rather than accumulating as a stopped one with a volume still billing.

That guard earned itself. A run aborted mid-script and never reached teardown, leaving an instance up with its logs and a 171 MB recording still on it. The collection step now **verifies** that both peers' logs and both recordings arrived before it destroys anything, and refuses to tear down if something is missing, saying out loud that the instance is still costing money.

The reason that script aborted, incidentally, is that I edited it while it was running. Bash reads a script incrementally, so editing one mid-execution makes the shell resume at a byte offset that no longer means what it did. The fix was to wrap the whole body in a function called on the last line, because a function is parsed as a unit before any of it executes.

---

## What I Learned

**Rollback is sensitive to latency and almost immune to loss.** 2% loss produced 19 corrections where 20 ms of delay produced 1,006. Those are different problems and only one of them is rollback's.

**The prediction limit is a bet about how far away your opponent is.** Eight frames is 133 ms. That is a bet on a continent, and it stops paying at exactly the distance where one-way delay reaches it.

**"How many rollbacks does my client do" measures starting phase, not connection quality.** The same route produced 1,280-vs-31 in one direction and 601-vs-19 in the other, fifteen minutes apart.

**Determinism is maintained, not obtained.** A wall clock, a randomised hash seed, or a float is enough to lose it, and none of that shows up until you run on two different machines.

**A simplified model can find bugs reality cannot.** The stalled-path deadlock only existed because the emulator holds delayed datagrams in a local queue. A real network structurally could not have produced it, and it was a genuine bug.

**Automation hides whole classes of failure.** Three real defects survived the entire project because one script got them right by accident. The first human session found all three in twenty minutes.

**Measuring something changes it.** Recording video costs about 65% of a core, which slows the frame loop and widens the phase gap between peers. The recorded sessions stall more than the un-recorded ones on a *better* route. The videos in this post illustrate the behaviour faithfully; the numbers come from sessions with recording off.

---

## What I Did Not Measure

The honest list, because I think it matters more than the results.

**Perception.** The lab can tell me a correction was 8 frames deep. It cannot tell me whether that was noticeable, or whether I would have preferred 100 ms of input delay instead. That is the question rollback exists to answer and the one this project does not. Answering it needs several players and blind comparisons.

**Burst loss.** The protocol's defence against loss is repeating the last eight inputs, and a burst is exactly the worst case for a redundancy window: eight consecutive losses defeat it, eight scattered ones do not come close. Every real link I measured was too clean to test it. Intercontinental fibre turned out to be **slow but almost perfectly clean**, the opposite of what my synthetic profiles assumed.

**More than one sample.** Every number here is a single run. There are no confidence intervals anywhere in this project.

**NAT on both ends.** One end was always an EC2 instance with a public IP. Real peer-to-peer play has neither.

---

## The Dataset

Everything is published. All 24 session logs, 100 MB expanded and 5 MB compressed, live in the repository:

```bash
git clone https://github.com/clivoa/backstep
cd backstep
tar xf dataset/rollback-sessions.tar.zst -C artifacts/
just elastic-up && just elastic-load
./ops/scripts/elastic-dashboards.py
```

That rebuilds every dashboard and every query in this post without running a single session or spending anything on AWS.

The format is line-delimited JSON, so it needs no tooling at all:

```bash
# every correction deeper than six frames, and when it happened
jq -c 'select(.record=="session" and .event=="rolled_back" and .depth>6)' \
  artifacts/logs/*-tokyo.jsonl | head
```

Every log records the commit that produced it, the SHA-256 of the core and the ROM set, the seed, and the full session configuration, so two logs claiming to be the same experiment can be checked rather than trusted. There is no ROM data in it, only hashes.

Questions the dataset could answer that I have not asked it:

- Does rollback depth correlate with what is happening in the match? There is a document per frame and the recordings are timestamped.
- Is "repeat the last confirmed input" beatable? Every guess and every real input is recorded, so an alternative predictor can be scored offline against 240,000 real frames without touching the engine.

---

## The Videos

All four are unlisted on YouTube. Two are embedded above; here they all are:

- [Madrid to Tokyo, both peers side by side](https://youtu.be/oE1ovIjDDGE) - 267 ms, depth pinned at the limit, the saturation case
- [A human on P1 against the bot in Frankfurt](https://youtu.be/4lm7mr2wblk) - the played session
- [Madrid to Frankfurt, both peers](https://youtu.be/kEijE-A6mHY) - 50 ms, the comfortable case, for contrast
- [Synthetic 20 ms delay, both peers](https://youtu.be/_1GG2LR7hrU) - the mechanism in isolation, reproducible with a fixed seed

Watching Tokyo and Frankfurt back to back is the clearest before-and-after in the project. Same game, same code, same everything except distance.

---

## Final Takeaway

This post is not the definitive explanation of rollback netcode. The videos at the top are better starting points, and people who ship this for a living know things I do not.

What I wanted was to stop taking the explanation on faith. Building it meant I had to decide what a savestate actually is, what happens when the prediction window fills, what "deterministic" costs in practice, and who pays when your opponent is 9,700 km away.

The thing I keep coming back to is how *little* the engine knows. It rewinds an arcade game it cannot read: no positions, no health, no idea a fight is even happening. It copies 415,155 opaque bytes, guesses that you are still holding the same direction, and is right about 93% of the time.

That is not a clever algorithm. It is a clever bet about how people hold buttons, wrapped in an unforgiving requirement that two machines never disagree about anything, ever. Most of the engineering in this project went into the second half.

The results are in the repository, the dataset is there so anyone can check them, and the parts I could not measure are written down next to the parts I could.

[https://github.com/clivoa/backstep](https://github.com/clivoa/backstep)
