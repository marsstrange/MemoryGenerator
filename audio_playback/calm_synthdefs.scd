// SynthDefs for the calm ambient system

// valence/arousal default to 0, which reproduces the original fixed sound exactly —
// SC_mood_reactive.scd live-updates them via .set() from the /valence and /arousal OSC stream
SynthDef(\calmPad, { |out = 0, amp = 0.18, valence = 0, arousal = 0|
    var trig, rootMidi, degrees, freqs, detune, sig, ampLfo, filtFreq, panLfo, sigStereo;
    var vLag, aLag, lfoRate, filtCenter, filtRange;

	//  smooths incoming valence/arousal over 2 seconds so mood changes glide instead of jumping
    vLag = Lag.kr(valence, 2);
    aLag = Lag.kr(arousal, 2);

	// Dust generates random impulses from 0 to +1.
    trig = Dust.kr(0.04 + aLag.max(0) * 0.15); // more notes when aroused
    rootMidi = Demand.kr(trig, 0, // Demand uses each impulse to pull the next value out of a repeating sequence
        Dseq([48, 50, 45, 52, 47, 50].stutter(4), inf)
    );

    // shifts toward brighter/wider intervals as valence rises, tighter/darker as it falls
    degrees = [0, 2, 5, 7] + (vLag * [0, 1, 1, 2]);
    freqs = (rootMidi + degrees).midicps;

    detune = LFNoise1.kr(0.1 ! degrees.size).range(0.99, 1.01);
    freqs = freqs * detune;

    sig = Saw.ar(freqs) * 0.15 + SinOsc.ar(freqs * 2, 0, 0.08);

    lfoRate = 0.01 + aLag.max(0) * 0.03;                // pulses faster when aroused
    ampLfo = SinOsc.kr(lfoRate).range(0.5, 1.0);
    // lagged so SC_mood_reactive.scd's scape crossfade (.set(\amp, 0) then free) fades out
    // smoothly instead of clicking — also makes every calmPad fade in gently on start
    sig = sig * ampLfo * amp.lag(1.5);

    filtCenter = 2900 + (aLag * 1800);                  // brighter when aroused
    filtRange  = 2100 + (aLag.max(0) * 1500);
    filtFreq = SinOsc.kr(0.008).range((filtCenter - filtRange).max(200), filtCenter + filtRange);
    sig = RLPF.ar(sig, filtFreq, 0.3);

    sigStereo = Splay.ar(sig, spread: 0.7);
    panLfo = SinOsc.kr(0.007).range(-0.5, 0.5);
    sigStereo = Pan2.ar(Mix(sigStereo), panLfo);

    sigStereo = FreeVerb.ar(sigStereo, mix: 0.35, room: 0.85, damp: 0.5);

    Out.ar(out, sigStereo);
}).add;

// classical scape's pad — a granular cloud instead of a sustained drone: short sine
// grains scattered around a warm chord, so the texture is event-based and floaty rather
// than continuous. Deliberately a completely different synthesis technique from calmPad
// (or glitchPad below), not just a retuned variant of the same subtractive architecture.
SynthDef(\shimmerPad, { |out = 0, amp = 0.2, valence = 0, arousal = 0|
    var vLag, aLag, root, degrees, freqs, trigRate, grainDur, grains, sub, sig;

    vLag = Lag.kr(valence, 3);
    aLag = Lag.kr(arousal, 3);

    root    = 48 + (vLag * 3);          // root drifts up slightly with valence
    degrees = [0, 4, 7, 11, 14];        // warm major 7/9 stack
    freqs   = (root + degrees).midicps;

    trigRate = 6 + (aLag.max(0) * 14);  // more grains/sec when aroused
    grainDur = 1.2 - (aLag.max(0) * 0.5);

    grains = Mix.fill(6, {
        var trig = Dust.kr(trigRate / 6);
        var idx  = TIRand.kr(0, freqs.size - 1, trig);
        var freq = Select.kr(idx, freqs) * Select.kr(TIRand.kr(0, 1, trig), [1, 2]);
        var pan  = TRand.kr(-1, 1, trig);
        GrainSin.ar(2, trig, grainDur, freq, pan, -1) * 0.35;
    });

    sub = SinOsc.ar(freqs[0] / 2) * 0.08;  // quiet sub-octave anchor under the grain cloud

    sig = grains + sub;
    sig = sig * amp.lag(1.5);
    sig = FreeVerb.ar(sig, mix: 0.55, room: 0.92, damp: 0.35);  // large, lush space

    Out.ar(out, sig);
}).add;

