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
        // octatonic (half-whole) scale -- "wrong"-sounding but still musical harmony, unlike
        // the previous random-Hz noise-hits that buried the pitch and felt chaotic/repetitive.
        // Pxrand never immediately repeats a degree, and durations are slower/more varied than
        // before so it doesn't feel as frantic or samey.
        ~plucks = Pbind(
            \instrument, \tenseHit,
            \scale,   Scale.new([0, 1, 3, 4, 6, 7, 9, 10], 12),
            \root,    0,
            \octave,  Pwrand([4, 5], [0.6, 0.4], inf),
            \degree,  Pxrand((0..7), inf),
            \dur,     Pwhite(0.7, 1.8, inf),
            \rel,     Pwhite(0.6, 1.4, inf),
            \amp,     Pwhite(0.05, 0.12, inf),
        ).play(~clock, target: g);
        ~bells = Pbind(
            \instrument, \tenseHit,
            \scale,   Scale.new([0, 1, 3, 4, 6, 7, 9, 10], 12),
            \root,    -12,
            \octave,  Pwrand([2, 3], [0.7, 0.3], inf),
            \degree,  Pxrand((0..7), inf),
            \dur,     Pwhite(3.0, 6.0, inf),
            \rel,     Pwhite(2.5, 5.0, inf),
            \amp,     Pwhite(0.07, 0.14, inf),
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

~handTimeout      = 0.3;
~scatterThreshold = 0.05;  // /hand_size_delta (windowed, ~8 frames) counted as "fast approach/retreat"
~glassVerbMix     = 0.75;    // dry/wet ratio for \glassBreak / \glassRegroup's reverb (0=dry, 1=wet)
~glassVerbRoom    = 0.95; // reverb room size, close to 1 = big hall (longer decay tail)
~glassDur         = 3.5;  // total synth lifetime -- needs to be long enough that a big-hall
                          // reverb tail isn't abruptly cut off when the synth frees itself

// \glassRegroup is gated (see /regrouping below), not duration-based -- it holds for exactly
// as long as camera.py says the palm is parked in the back position, so only the swell-in and
// fade-out shaping need configuring here, not an overall length.
~glassRegroupBuild   = 0.6;
~glassRegroupRelease = 0.8;

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
    ~particlesActive  = false;  // mirrors camera.py's /particles_active toggle
    ~regroupSynth     = nil;    // currently-held \glassRegroup, if any (see /regrouping)
    ~regrouping       = false;

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
    var size = msg[1];
    ~palm.set(\room, size.linlin(0.1, 0.4, 0.8, 0.2));   // closer -> drier/closer-sounding
    ~lastHandTime = Main.elapsedTime;
}, '/hand_size');

// Windowed (not frame-to-frame) delta computed once in camera.py -- a single-message delta
// missed slower-but-still-deliberate pushes/retreats that spread their motion across several
// frames instead of spiking in just one. Matches what painting_visualizer.pde now uses too.
OSCdef(\handSizeDeltaRx, { |msg|
    var delta = msg[1];
    if (~particlesActive) {
        // particle-follow mode: fast approach -> scatter voice (one-shot). Regroup is no
        // longer triggered from here -- it's a sustained state, see /regrouping below.
        if (delta > ~scatterThreshold) {
            Synth.tail(~padGroup, \glassBreak,
                [\amp, 0.08, \dur, ~glassDur, \verbMix, ~glassVerbMix, \verbRoom, ~glassVerbRoom]);
        };
    } {
        // outside particle-follow mode: the original generic fast-approach accent
        if (delta > ~scatterThreshold) {
            Synth.tail(~padGroup, \calmBell, [\freq, 300, \amp, 0.15, \rel, 3]);
        };
    };
}, '/hand_size_delta');

// Sustained on/off from camera.py (not a one-shot event) -- \glassRegroup plays for exactly
// as long as /regrouping stays 1 (i.e. the palm stays parked in the back position), by
// releasing its gate the instant camera.py reports the palm moved on to something else.
OSCdef(\regroupingRx, { |msg|
    var active = msg[1] > 0;
    if (active and: { ~regrouping.not }) {
        ~regroupSynth = Synth.tail(~padGroup, \glassRegroup,
            [\amp, 0.1, \gate, 1, \buildDur, ~glassRegroupBuild, \releaseDur, ~glassRegroupRelease,
             \verbMix, ~glassVerbMix, \verbRoom, ~glassVerbRoom]);
        ~regrouping = true;
    };
    if (active.not and: { ~regrouping }) {
        ~regroupSynth.set(\gate, 0);
        ~regrouping = false;
    };
}, '/regrouping');

OSCdef(\feedbackRx, { |msg|
    var gesture = msg[1].asSymbol;
    var freq = ~feedbackFreqs[gesture] ?? { 440 };
    Synth.tail(~padGroup, \calmPluck, [\freq, freq, \amp, 0.12, \rel, 3]);
}, '/feedback');

OSCdef(\particlesActiveRx, { |msg|
    ~particlesActive = msg[1] > 0;
    ("particles_active -> " ++ ~particlesActive).postln;
}, '/particles_active');

OSCdef(\dynamicRx, { |msg|
    var gesture = msg[1].asSymbol;
    case
    { gesture == \swipe_left  } { Synth.tail(~padGroup, \calmPluck, [\freq, 500, \amp, 0.1,  \rel, 2]) }
    { gesture == \swipe_right } { Synth.tail(~padGroup, \calmPluck, [\freq, 700, \amp, 0.1,  \rel, 2]) }
    { gesture == \push        } {
        // in particle-follow mode, handSizeRx above drives the scatter/regroup voices instead
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
