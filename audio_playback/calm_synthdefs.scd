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
// Carrier/mod ratio jump around randomly (LFNoise0 = stepped, not smooth) for an
// unpredictable, broken-electronics character instead of a floaty or tonal one.
SynthDef(\glitchPad, { |out = 0, amp = 0.18, valence = 0, arousal = 0|
    var vLag, aLag, carrier, modFreq, modIndex, fm, burstTrig, noiseBurst, crushSteps, sig;

    vLag = Lag.kr(valence, 2);
    aLag = Lag.kr(arousal, 2);

    carrier  = 55 + LFNoise0.kr(0.5).range(-8, 8);       // jumps around, never settles
    modFreq  = carrier * LFNoise0.kr(0.7).range(1.5, 4.3); // inharmonic, randomly-stepped ratio
    modIndex = 3 + (aLag.max(0) * 12);                     // harsher/more sidebands when aroused

    fm = SinOsc.ar(carrier + (SinOsc.ar(modFreq) * modFreq * modIndex)) * 0.5;

    burstTrig  = Dust.kr(0.8 + (aLag.max(0) * 3));
    // Latch = sample-and-hold at a low, arousal-dependent rate -> a lo-fi/decimated noise burst
    // (manual decimation with core UGens; Decimator itself needs the sc3-plugins extension)
    noiseBurst = Latch.ar(WhiteNoise.ar(1), Impulse.ar(11025 - (aLag.max(0) * 10000)))
                 * EnvGen.kr(Env.perc(0.001, 0.3), burstTrig) * 0.4;

    sig = fm + noiseBurst;
    crushSteps = 2 ** LFNoise0.kr(0.3).range(3, 8).round(1);  // ~"3 to 8 bit" quantization steps
    sig = (sig * crushSteps).round(1) / crushSteps;           // manual bitcrush (no plugin needed)
    sig = sig * amp.lag(1.5);
    sig = HPF.ar(sig, 100);
    sig = FreeVerb.ar(sig, mix: 0.15, room: 0.4, damp: 0.1);       // dry, close, unsettling

    Out.ar(out, Pan2.ar(sig, LFNoise0.kr(1.5).range(-1, 1)));
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

// expressionist scape's one-shot voice — inharmonic, metallic noise-hits instead of a
// tuned pluck/bell. freq sets the resonance center, not a note in a scale: each hit
// gets its own random inharmonic ring and pan, so it never reads as "melody"
SynthDef(\tenseHit, { |out = 0, freq = 200, amp = 0.15, rel = 0.6|
    var env, sig;

    env = EnvGen.kr(Env.perc(0.001, rel, curve: -8), doneAction: 2);

    sig = WhiteNoise.ar(0.6) + SinOsc.ar(freq);
    sig = RLPF.ar(sig, freq * Rand(2.0, 6.0), 0.15);  // inharmonic metallic resonance, unique per hit
    sig = HPF.ar(sig, 150);
    sig = (sig * 64).round(1) / 64;                   // manual bitcrush grit, matches glitchPad
    sig = sig * env * amp;

    Out.ar(out, Pan2.ar(sig, Rand(-1.0, 1.0)));
}).add;

// expressionist scape's texture bed — grittier and more unstable than calmNoise:
// faster/jumpier filter motion and random amplitude bursts instead of a smooth sweep
SynthDef(\tenseNoise, { |out = 0, amp = 0.07|
    var sig, filtFreq, burst;

    sig = WhiteNoise.ar(amp.lag(1.5));

    filtFreq = LFNoise2.kr(0.6).range(400, 6000);
    sig = BPF.ar(sig, filtFreq, 0.15);

    burst = LFNoise0.kr(2).range(0.4, 1.0);  // random jumps in level -> nervous/unstable feel
    sig = sig * burst;

    sig = (sig * 128).round(1) / 128;                        // manual bitcrush grit, matches glitchPad
    sig = FreeVerb.ar(sig, mix: 0.2, room: 0.5, damp: 0.2);  // drier than calmNoise

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

"Calm SynthDefs loaded.".postln;