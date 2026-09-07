import asyncio
import os
import signal
import subprocess

from evdev import InputDevice, UInput, ecodes, list_devices


# "sunshine" is here for the pads Sunshine makes when a stream starts. It
# names them by the console it is emulating -- "Sunshine X-Box One (virtual)
# pad", but also PS5, Nintendo -- and only the Xbox one would have matched the
# hints below. The button codes are the same whichever it picks.
CONTROLLER_NAME_HINTS = ("xbox", "x-box", "microsoft", "sunshine")

# Any one of these means the device has a face button, so it is the pad itself
# and not something bundled alongside it. BTN_SOUTH and BTN_A are the same
# code; the pair below covers both the Xbox and the DualShock naming.
GAMEPAD_BUTTONS = (ecodes.BTN_SOUTH, ecodes.BTN_EAST, ecodes.BTN_START, ecodes.BTN_MODE)
STICK_DEADZONE = 0.15
MOUSE_SENSITIVITY = 18
MOUSE_POLL_HZ = 60
SCROLL_SENSITIVITY = 4
SCROLL_POLL_HZ = 20
TRIGGER_THRESHOLD = 0.5
TERMINAL_COMMAND = "kitty"

# This runs for the length of the session, not the length of a stream, so a pad
# that is not there yet is the normal state and not a failure. It waits, and it
# goes back to waiting when one is unplugged -- which includes the end of a
# Sunshine stream, since Sunshine deletes the pad it made.
CONTROLLER_POLL_SECONDS = 0.5

# Where the shell reads the mode from. Written on every change and watched by
# AppState, so the control panel's tile follows a toggle made on the pad, and
# SIGUSR1 (which the tile sends) drives the same toggle the pad does. One piece
# of state, both ends looking at it.
#
#   waiting   running, but no controller is plugged in
#   off       controller present, acting as a plain gamepad
#   on        controller present, driving the desktop
STATE_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gamepad-mode.state")


class GamepadState:
    def __init__(self):
        self.controller_present = False
        self.control_mode_active = False
        self.left_bumper_held = False
        self.left_thumb_held = False
        self.right_thumb_held = False
        self.toggle_combo_fired = False
        self.stick_x = 0.0
        self.stick_y = 0.0
        self.right_stick_x = 0.0
        self.right_stick_y = 0.0
        self.left_trigger_pressed = False
        self.right_trigger_pressed = False

    def forget_inputs(self):
        # Called when a pad is picked up. Everything above except the mode is a
        # reading from the last pad, and a stick left off-centre when a stream
        # ended would otherwise still be pushing the cursor when the next one
        # connects.
        self.left_bumper_held = False
        self.left_thumb_held = False
        self.right_thumb_held = False
        self.toggle_combo_fired = False
        self.stick_x = 0.0
        self.stick_y = 0.0
        self.right_stick_x = 0.0
        self.right_stick_y = 0.0
        self.left_trigger_pressed = False
        self.right_trigger_pressed = False


def find_controller():
    # Every device it opens and rejects gets closed again. This used to run
    # once at startup, where leaking the descriptors cost nothing; it runs
    # twice a second for the length of the session now.
    for path in list_devices():
        try:
            device = InputDevice(path)
        except OSError:
            continue
        if is_controller(device):
            return device
        device.close()
    return None


def is_controller(device):
    if not any(hint in device.name.lower() for hint in CONTROLLER_NAME_HINTS):
        return False
    capabilities = device.capabilities()
    absolute_axes = [code for code, _ in capabilities.get(ecodes.EV_ABS, [])]
    if ecodes.ABS_X not in absolute_axes or ecodes.ABS_Y not in absolute_axes:
        return False
    # Sticks alone are not enough to tell a pad from the motion sensors that
    # come with it: an accelerometer reports on ABS_X and ABS_Y too. Sunshine
    # publishes both under one name -- more of them since it moved to
    # libvirtualhid -- so the buttons are what separates them.
    buttons = capabilities.get(ecodes.EV_KEY, [])
    return any(code in buttons for code in GAMEPAD_BUTTONS)


def create_virtual_mouse():
    capabilities = {
        ecodes.EV_REL: [ecodes.REL_X, ecodes.REL_Y, ecodes.REL_WHEEL, ecodes.REL_HWHEEL],
        ecodes.EV_KEY: [ecodes.BTN_LEFT, ecodes.BTN_RIGHT],
    }
    return UInput(capabilities, name="gamepad-virtual-mouse")


def normalize_axis(value, info):
    axis_range = info.max - info.min
    center = info.min + axis_range / 2
    normalized = (value - center) / (axis_range / 2)
    if abs(normalized) < STICK_DEADZONE:
        return 0.0
    return max(-1.0, min(1.0, normalized))


