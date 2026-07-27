# tracc
An XM and more module tracker for ComputerCraft 1.100+.

This branch splits the core into a separate library, which can be embedded into other programs.

![Screenshot](image.png)

## Usage
At least one speaker attached is required. If speakers are on both the left and right of the computer, they will be used for stereo output - otherwise, the module will play on one attached speaker in mono. (Note that stereo may affect performance on modules with many channels.)

To play a module, just run tracc with the path to the module file. Press Q to close the tracker while playing.

You can seek through the file with the left and right arrow keys. The P key will pause the module, and the up/down arrow keys will move the cursor up/down. A and D will scroll the channels left and right respectively, allowing viewing the rest of the channels. Number keys 1-9/0 will toggle mute on channels 1-10.

Note that the cursor will be a couple of rows ahead, due to how ComputerCraft's audio works. CraftOS-PC will not have this issue, however.

You may pass "linear" as a second argument to enable linear interpolation for samples. This will improve audio quality at the cost of speed/channel count.

## Module support
tracc can natively load most common module files in MOD/XM/S3M format plus some IT modules. It works best with XM modules with 20 channels or fewer, though larger modules are theoretically playable - normal CC is too slow to handle more channels. While tracc can load S3M and IT modules, the effects are converted to XM internally as this is the native effect set. S3M has fairly well-tested support for most modules, but IT is lacking many extended features which will likely not be implemented in this version of tracc.

## Embedding
The `libtracc` module can be used to play modules inside other programs, with or without visual output.

- Call one of the `libtracc.read[XM|S3M|IT|MOD]File` functions to load a module. This takes a file handle, and returns a state object, which holds all of the information required for playback.
  - Use `libtracc.makeFile` to turn string data into a usable file handle.
- For simple playback, call `libtracc.play` with the state, optional volume, and the speakers to play on. This is a blocking function, and will return once the module finishes (which may be never if `state.loop` is true, which is the default).
  - Put this function in a coroutine manager, like `parallel` or [Taskmaster](https://gist.github.com/MCJack123/1678fb2c240052f1480b07e9053d4537), to play while other code is running.
- For more advanced playback, the `libtracc.tick` and `libtracc.row` functions can be used to process each tick/row sequentially. These take the state, whether to use stereo output, and optional tables to fill, and return tables with the left/mono, right (if requested), and VU information (which is mainly for use in tracc). The sample tables can be sent directly to `speaker.playAudio`.
- You can use MIDI macros (an OpenMPT hack) to trigger functions in a program from the module. Set functions inside the `state.midiMacros.[parametered|fixed]` table - these are 0-indexed and take the state, channel object, and the parameter for parametered macros - and they'll be called on `Zxx` effects. See [the OpenMPT manual](https://wiki.openmpt.org/Manual:_Zxx_Macros) for more info on how MIDI macros work.

The `minitracc.lua` program shows how to use `libtracc` in a simple program.
