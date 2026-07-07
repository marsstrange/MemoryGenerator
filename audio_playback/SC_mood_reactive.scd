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

// sample for \glassBreakGrain's granular "push position" voice (see calm_synthdefs.scd)
~glassBuf = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "samples/glass break normal.wav");

thisProcess.openUDPPort(12001);

~clock = TempoClock.default;

// ── tier 1: ambient bed — reacts continuously to valence/arousal, and swaps
// between "soundscapes" (different pad, texture bed, and one-shot voice — not
// just a different scale on the same instruments) depending on which family the
// current painting's /painting/style belongs to ────────────────────────────

// each entry spawns its own pad + noise bed + patterns into a fresh group and
// reassigns the shared ~pad/~plucks/~bells, then returns the group so
// ~switchScape can track it; the noise bed lives inside the group too, so it
// fades and frees along with everything else on a scape switch
~scapeMap = Dictionary.newFrom([
    \classical, {
        var g = Group.tail(~padGroup);
        ~pad      = Synth(\shimmerPad, [\amp, 0.2, \valence, ~mood.valence, \arousal, ~mood.arousal], g);
        ~noiseBed = Synth(\calmNoise,  [\amp, 0.05], g);
        ~plucks = Pbind(
            \instrument, \calmPluck,
            \scale,   Pfunc({ if(~mood.valence >= 0) { Scale.major } { Scale.minor } }),
            \root,    0,
            \octave,  Pwrand([4, 5], [0.7, 0.3], inf),
            \degree,  Pwhite(0, 7, inf),
            \dur,     Pfunc({ (2.6 - (~mood.arousal.max(0) * 1.8)).max(0.5) }),  // faster when aroused
            \rel,     Pwhite(4.0, 9.0, inf),
            \amp,     Pfunc({ 0.04 + (~mood.arousal.max(0) * 0.06) }),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \calmBell,
            \scale,   Pfunc({ if(~mood.valence >= 0) { Scale.major } { Scale.minor } }),
            \root,    -12,
            \octave,  Pwrand([5, 6], [0.8, 0.2], inf),
            \degree,  Pwhite(0, 7, inf),
            \dur,     Pwhite(6.0, 14.0, inf),
            \rel,     Pwhite(5.0, 12.0, inf),
            \amp,     Pwhite(0.03, 0.08, inf),
        ).play(~clock, target: g);
        g;
    },
    \expressionist, {
        var g = Group.tail(~padGroup);
        ~pad      = Synth(\glitchPad, [\amp, 0.18, \valence, ~mood.valence, \arousal, ~mood.arousal], g);
        ~noiseBed = Synth(\tenseNoise, [\amp, 0.07], g);
        // inharmonic metallic hits, not tuned notes — no \scale/\degree, freq is
        // just the resonance center (see \tenseHit), so this reads as noise-events
        // rather than a melody, deliberately unlike classical's plucked/bell voice
        ~plucks = Pbind(
            \instrument, \tenseHit,
            \freq,    Pwhite(300, 1200, inf),
            \dur,     Pwhite(0.15, 0.9, inf),        // fast, agitated
            \rel,     Pwhite(0.2, 0.8, inf),
            \amp,     Pwhite(0.08, 0.18, inf),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \tenseHit,
            \freq,    Pwhite(60, 200, inf),          // low, ominous rumbles
            \dur,     Pwhite(1.0, 3.5, inf),
            \rel,     Pwhite(1.5, 4.0, inf),
            \amp,     Pwhite(0.10, 0.20, inf),
        ).play(~clock, target: g);
        g;
    },
    \abstract, {
        // sparse, low, non-tonal pool — matches driftPad's frequencies rather than a scale
        var g = Group.tail(~padGroup);
        var freqs = (36 + [0, 5, 7, 10]).midicps;
        ~pad      = Synth(\driftPad, [\amp, 0.14, \valence, ~mood.valence, \arousal, ~mood.arousal], g);
        ~noiseBed = Synth(\driftHum, [\amp, 0.02], g);
        // very rare, very quiet swells — no \scale/\degree, this scape is mostly silence
        ~plucks = Pbind(
            \instrument, \driftTone,
            \freq,    Prand(freqs, inf),
            \dur,     Pwhite(10.0, 22.0, inf),
            \rel,     Pwhite(8.0, 16.0, inf),
            \amp,     Pwhite(0.04, 0.08, inf),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \driftTone,
            \freq,    Prand(freqs * 2, inf),
            \dur,     Pwhite(14.0, 28.0, inf),
            \rel,     Pwhite(10.0, 20.0, inf),
            \amp,     Pwhite(0.03, 0.06, inf),
        ).play(~clock, target: g);
        g;
    },
    \impressionist, {
        // whole-tone pool, matches hazeBank's fixed resonant bank
        var g = Group.tail(~padGroup);
        var freqs = (55 + [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]).midicps;
        ~pad      = Synth(\hazeBank,    [\amp, 0.18, \valence, ~mood.valence, \arousal, ~mood.arousal], g);
        ~noiseBed = Synth(\hazeShimmer, [\amp, 0.05], g);
        ~plucks = Pbind(
            \instrument, \hazeBell,
            \freq,    Prand(freqs, inf),
            \dur,     Pwhite(2.0, 5.0, inf),
            \rel,     Pwhite(4.0, 8.0, inf),
            \amp,     Pwhite(0.05, 0.12, inf),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \hazeBell,
            \freq,    Prand(freqs * 2, inf),          // an octave up, "high shimmer" voice
            \dur,     Pwhite(3.0, 7.0, inf),
            \rel,     Pwhite(5.0, 10.0, inf),
            \amp,     Pwhite(0.03, 0.08, inf),
        ).play(~clock, target: g);
        g;
    },
    \pop, {
        // quantized, pentatonic, and rhythmic — the only scape with a clear steady beat
        var g = Group.tail(~padGroup);
        ~pad      = Synth(\popPulse, [\amp, 0.2, \valence, ~mood.valence, \arousal, ~mood.arousal], g);
        ~noiseBed = Synth(\popHat,   [\amp, 0.04], g);
        ~plucks = Pbind(
            \instrument, \popStab,
            \scale,   Scale.majorPentatonic,
            \root,    0,
            \octave,  5,
            \degree,  Pxrand((0..4), inf),
            \dur,     Prand([0.25, 0.25, 0.5], inf),
            \rel,     0.25,
            \amp,     Pwhite(0.10, 0.18, inf),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \popStab,
            \scale,   Scale.majorPentatonic,
            \root,    0,
            \octave,  3,
            \degree,  Pxrand((0..4), inf),
            \dur,     Prand([0.5, 1.0], inf),
            \rel,     0.4,
            \amp,     Pwhite(0.12, 0.2, inf),
        ).play(~clock, target: g);
        g;
    },
]);