def normalize_trigger(value, info):
    axis_range = info.max - info.min
    if axis_range == 0:
        return 0.0
    return (value - info.min) / axis_range


def run_hyprland_dispatch(lua_expression):
    subprocess.Popen(["hyprctl", "dispatch", lua_expression])


def send_notification(message):
    subprocess.Popen(["notify-send", "-a", "Modo mando", "-i", "input-gaming", message])


def write_state(value):
    # Written whole and moved into place: the shell watches this file, and a
    # half-written one would read back as an empty mode.
    temporary = f"{STATE_PATH}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(f"{value}\n")
    os.replace(temporary, STATE_PATH)


def remove_state():
    try:
        os.unlink(STATE_PATH)
    except FileNotFoundError:
        pass


def set_control_mode(state, active):
    if state.control_mode_active == active:
        return
    state.control_mode_active = active
    status = "activado" if active else "desactivado"
    print(f"Modo mando {status}", flush=True)
    write_state("on" if active else "off")
    send_notification(f"Modo mando {status}")


def toggle_control_mode(state):
    # Reachable with nothing plugged in, over SIGUSR1 from the control panel's
    # tile. There is no mode to be in without a pad, so say so rather than
    # flipping a switch that drives nothing.
    if not state.controller_present:
        print("No hay mando conectado", flush=True)
        send_notification("No hay mando conectado")
        return
    set_control_mode(state, not state.control_mode_active)


def handle_toggle_combo(state):
    both_held = state.left_thumb_held and state.right_thumb_held
    if both_held and not state.toggle_combo_fired:
        toggle_control_mode(state)
        state.toggle_combo_fired = True
    elif not both_held:
        state.toggle_combo_fired = False


def handle_action_combo(state, button_code):
    if not state.control_mode_active or not state.left_bumper_held:
        return
    if button_code == ecodes.BTN_SOUTH:
        run_hyprland_dispatch(f'hl.dsp.exec_cmd("{TERMINAL_COMMAND}")')
    elif button_code == ecodes.BTN_EAST:
        run_hyprland_dispatch("hl.dsp.window.close()")
    elif button_code == ecodes.BTN_NORTH:
        # The shell's own launcher, over Hyprland's global-shortcuts protocol.
        # This used to exec walker, which is not installed on this machine --
        # the button did nothing at all.
        run_hyprland_dispatch('hl.dsp.global("quickshell:launcher")')


async def move_mouse_loop(virtual_mouse, state):
    interval = 1 / MOUSE_POLL_HZ
    while True:
        if state.control_mode_active and (state.stick_x or state.stick_y):
            delta_x = round(state.stick_x * MOUSE_SENSITIVITY)
            delta_y = round(state.stick_y * MOUSE_SENSITIVITY)
            if delta_x:
                virtual_mouse.write(ecodes.EV_REL, ecodes.REL_X, delta_x)
            if delta_y:
                virtual_mouse.write(ecodes.EV_REL, ecodes.REL_Y, delta_y)
            virtual_mouse.syn()
        await asyncio.sleep(interval)


async def scroll_loop(virtual_mouse, state):
    interval = 1 / SCROLL_POLL_HZ
    while True:
        if state.control_mode_active and (state.right_stick_x or state.right_stick_y):
            delta_vertical = round(-state.right_stick_y * SCROLL_SENSITIVITY)
            delta_horizontal = round(state.right_stick_x * SCROLL_SENSITIVITY)
            if delta_vertical:
                virtual_mouse.write(ecodes.EV_REL, ecodes.REL_WHEEL, delta_vertical)
            if delta_horizontal:
                virtual_mouse.write(ecodes.EV_REL, ecodes.REL_HWHEEL, delta_horizontal)
            virtual_mouse.syn()
        await asyncio.sleep(interval)


