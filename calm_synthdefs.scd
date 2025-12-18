// SynthDefs for the calm ambient system

SynthDef(\calmPad, { |out = 0, amp = 0.18|
    var trig, rootMidi, degrees, freqs, detune, sig, ampLfo, filtFreq, panLfo, sigStereo;

    trig = Dust.kr(0.04);
    rootMidi = Demand.kr(trig, 0,
        Dseq([48, 50, 45, 52, 47, 50].stutter(4), inf)
    );

    degrees = [0, 2, 5, 7];
    freqs = (rootMidi + degrees).midicps;

    detune = LFNoise1.kr(0.1 ! degrees.size).range(0.99, 1.01);
    freqs = freqs * detune;

    sig = Saw.ar(freqs) * 0.15 + SinOsc.ar(freqs * 2, 0, 0.08);

    ampLfo = SinOsc.kr(0.01).range(0.5, 1.0);
    sig = sig * ampLfo * amp;

    filtFreq = SinOsc.kr(0.008).range(800, 5000);
    sig = RLPF.ar(sig, filtFreq, 0.3);

    sigStereo = Splay.ar(sig, spread: 0.7);
    panLfo = SinOsc.kr(0.007).range(-0.5, 0.5);
    sigStereo = Pan2.ar(Mix(sigStereo), panLfo);

    sigStereo = FreeVerb.ar(sigStereo, mix: 0.35, room: 0.85, damp: 0.5);

    Out.ar(out, sigStereo);
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

    sig = PinkNoise.ar(amp);

    filtFreq = LFNoise1.kr(0.15).range(500, 4000);
    sig = BPF.ar(sig, filtFreq, 0.25);

    sig = FreeVerb.ar(sig, mix: 0.4, room: 0.9, damp: 0.5);

    Out.ar(out, sig ! 2);
}).add;

"Calm SynthDefs loaded.".postln;