// expressionist scape's pad — unstable FM plus bitcrushed noise bursts, as far from
// shimmerPad's granular cloud as possible while staying synthesis-only (no samples).
// Carrier/mod ratio drift slowly and smoothly (LFNoise1, not the stepped/jumpy LFNoise0
// this used to use) for an unsettled-but-not-random character -- unstable without being chaotic.
SynthDef(\glitchPad, { |out = 0, amp = 0.18, valence = 0, arousal = 0|
    var vLag, aLag, carrier, modFreq, modIndex, fm, burstTrig, noiseBurst, crushSteps, sig;

    vLag = Lag.kr(valence, 2);
    aLag = Lag.kr(arousal, 2);

    carrier  = 55 + LFNoise1.kr(0.1).range(-8, 8);          // drifts smoothly, doesn't jump
    modFreq  = carrier * LFNoise1.kr(0.15).range(1.5, 3.2); // slower, narrower inharmonic drift
    modIndex = 2 + (aLag.max(0) * 6);                       // gentler sidebands even when aroused

    fm = SinOsc.ar(carrier + (SinOsc.ar(modFreq) * modFreq * modIndex)) * 0.5;

    burstTrig  = Dust.kr(0.4 + (aLag.max(0) * 1.5));        // sparser -> less repetitive
    // Latch = sample-and-hold at a low, arousal-dependent rate -> a lo-fi/decimated noise burst
    // (manual decimation with core UGens; Decimator itself needs the sc3-plugins extension)
    noiseBurst = Latch.ar(WhiteNoise.ar(1), Impulse.ar(8000 - (aLag.max(0) * 6000)))
                 * EnvGen.kr(Env.perc(0.001, 0.3), burstTrig) * 0.25;

    sig = fm + noiseBurst;
    crushSteps = 2 ** LFNoise1.kr(0.2).range(5, 9).round(1);  // milder bitcrush -> less sharp
    sig = (sig * crushSteps).round(1) / crushSteps;
    sig = sig * amp.lag(1.5);
    sig = HPF.ar(sig, 100);
    sig = FreeVerb.ar(sig, mix: 0.25, room: 0.5, damp: 0.15);  // a bit more space to smooth the edges

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(0.3).range(-1, 1)));  // slower pan drift
}).add;

// abstract scape's pad — additive drone: independent sine partials, each fading in/out on its
// own random slow schedule (LFNoise1 per-partial). No chord, no notes, no rhythm — just a
// near-static wash of a few frequencies drifting in and out, evoking Minimalism/Color Field
// Painting's stillness rather than a melodic or granular texture.
SynthDef(\driftPad, { |out = 0, amp = 0.14, valence = 0, arousal = 0|
    var vLag, aLag, freqs, partials, sig;

    vLag = Lag.kr(valence, 6);
    aLag = Lag.kr(arousal, 6);

    freqs = [60, 97, 151, 214, 288, 379] * (1 + (vLag * 0.02));  // sparse, non-tonal, wide-spaced

    partials = Mix.fill(freqs.size, { |i|
        var indepLfo = LFNoise1.kr(0.02 + (0.01 * i) + (aLag.max(0) * 0.05)).range(0.0, 1.0);
        SinOsc.ar(freqs[i]) * indepLfo * 0.15;
    });

    sig = partials * amp.lag(1.5);
    sig = FreeVerb.ar(sig, mix: 0.6, room: 0.95, damp: 0.6);

    Out.ar(out, sig ! 2);
}).add;