// only the first token before a comma matters for the rare multi-label styles
// (e.g. "Cubism,Expressionism" -> "Cubism"); covers all 22 WikiArt style categories now
~styleToScape = Dictionary.newFrom([
    "Realism",             \classical,
    "Northern Renaissance", \classical,
    "Early Renaissance",    \classical,
    "High Renaissance",     \classical,
    "Baroque",              \classical,
    "Rococo",               \classical,
    "Romanticism",          \classical,
    "Neoclassicism",        \classical,

    "Expressionism",        \expressionist,
    "Neo-Expressionism",    \expressionist,
    "Cubism",               \expressionist,
    "Surrealism",           \expressionist,

    "Abstract Art",           \abstract,
    "Abstract Expressionism", \abstract,
    "Minimalism",             \abstract,
    "Color Field Painting",   \abstract,
    "Lyrical Abstraction",    \abstract,
    "Art Informel",           \abstract,

    "Impressionism",         \impressionist,
    "Post-Impressionism",    \impressionist,
    "Magic Realism",         \impressionist,

    "Pop Art",               \pop,
]);

~resolveScape = { |styleStr|
    var first = styleStr.split($,)[0];
    ~styleToScape[first] ?? { \classical };
};

// crossfades by fading the outgoing pad out (each pad's amp is lagged, see
// calm_synthdefs.scd) while the incoming pad fades in the same way, then frees the old group
~switchScape = { |name|
    if (name != ~currentScapeName and: { ~scapeMap.includesKey(name) }) {
        var oldGroup = ~scapeGroup;

        ("Switching soundscape -> " ++ name).postln;

        if (oldGroup.notNil) {
            ~plucks.stop;
            ~bells.stop;
            oldGroup.set(\amp, 0);
            fork { 2.0.wait; oldGroup.free };
        };

        ~scapeGroup = ~scapeMap[name].value;
        ~currentScapeName = name;
    };
};

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

// SynthDef(...).add is async -- without this, ~initAudioState.value below can try to
// instantiate \palmVoice (or anything from calm_synthdefs.scd) before the server has
// actually confirmed it finished compiling, causing "SynthDef not found" errors
s.sync;

// numFrames == 0 (or a giant/bogus number) means the path didn't resolve to a real file --
// this only prints something meaningful because it runs after s.sync, once the async
// Buffer.read has actually completed
("glass sample loaded: " ++ ~glassBuf.numFrames ++ " frames, "
    ++ ~glassBuf.numChannels ++ " channel(s), path=" ++ ~glassBuf.path).postln;

~handTimeout      = 0.3;
~scatterThreshold = 0.05;  // hand_size jump per message counted as "fast approach"

~feedbackFreqs = Dictionary.newFrom([
    \thumbs_up,   660,
    \thumbs_down, 220,
    \ok,          440,
]);

