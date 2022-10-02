
# Rationale

Just a Sunday afternood fun. This code runs on a Raspberry Pi with Tinkerforge, Hifi-Berry AMP and a lot of recycled
hardware (TV parts, old router power plug, ...).
The speaker binds NFC Chips with songs.

# Dependencies

```bash
apt install libportaudiocpp0 portaudio19-dev libmpg123-dev
```

# Bashrc

Add this to your `.bashrc` to enable ro/rw filesystem and limit the sdcard wearing.
The system must be prepared for that, there is various documentation to achieve a read-only fs
on the raspberry pi. For instance:

- https://hallard.me/raspberry-pi-read-only/
- https://medium.com/@andreas.schallwig/how-to-make-your-raspberry-pi-file-system-read-only-raspbian-stretch-80c0f7be7353

to link just few.


```bash
set_bash_prompt() {
  fs_mode=$(mount | sed -n -e "s/^\/dev\/.* on \/ .*(\(r[w|o]\).*/\1/p")
  PS1='\[\033[01;32m\]\u@\h${fs_mode:+($fs_mode)}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
}
alias ro='sudo mount -o remount,ro / ; sudo mount -o remount,ro /boot'
alias rw='sudo mount -o remount,rw / ; sudo mount -o remount,rw /boot'
PROMPT_COMMAND=set_bash_prompt
```

Hit `rw` in your ssh console to remount the root filesystem as read-write.