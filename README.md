# 3DO for MiSTer

## Status

Current status is WIP/Beta

Some games have popping and noise.


## Kanji ROM
Rename the kanji.bin file to kanji.rom and place it in the game folder or parent folder.

## Arcade
Build `3DO.qpf` for both console and arcade games. For MRA launches, put a
copy of that same RBF under `_Arcade/cores` and install the MRAs from
`releases/mra`. The MRAs need a MiSTer Main that keeps the BIOS loaded by the
MRA when the MRA mounts the disc.

Each MRA sends a game ID to the core as a one-byte ROM on index 16. The high
nibble selects the controls (`1` trackball, `2` lightgun) and the low nibble is
a per-game parameter: `0x10` Orbatak, `0x20` Shootout at Old Tucson, `0x21`
Mad Dog II (its lightgun aim origin). With a non-zero ID the OSD hides the
console options and shows the arcade ones: Orbatak shows its trackball input
selector; the lightgun games show both crosshair settings. Launched as a
console core (no MRA), the ID is `0` and only console options are shown. A new
game that uses the trackball, or a lightgun with one of these aim origins,
needs only an MRA with its ID.

Put `alg3do.zip` in `games/mame`. All three MRAs load `saot_rom2.bin` from it.
The discs are MAME's CHDs, in MAME's folder layout under `games/mame`. No CUE
sheet or `cd_bios.rom` is needed for these MRAs.

| Game | CHD path under `games/mame` |
| --- | --- |
| Orbatak | `orbatak/orbatak.chd` |
| Mad Dog II | `md23do/mad dog ii.chd` |
| Shootout at Old Tucson | `sht3do/shootout at old tucson.chd` |

Arcade backup RAM autosaves when the OSD opens, not when the core exits.
To save explicitly, select **Save Backup RAM** and let it finish before exiting.

## Official beta 
Rename the panafz1j-norsa.bin (for NTSC) or panafz1e-unencrypted.bin (for PAL) file to cd_bios.rom and place it in the game folder or parent folder.

## Changing disc (in a multi-disc game) 
When the game prompts you to change the disc, you need to save NVRAM. Then insert the next disc. 