// ── (re)build a clean, ready-to-play state ──────────────────────────────────
// Called once at boot, AND again from /shutdown -- so telling SC to stop the sound
// doesn't leave ~padGroup/~pad/~palm etc. pointing at freed, dead nodes. Without this,
// restarting camera.py against the same still-running sclang process (rather than
// closing and reopening it) would hit the same "node not found" errors we hit before,
// since every OSCdef references these vars directly.
~initAudioState = {
    if (~padGroup.notNil)     { ~padGroup.free };
    if (~plucks.notNil)       { ~plucks.stop };
    if (~bells.notNil)        { ~bells.stop };
    if (~handWatchdog.notNil) { ~handWatchdog.stop };

    ~padGroup         = Group.new;
    ~scapeGroup       = nil;
    ~currentScapeName = nil;
    ~mood             = (valence: 0.0, arousal: 0.0, emotion: \neutral);
    ~lastHandSize     = 0;
    ~particlesActive  = false;  // mirrors camera.py's /particles_active toggle
    ~glassSynth       = nil;    // currently-playing \glassBreakGrain, if any (see /push_active)
    ~glassPlaying     = false;

    ~palm = Synth(\palmVoice, [\amp, 0], ~padGroup);

    // silences palmVoice if no hand messages arrive for a while (hand left frame)
    ~lastHandTime = Main.elapsedTime;
    ~handWatchdog = Routine({
        loop {
            if ((Main.elapsedTime - ~lastHandTime) > ~handTimeout) { ~palm.set(\amp, 0) };
            0.1.wait;
        };
    }).play;

    // Spawn a classical scape just so ~pad/~plucks/~bells/~scapeGroup are valid objects
    // (avoids nil errors if e.g. /valence arrives before the first real /painting/style),
    // then immediately silence and stop it and forget we did this by resetting
    // ~currentScapeName back to nil -- otherwise this "bootstrap" scape would (a) audibly
    // play on its own right after a /shutdown reset (the group-level amp silence only
    // covers the continuous pad/noise bed, not the ~plucks/~bells patterns, which keep
    // firing their own one-shot notes at their own amp regardless), and (b) if the first
    // *real* painting selection also resolves to \classical, ~switchScape would see no
    // change and skip fading it back in.
    ~switchScape.(\classical);
    ~scapeGroup.set(\amp, 0);
    ~plucks.stop;
    ~bells.stop;
    ~currentScapeName = nil;
};

~initAudioState.value;

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

OSCdef(\paintingStyleRx, { |msg|
    var style = msg[1].asString;
    var scape = ~resolveScape.(style);
    ("Painting style: " ++ style ++ "  ->  scape: " ++ scape).postln;
    ~switchScape.(scape);
}, '/painting/style');

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
    // fast approach -> impact accent, mirrors the visual particle scatter burst. Only outside
    // particle-follow mode -- in that mode /push_active drives the glass-break voice instead,
    // and this independent trigger would otherwise still fire the bell alongside/over it
    if (delta > ~scatterThreshold and: { ~particlesActive.not }) {
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

OSCdef(\particlesActiveRx, { |msg|
    ~particlesActive = msg[1] > 0;
    ("particles_active -> " ++ ~particlesActive).postln;
}, '/particles_active');

// Sustained on/off from camera.py's hand_size hysteresis (not a one-shot event) -- the
// granular glass-break voice plays for exactly as long as /push_active stays 1, regardless
// of how long that turns out to be, by releasing its gate the instant it goes back to 0.
OSCdef(\pushActiveRx, { |msg|
    var active = msg[1] > 0;
    ("push_active -> " ++ active ++ " (glassPlaying was " ++ ~glassPlaying ++ ")").postln;
    if (active and: { ~glassPlaying.not }) {
        ~glassSynth = Synth.tail(~padGroup, \glassBreakGrain, [\buf, ~glassBuf, \amp, 0.3, \gate, 1]);
        ~glassPlaying = true;
        "-> started glassBreakGrain".postln;
    };
    if (active.not and: { ~glassPlaying }) {
        ~glassSynth.set(\gate, 0);
        ~glassPlaying = false;
        "-> released glassBreakGrain".postln;
    };
}, '/push_active');

OSCdef(\dynamicRx, { |msg|
    var gesture = msg[1].asSymbol;
    case
    { gesture == \swipe_left  } { Synth.tail(~padGroup, \calmPluck, [\freq, 500, \amp, 0.1,  \rel, 2]) }
    { gesture == \swipe_right } { Synth.tail(~padGroup, \calmPluck, [\freq, 700, \amp, 0.1,  \rel, 2]) }
    { gesture == \push        } {
        // in particle-follow mode, /push_active above drives the glass-break voice instead
        if (~particlesActive.not) {
            Synth.tail(~padGroup, \calmBell, [\freq, 200, \amp, 0.18, \rel, 4]);
        };
    };
}, '/dynamic');

// camera.py sends this from its try/finally on exit — normal quit, crash, or Ctrl+C.
// Fully resets back to a clean, ready state (see ~initAudioState above) rather than just
// freeing everything, so the next camera.py run works against this same sclang process
// without needing SC itself restarted.
OSCdef(\shutdownRx, { |msg|
    "Received /shutdown — resetting to a clean state.".postln;
    ~initAudioState.value;
}, '/shutdown');

"Mood-reactive receiver ready on port 12001.".postln;

});