// impressionist scape's pad — modal/resonant wash: a fixed bank of resonant filters (Klank,
// tuned to a whole-tone scale — the classic "Impressionist" harmonic color) rung by soft,
// sparse noise clicks, blurred together with a huge reverb. A struck-glass/wind-chime wash
// rather than an oscillator drone or a granular cloud.
SynthDef(\hazeBank, { |out = 0, amp = 0.18, valence = 0, arousal = 0|
    var vLag, aLag, freqs, amps, rings, freqScale, decayScale, trig, exciter, sig;

    vLag = Lag.kr(valence, 4);
    aLag = Lag.kr(arousal, 4);

    freqs = (55 + [0, 2, 4, 6, 8, 10]).midicps;  // fixed whole-tone scale (Klank needs literal numbers)
    amps  = [1, 0.8, 0.9, 0.7, 0.85, 0.6];
    rings = [4, 5, 3.5, 6, 4.5, 5.5];

    freqScale  = 1 + (vLag * 0.03);        // subtle brightening with valence
    decayScale = 1 + (aLag.max(0) * 1.5);  // longer, blurrier rings when aroused

    trig = Dust.kr(0.3 + (aLag.max(0) * 1.5));
    exciter = PinkNoise.ar(1) * EnvGen.kr(Env.perc(0.005, 0.05), trig);

    sig = Klank.ar(`[freqs, amps, rings], exciter, freqScale, 0, decayScale);
    sig = sig * amp.lag(1.5) * 0.2;
    sig = FreeVerb.ar(sig, mix: 0.6, room: 0.95, damp: 0.6);  // huge blurred space

    Out.ar(out, sig ! 2);
}).add;

// pop scape's pad — a quantized, sequenced pulse-wave bassline instead of a drone. Bright,
// punchy, and rhythmic (Impulse.kr = steady clock, not random Dust) to match Pop Art's bold,
// mechanical/repetitive graphic energy — the only scape with a clear, steady beat.
SynthDef(\popPulse, { |out = 0, amp = 0.2, valence = 0, arousal = 0|
    var vLag, aLag, seqTrig, bassFreq, pw, env, sig;

    vLag = Lag.kr(valence, 1.5);
    aLag = Lag.kr(arousal, 1.5);

    seqTrig  = Impulse.kr(2 + (aLag.max(0) * 2));  // steady quantized pulse, speeds up w/ arousal
    bassFreq = Demand.kr(seqTrig, 0, Dseq([36, 36, 43, 41].midicps, inf));
    pw       = 0.3 + (vLag * 0.15);

    env = EnvGen.kr(Env.perc(0.001, 0.15), seqTrig);
    sig = Pulse.ar(bassFreq, pw) * env;
    sig = LPF.ar(sig, 1200 + (aLag.max(0) * 2000));
    sig = sig * amp.lag(1.5);
    sig = FreeVerb.ar(sig, mix: 0.15, room: 0.3, damp: 0.2);  // tight, dry, punchy

    Out.ar(out, Pan2.ar(sig, 0));
}).add;

SynthDef(\calmPluck, { |out = 0, freq = 440, amp = 0.12, rel = 6|
    var env, sig;

    env = EnvGen.kr(Env.linen(0.01, rel, 2), doneAction: 2);

    sig = Pluck.ar(
        in:  PinkNoise.ar(0.3),
        trig: Impulse.ar(0),
        maxdelaytime: 1.0,
        delaytime:    1 / freq,
        decaytime:    rel,
        coef:         0.35
    );

    sig = LPF.ar(sig, 4000);
    sig = sig * env * amp;

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(0.5)));
}).add;

SynthDef(\calmBell, { |out = 0, freq = 440, amp = 0.1, rel = 8|
    var env, mod, sig;

    env = EnvGen.kr(Env.perc(0.01, rel, curve: -4), doneAction: 2);

    mod = SinOsc.ar(freq * 2.7, 0, freq * 2);
    sig = SinOsc.ar(freq + mod) * env * amp;

    sig = HPF.ar(sig, 300);
    sig = FreeVerb.ar(sig, mix: 0.5, room: 0.9, damp: 0.3);

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(0.3)));
}).add;

SynthDef(\calmNoise, { |out = 0, amp = 0.06|
    var sig, filtFreq;

    sig = PinkNoise.ar(amp.lag(1.5));  // lagged so it fades with the rest of its scape group

    filtFreq = LFNoise1.kr(0.15).range(500, 4000);
    sig = BPF.ar(sig, filtFreq, 0.25);

    sig = FreeVerb.ar(sig, mix: 0.4, room: 0.9, damp: 0.5);

    Out.ar(out, sig ! 2);
}).add;

// expressionist scape's one-shot voice — a tuned note (freq now comes from the octatonic
// scale in ~scapeMap, not a random Hz value) with a touch of inharmonic ring and a brief
// noisy attack transient for "unsettled" color, instead of the previous all-noise hit that
// buried the pitch entirely and read as harsh, unpitched percussion
SynthDef(\tenseHit, { |out = 0, freq = 200, amp = 0.15, rel = 0.6|
    var env, attackNoise, sig;

    env = EnvGen.kr(Env.perc(0.005, rel, curve: -4), doneAction: 2);
    attackNoise = WhiteNoise.ar(0.15) * EnvGen.kr(Env.perc(0.001, 0.05));

    sig = SinOsc.ar(freq) + attackNoise;
    sig = RLPF.ar(sig, freq * Rand(1.2, 2.2), 0.25);  // mild inharmonic color, stays close to the fundamental
    sig = HPF.ar(sig, 80);
    sig = sig * env * amp;

    Out.ar(out, Pan2.ar(sig, Rand(-1.0, 1.0)));
}).add;

// expressionist scape's texture bed — grittier and more unstable than calmNoise, but with
// smooth (LFNoise2/LFNoise1) rather than jumpy (LFNoise0) motion, so it reads as unsettled
// rather than chaotic
SynthDef(\tenseNoise, { |out = 0, amp = 0.07|
    var sig, filtFreq, burst;

    sig = WhiteNoise.ar(amp.lag(1.5));

    filtFreq = LFNoise2.kr(0.25).range(400, 5000);
    sig = BPF.ar(sig, filtFreq, 0.2);

    burst = LFNoise1.kr(0.8).range(0.5, 1.0);  // smooth swell instead of jumpy level changes
    sig = sig * burst;

    sig = (sig * 256).round(1) / 256;                        // milder grit than before
    sig = FreeVerb.ar(sig, mix: 0.3, room: 0.6, damp: 0.25);

    Out.ar(out, sig ! 2);
}).add;

// abstract scape's one-shot voice — an extremely soft, slow sine swell (Env.sine has no sharp
// attack, unlike Env.perc elsewhere), triggered very rarely. Almost more silence than sound.
SynthDef(\driftTone, { |out = 0, freq = 110, amp = 0.06, rel = 10|
    var env, sig;

    env = EnvGen.kr(Env.sine(rel), doneAction: 2);  // rel = length of the whole rise-and-fall swell
    sig = SinOsc.ar(freq) * env * amp;
    sig = FreeVerb.ar(sig, mix: 0.6, room: 0.95, damp: 0.5);

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(0.05)));
}).add;

// abstract scape's texture bed — near-silent, extremely slow-drifting filtered noise, a
// "room tone" rather than an audible atmosphere, reinforcing the family's near-stillness
SynthDef(\driftHum, { |out = 0, amp = 0.02|
    var sig, filtFreq;

    sig = PinkNoise.ar(amp.lag(1.5));

    filtFreq = LFNoise1.kr(0.02).range(200, 1000);  // far slower than calmNoise/tenseNoise
    sig = BPF.ar(sig, filtFreq, 0.2);
    sig = FreeVerb.ar(sig, mix: 0.5, room: 0.95, damp: 0.6);

    Out.ar(out, sig ! 2);
}).add;

// impressionist scape's one-shot voice — two nearly-unison detuned sines with a soft sine-shaped
// swell (no percussive attack), producing a slow natural "beating" shimmer rather than a clang
SynthDef(\hazeBell, { |out = 0, freq = 440, amp = 0.1, rel = 6|
    var env, sig;

    env = EnvGen.kr(Env.sine(rel), doneAction: 2);
    sig = Mix(SinOsc.ar(freq * [1, 1.004])) * 0.5;
    sig = sig * env * amp;
    sig = FreeVerb.ar(sig, mix: 0.7, room: 0.95, damp: 0.5);

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(0.2)));
}).add;

// impressionist scape's texture bed — sparse high-frequency "twinkles" (short sine blips at
// random pitch/pan) instead of a continuous noise sweep, like light glinting on water
SynthDef(\hazeShimmer, { |out = 0, amp = 0.05|
    var trig, freq, sig;

    trig = Dust.kr(8);
    freq = TExpRand.kr(2000, 6000, trig);
    sig  = SinOsc.ar(freq) * EnvGen.kr(Env.perc(0.001, 0.3), trig) * 0.3;
    sig  = sig * amp.lag(1.5);
    sig  = FreeVerb.ar(sig, mix: 0.5, room: 0.9, damp: 0.3);

    Out.ar(out, Pan2.ar(sig, TRand.kr(-1.0, 1.0, trig)));
}).add;

// pop scape's one-shot voice — bright, punchy detuned-pulse stabs with a fast, short envelope,
// matching popPulse's quantized rhythmic feel instead of the ambient one-shots elsewhere
SynthDef(\popStab, { |out = 0, freq = 440, amp = 0.15, rel = 0.3|
    var env, sig;

    env = EnvGen.kr(Env.perc(0.001, rel, curve: -6), doneAction: 2);
    sig = Pulse.ar(freq, 0.5) + Pulse.ar(freq * 1.005, 0.5);  // slightly detuned unison for thickness
    sig = LPF.ar(sig, 3000);
    sig = sig * env * amp;

    Out.ar(out, Pan2.ar(sig, LFNoise1.kr(1)));
}).add;

// pop scape's texture bed — a steady hi-hat-like tick instead of an atmospheric noise wash,
// giving the family a driving, mechanical pulse instead of ambient texture
SynthDef(\popHat, { |out = 0, amp = 0.04|
    var trig, sig;

    trig = Impulse.kr(4);
    sig  = HPF.ar(WhiteNoise.ar(1), 6000) * EnvGen.kr(Env.perc(0.001, 0.05), trig);
    sig  = sig * amp.lag(1.5);

    Out.ar(out, sig ! 2);
}).add;

// particle-follow mode's "scatter" voice -- fires on a fast approach (palm toward camera).
// Synthesis-only (no sample): a sharp initial crack (fast-decay high-passed noise) followed
// by a cloud of short, randomly-pitched high sine "shard" grains whose trigger density
// decays from dense to sparse, like shards flying outward then settling. One-shot, fixed
// duration -- this is a discrete event tied to the motion, not a sustained/held sound.
SynthDef(\glassBreak, { |out = 0, amp = 0.35, dur = 1.8, attackTime = 0.05,
                         verbMix = 0.25, verbRoom = 0.6, verbDamp = 0.2|
    var overallEnv, crack, shardDensity, shardTrig, shards, sig, coreDur;

    // the crash itself (crack + shard density decay) stays a fixed, punchy length regardless
    // of dur -- dur beyond coreDur only extends a gentle envelope tail-out, giving a bigger
    // room-size reverb space to ring out in rather than dragging the dry crackle on for seconds
    coreDur = 1.5;

    // attackTime replaces what used to be a hard 0.001s instant jump to full level -- a short
    // fade-in avoids a click on the overall envelope while still reading as a fast, punchy hit
    overallEnv = EnvGen.kr(Env.linen(attackTime, coreDur - 0.2 - attackTime, (dur - coreDur + 0.2).max(0.2)), doneAction: 2);

    crack = HPF.ar(WhiteNoise.ar(1), 2000) * EnvGen.kr(Env.perc(0.001, 0.08, curve: -10));

    shardDensity = EnvGen.kr(Env([35, 35, 0.5], [0.05, coreDur - 0.15], curve: -4));
    shardTrig    = Dust.kr(shardDensity);

    shards = Mix.fill(3, {
        var freq = TExpRand.kr(1800, 7000, shardTrig);
        var pan  = TRand.kr(-1.0, 1.0, shardTrig);
        var env  = EnvGen.kr(Env.perc(0.001, TRand.kr(0.03, 0.15, shardTrig), curve: -8), shardTrig);
        Pan2.ar(SinOsc.ar(freq) * env, pan) * 0.3;
    });

    sig = (crack ! 2 * 0.6) + shards;
    sig = sig * amp * overallEnv;
    sig = FreeVerb.ar(sig, mix: verbMix, room: verbRoom, damp: verbDamp);

    Out.ar(out, sig);
}).add;

// particle-follow mode's "regroup" voice -- gated, not a fixed-duration one-shot: swells in
// once (~0.6s), then holds at a settled rumble for exactly as long as gate=1 (i.e. for as
// long as camera.py's /regrouping says the palm is still parked in the back position), and
// fades out over releaseDur the instant gate drops (palm moved forward again or sideways).
// A soft "settling click" marks that release moment instead of a scheduled impact, since
// there's no longer a predetermined end time to schedule one against.
SynthDef(\glassRegroup, { |out = 0, amp = 0.35, gate = 1, buildDur = 0.6, releaseDur = 0.8,
                           verbMix = 0.25, verbRoom = 0.6, verbDamp = 0.2|
    var env, releaseTrig, thud, shardDensity, shardTrig, shards, sig;

    env = EnvGen.kr(Env.asr(buildDur, 1, releaseDur), gate, doneAction: 2);

    // rises once over buildDur, then EnvGen just keeps outputting the final level indefinitely
    // -- no gate-awareness needed here, the settled rate holds on its own until freed
    shardDensity = EnvGen.kr(Env([0.5, 18], [buildDur], curve: 4));
    shardTrig    = Dust.kr(shardDensity);

    shards = Mix.fill(3, {
        var freq = TExpRand.kr(1800, 7000, shardTrig);
        var pan  = TRand.kr(-1.0, 1.0, shardTrig);
        var shardEnv = EnvGen.kr(Env.perc(0.001, TRand.kr(0.03, 0.15, shardTrig), curve: -8), shardTrig);
        Pan2.ar(SinOsc.ar(freq) * shardEnv, pan) * 0.3;
    });

    // fires exactly once, right when gate transitions from 1 to 0
    releaseTrig = Trig.kr(1 - gate, 0.01);
    thud = HPF.ar(WhiteNoise.ar(1), 1200) * EnvGen.kr(Env.perc(0.01, 0.15, curve: -6), releaseTrig);

    sig = (thud ! 2 * 0.5) + shards;
    sig = sig * amp * env;
    sig = FreeVerb.ar(sig, mix: verbMix, room: verbRoom, damp: verbDamp);

    Out.ar(out, sig);
}).add;

"Calm SynthDefs loaded.".postln;