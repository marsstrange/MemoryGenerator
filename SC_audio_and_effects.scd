s.boot;

// Load SynthDefs from calm_synthdefs.scd in the same directory as main.scd
"calm_synthdefs.scd".loadRelative;

~classInstances = Dictionary.new; // a dictionary to store class instances
~buffers = Dictionary.new; // a dictionary to store buffers

// loading saples

// NOTE: loading is async, we need to wait until we see the "Loaded ..." messages
// in the Post window before we start sending OSC.

~buffers["water"] = Buffer.read(
    server: s,
    path:   "D:/PoliMi/3_term/CPAC/Project/samples/rain-window-04.wav",
    action: { |buf| ("Loaded 'water' from: " ++ buf.path).postln; }
);

// play a buffer by name
~playBufByName = { |className|
    var buf = ~buffers[className];
    var synth;

    if(buf.isNil) {
        ("No buffer loaded for class: " ++ className).warn;
        ^nil;
    };

    ("Playing sample for " ++ className).postln;

    synth = {
        var sig;
        sig = PlayBuf.ar(
            numChannels: buf.numChannels,
            bufnum: buf,
            rate: BufRateScale.kr(buf),
			trigger: 1, // keep playing
            startPos: 0, // start from beginning
			loop: 1, //loop
			doneAction: 0 // don't auto-free
        );
        sig * 0.4
    }.play;

    ^synth;
};

// List of sample classes
~waterClass = {
    ~playBufByName.("water")
};

~cityClass = {
    var synth;
    synth = {
        var sig, env;
        env = EnvGen.kr(Env.perc(0.1, 3), doneAction: 2);
        sig = WhiteNoise.ar(0.2) * env;
        sig = LPF.ar(sig, 2000);
        sig = sig + SinOsc.ar([100, 150, 200].choose, 0, 0.1) * env;
        sig = sig * 0.4;
        sig ! 2;
    }.play;
    "City sample playing".postln;
    synth;
};

~forestClass = {
    var synth;
    synth = {
        var sig, env;
        env = EnvGen.kr(Env.perc(0.05, 2.5), doneAction: 2);
        sig = BrownNoise.ar(0.15) * env;
        sig = BPF.ar(sig, LFNoise1.kr(1).range(500, 2000), 0.3);
        sig = sig + Dust.ar(5, 0.2) * env;
        sig = sig * 0.5;
        sig ! 2;
    }.play;
    "Forest sample playing".postln;
    synth;
};

~windClass = {
    var synth;
    synth = {
        var sig, env;
        env = EnvGen.kr(Env.perc(0.5, 4), doneAction: 2);
        sig = PinkNoise.ar(0.25) * env;
        sig = LPF.ar(sig, LFNoise1.kr(0.3).range(300, 1500));
        sig = sig * 0.45;
        sig ! 2;
    }.play;
    "Wind sample playing".postln;
    synth;
};

~calmClass = {
    var env = IdentityDictionary.new;

    env[\group] = Group.head(s);

    env[\pad]   = Synth.tail(env[\group], \calmPad,  [\amp, 0.18]);
    env[\noise] = Synth.tail(env[\group], \calmNoise, [\amp, 0.05]);

    env[\clock] = TempoClock.default;

	env[\plucks] = Pbind(
        \instrument, \calmPluck,
        \scale,      Scale.minor,
        \root,       0,
        \octave,     Pwrand([4, 5], [0.7, 0.3], inf),
        \degree,     Pwhite(0, 7, inf),
        \dur,        Pwhite(1.5, 4.0, inf),
        \rel,        Pwhite(4.0, 9.0, inf),
        \amp,        Pwhite(0.04, 0.10, inf)
    ).play(env[\clock], target: env[\group]);

    env.bells = Pbind(
        \instrument, \calmBell,
        \scale,      Scale.minor,
        \root,       -12,
        \octave,     Pwrand([5, 6], [0.8, 0.2], inf),
        \degree,     Pwhite(0, 7, inf),
        \dur,        Pwhite(6.0, 14.0, inf),
        \rel,        Pwhite(5.0, 12.0, inf),
        \amp,        Pwhite(0.03, 0.08, inf)
    ).play(env[\clock], target: env[\group]);

    env;  // returned & stored in ~classInstances["calm"]
};

// Map class names to their corresponding functions
~classMap = Dictionary.newFrom([
	// places
    "water", ~waterClass,
    "city", ~cityClass,
    "forest", ~forestClass,
    "wind", ~windClass,

	//moods
	"calm",  ~calmClass
]);

// OSC Responder
OSCdef(\classReceiver, {
    arg msg, time, addr, recvPort;
    var className;

    // Extract class name from OSC message
    className = msg[1].asString.toLower;

    ("Received OSC message: " ++ className).postln;

    // Check if class exists in our map
    if(~classMap.includesKey(className), {
        // Create instance and play sample
        ~classInstances[className] = ~classMap[className].value;
        ("Created instance of: " ++ className).postln;
    }, {
        ("Class not found: " ++ className).postln;
    });

}, '/class'); // OSC address pattern

"OSC Receiver ready on port 57120, listening to /class".postln;
"Send OSC messages with format: /class <classname>".postln;
"Available classes: water, city, forest, wind".postln;


// To test locally, uncomment and evaluate:
n = NetAddr("127.0.0.1", 57120);
n.sendMsg('/class', 'water');
n.sendMsg('/class', 'city');
n.sendMsg('/class', 'calm');


// Stopping

// To stop the OSC responder:
OSCdef(\classReceiver).free;

// To stop calm
// Add this new class definition
~stopCalmClass = {
    var calm = ~classInstances["calm"]; // Get the stored calm environment

    if(calm.notNil) {
        // Stop patterns if they exist
        calm[\plucks].tryPerform(\stop);
        calm[\bells].tryPerform(\stop);

        // Free group if it exists
        calm[\group].tryPerform(\free);

        // Remove from ~classInstances so it's not stopped again
        ~classInstances.removeAt("calm");

        "Calm system stopped.".postln;
    } {
        "No calm instance running to stop.".postln;
    };
};

~stopCalmClass.value;