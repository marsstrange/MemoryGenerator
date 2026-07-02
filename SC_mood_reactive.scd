// ============================================
// MOOD-REACTIVE SOUND SYSTEM
// Listens on port 12001 — camera.py sends the same messages to Processing (port
// 12000) and here on a separate port, since two processes can't reliably share
// one UDP port.
//
// Independent of SC_audio_and_effects.scd (that one is the separate
// Gemini/YOLO prompt-driven pipeline on port 57120).
// ============================================

s.waitForBoot({

"calm_synthdefs.scd".loadRelative;

thisProcess.openUDPPort(12001);

if (~padGroup.notNil) { ~padGroup.free };
if (~plucks.notNil)   { ~plucks.stop };
if (~bells.notNil)    { ~bells.stop };
if (~handWatchdog.notNil) { ~handWatchdog.stop };

~padGroup = Group.new;

// ── mood state, read live by the Pbind patterns below via Pfunc ────────────
~mood = (valence: 0.0, arousal: 0.0, emotion: \neutral);

// ── tier 1: ambient bed — reacts continuously to valence/arousal ───────────
~pad      = Synth(\calmPad,   [\amp, 0.18], ~padGroup);
~noiseBed = Synth(\calmNoise, [\amp, 0.05], ~padGroup);

~clock = TempoClock.default;

~plucks = Pbind(
    \instrument, \calmPluck,
    \scale,   Pfunc({ if(~mood.valence >= 0) { Scale.major } { Scale.minor } }),
    \root,    0,
    \octave,  Pwrand([4, 5], [0.7, 0.3], inf),
    \degree,  Pwhite(0, 7, inf),
    \dur,     Pfunc({ (2.6 - (~mood.arousal.max(0) * 1.8)).max(0.5) }),  // faster when aroused
    \rel,     Pwhite(4.0, 9.0, inf),
    \amp,     Pfunc({ 0.04 + (~mood.arousal.max(0) * 0.06) }),
).play(~clock, target: ~padGroup);

~bells = Pbind(
    \instrument, \calmBell,
    \scale,   Pfunc({ if(~mood.valence >= 0) { Scale.major } { Scale.minor } }),
    \root,    -12,
    \octave,  Pwrand([5, 6], [0.8, 0.2], inf),
    \degree,  Pwhite(0, 7, inf),
    \dur,     Pwhite(6.0, 14.0, inf),
    \rel,     Pwhite(5.0, 12.0, inf),
    \amp,     Pwhite(0.03, 0.08, inf),
).play(~clock, target: ~padGroup);

// ── tier 2: palm-driven continuous voice ────────────────────────────────────
// mirrors the Processing particle system: palm_x -> pan, palm_y -> filter,
// hand_size -> proximity (reverb/brightness), matching the visual zoom
SynthDef(\palmVoice, { |out = 0, pan = 0, cutoff = 1200, amp = 0, room = 0.6|
    var sig;
    sig = Saw.ar(70) * 0.4 + PinkNoise.ar(0.25);
    sig = RLPF.ar(sig, cutoff.clip(150, 6000), 0.35);
    sig = sig * amp.lag(0.15);
    sig = FreeVerb.ar(sig, mix: room, room: 0.8, damp: 0.4);
    Out.ar(out, Pan2.ar(sig, pan.clip(-1, 1)));
}).add;

~palm = Synth(\palmVoice, [\amp, 0], ~padGroup);

// silences palmVoice if no hand messages arrive for a while (hand left frame)
~lastHandTime = Main.elapsedTime;
~handTimeout  = 0.3;
~handWatchdog = Routine({
    loop {
        if ((Main.elapsedTime - ~lastHandTime) > ~handTimeout) { ~palm.set(\amp, 0) };
        0.1.wait;
    };
}).play;

// ── tier 3: one-shot event triggers ─────────────────────────────────────────
~lastHandSize     = 0;
~scatterThreshold = 0.05;  // hand_size jump per message counted as "fast approach"

~feedbackFreqs = Dictionary.newFrom([
    \thumbs_up,   660,
    \thumbs_down, 220,
    \ok,          440,
]);

// ── OSC handlers ─────────────────────────────────────────────────────────────

OSCdef(\emotionRx, { |msg| ~mood.emotion = msg[1].asSymbol; }, '/emotion');

OSCdef(\valenceRx, { |msg|
    ~mood.valence = msg[1];
    ~pad.set(\valence, msg[1]);
}, '/valence');

OSCdef(\arousalRx, { |msg|
    ~mood.arousal = msg[1];
    ~pad.set(\arousal, msg[1]);
}, '/arousal');

OSCdef(\palmXRx, { |msg|
    ~palm.set(\pan, msg[1].linlin(0, 1, -1, 1), \amp, 0.15);
    ~lastHandTime = Main.elapsedTime;
}, '/palm_x');

OSCdef(\palmYRx, { |msg|
    ~palm.set(\cutoff, msg[1].linlin(0, 1, 3500, 300));  // hand high in frame -> bright, low -> dark
    ~lastHandTime = Main.elapsedTime;
}, '/palm_y');

OSCdef(\handSizeRx, { |msg|
    var size  = msg[1];
    var delta = size - ~lastHandSize;
    ~palm.set(\room, size.linlin(0.1, 0.4, 0.8, 0.2));   // closer -> drier/closer-sounding
    if (delta > ~scatterThreshold) {
        // fast approach -> impact accent, mirrors the visual particle scatter burst
        Synth.tail(~padGroup, \calmBell, [\freq, 300, \amp, 0.15, \rel, 3]);
    };
    ~lastHandSize = size;
    ~lastHandTime = Main.elapsedTime;
}, '/hand_size');

OSCdef(\feedbackRx, { |msg|
    var gesture = msg[1].asSymbol;
    var freq = ~feedbackFreqs[gesture] ?? { 440 };
    Synth.tail(~padGroup, \calmPluck, [\freq, freq, \amp, 0.12, \rel, 3]);
}, '/feedback');

OSCdef(\dynamicRx, { |msg|
    var gesture = msg[1].asSymbol;
    case
    { gesture == \swipe_left  } { Synth.tail(~padGroup, \calmPluck, [\freq, 500, \amp, 0.1,  \rel, 2]) }
    { gesture == \swipe_right } { Synth.tail(~padGroup, \calmPluck, [\freq, 700, \amp, 0.1,  \rel, 2]) }
    { gesture == \push        } { Synth.tail(~padGroup, \calmBell,  [\freq, 200, \amp, 0.18, \rel, 4]) };
}, '/dynamic');

"Mood-reactive receiver ready on port 12001.".postln;

});