async def read_controller_events(device, virtual_mouse, state):
    left_stick_x_info = device.absinfo(ecodes.ABS_X)
    left_stick_y_info = device.absinfo(ecodes.ABS_Y)
    right_stick_x_info = device.absinfo(ecodes.ABS_RX)
    right_stick_y_info = device.absinfo(ecodes.ABS_RY)
    left_trigger_info = device.absinfo(ecodes.ABS_Z)
    right_trigger_info = device.absinfo(ecodes.ABS_RZ)

    async for event in device.async_read_loop():
        if event.type == ecodes.EV_ABS:
            if event.code == ecodes.ABS_X:
                state.stick_x = normalize_axis(event.value, left_stick_x_info)
            elif event.code == ecodes.ABS_Y:
                state.stick_y = normalize_axis(event.value, left_stick_y_info)
            elif event.code == ecodes.ABS_RX:
                state.right_stick_x = normalize_axis(event.value, right_stick_x_info)
            elif event.code == ecodes.ABS_RY:
                state.right_stick_y = normalize_axis(event.value, right_stick_y_info)
            elif event.code == ecodes.ABS_Z:
                pressed = normalize_trigger(event.value, left_trigger_info) > TRIGGER_THRESHOLD
                if pressed != state.left_trigger_pressed:
                    state.left_trigger_pressed = pressed
                    if state.control_mode_active:
                        virtual_mouse.write(ecodes.EV_KEY, ecodes.BTN_RIGHT, 1 if pressed else 0)
                        virtual_mouse.syn()
            elif event.code == ecodes.ABS_RZ:
                pressed = normalize_trigger(event.value, right_trigger_info) > TRIGGER_THRESHOLD
                if pressed != state.right_trigger_pressed:
                    state.right_trigger_pressed = pressed
                    if state.control_mode_active:
                        virtual_mouse.write(ecodes.EV_KEY, ecodes.BTN_LEFT, 1 if pressed else 0)
                        virtual_mouse.syn()
            elif event.code == ecodes.ABS_HAT0X and state.control_mode_active:
                if event.value == -1:
                    run_hyprland_dispatch('hl.dsp.focus({ workspace = "-1" })')
                elif event.value == 1:
                    run_hyprland_dispatch('hl.dsp.focus({ workspace = "+1" })')
        elif event.type == ecodes.EV_KEY:
            pressed = event.value == 1
            if event.code == ecodes.BTN_TL:
                state.left_bumper_held = pressed
            elif event.code == ecodes.BTN_THUMBL:
                state.left_thumb_held = pressed
                handle_toggle_combo(state)
            elif event.code == ecodes.BTN_THUMBR:
                state.right_thumb_held = pressed
                handle_toggle_combo(state)
            elif pressed:
                handle_action_combo(state, event.code)


async def await_controller():
    while True:
        device = find_controller()
        if device is not None:
            return device
        await asyncio.sleep(CONTROLLER_POLL_SECONDS)


async def run_session(device, virtual_mouse, state):
    print(f"Mando detectado: {device.name}", flush=True)
    state.forget_inputs()
    state.controller_present = True
    write_state("off")
    send_notification("Mando conectado. L3 + R3 para el modo mando")

    tasks = [
        asyncio.ensure_future(read_controller_events(device, virtual_mouse, state)),
        asyncio.ensure_future(move_mouse_loop(virtual_mouse, state)),
        asyncio.ensure_future(scroll_loop(virtual_mouse, state)),
    ]
    try:
        # The reader is the only one of the three that ever finishes, and it
        # finishes by raising when the pad is unplugged. The two writer loops
        # would spin forever, so the first result ends the session either way.
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in tasks:
            if task.done() and not task.cancelled():
                task.result()
    except OSError:
        # The pad went away underneath us -- the normal end of a stream, since
        # Sunshine deletes the device it made. Not an error to report as one.
        print("El mando se desconecto", flush=True)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        set_control_mode(state, False)
        state.controller_present = False
        try:
            device.close()
        except OSError:
            pass


async def main():
    state = GamepadState()
    stopping = asyncio.Event()
    loop = asyncio.get_running_loop()

    # Armed before anything slow. SIGUSR1 is the control panel's way in --
    # `gamepad-mode.sh toggle` sends it, and it lands on the same switch L3 + R3
    # flips -- and creating the uinput device below takes a full two seconds,
    # which is two seconds of the tile doing nothing but killing the service on
    # the default disposition.
    loop.add_signal_handler(signal.SIGUSR1, lambda: toggle_control_mode(state))
    loop.add_signal_handler(signal.SIGTERM, stopping.set)

    # One uinput device for the life of the daemon. Recreating it per pad would
    # leave the compositor rediscovering a mouse every time a stream ends.
    virtual_mouse = create_virtual_mouse()

    async def sessions():
        while True:
            write_state("waiting")
            device = await await_controller()
            await run_session(device, virtual_mouse, state)

    work = asyncio.ensure_future(sessions())
    stop = asyncio.ensure_future(stopping.wait())
    try:
        await asyncio.wait([work, stop], return_when=asyncio.FIRST_COMPLETED)
        if work.done():
            work.result()
    finally:
        work.cancel()
        stop.cancel()
        await asyncio.gather(work, stop, return_exceptions=True)
        virtual_mouse.close()
        # Nothing is mapping anything any more, and the shell reads this file
        # rather than asking systemd.
        remove_state()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
