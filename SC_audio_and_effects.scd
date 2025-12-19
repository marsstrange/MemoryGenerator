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

    env[\bells] = Pbind(
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


// OSC Responder for STARTING sounds
OSCdef(\classStarter, {
    arg msg, time, addr, recvPort;
    var className = msg[1].asString.toLower;

    ("Received OSC /class: " ++ className).postln;

    if(~classMap.includesKey(className)) {
        // If already playing, stop it first to avoid overlapping
        if(~classInstances[className].notNil) {
            ~stopClass.(className);
        };

        ~classInstances[className] = ~classMap[className].value;
        ("Started: " ++ className).postln;
    } {
        ("Class not found: " ++ className).postln;
    };
}, '/class');

// OSC Responder for STOPPING sounds
~stopClass = { |name|
    var key  = name.asString.toLower;
    var inst = ~classInstances[key];

    if(inst.isNil) {
        ("Nothing running to stop for: " ++ key).postln;
        ^nil;
    };

    // Case 1: Complex (calm) - Dictionary/Environment with group + patterns
    if(inst.isKindOf(Dictionary) or: { inst.isKindOf(Environment) }) {
        // Stop patterns (plucks, bells)
        inst[\plucks] !? { inst[\plucks].stop };
        inst[\bells]  !? { inst[\bells].stop };

        // Free the entire group (kills pad, noise, and all pattern synths)
        inst[\group] !? { inst[\group].freeAll };

        ~classInstances.removeAt(key);
        ("Stopped complex: " ++ key).postln;
        ^inst;
    };

    // Case 2: Simple Synth (water, city, forest, wind)
    if(inst.isKindOf(Synth)) {
        inst.free;  // free the synth immediately
        ~classInstances.removeAt(key);
        ("Stopped sample: " ++ key).postln;
        ^inst;
    };

    // Case 3: Unknown - just try to free it
    inst.tryPerform(\free);
    ~classInstances.removeAt(key);
    ("Stopped (unknown type): " ++ key).postln;
    inst;
};

// The OSC Responder for /stop
// This is what actually "listens" for the command from Python
OSCdef(\classStopper, {
    arg msg, time, addr, recvPort;
    var className = msg[1].asString.toLower;

    ("Received OSC /stop: " ++ className).postln;

    // Call the function above
    ~stopClass.value(className);

}, '/stop');

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
//OSCdef(\classReceiver).free;

// Stop a specific sample:
n.sendMsg('/stop', 'water');  // Stop rain
n.sendMsg('/stop', 'calm');   // Stop calm

~classInstances.postln;
~classInstances["water"].postln;

x = ~waterClass.value;
x.postln;                  // should print a Synth