import asyncio
import subprocess
import sys
import time

from evdev import InputDevice, UInput, ecodes, list_devices


# "sunshine" is here for the pads Sunshine makes when a stream starts. It
# names them by the console it is emulating -- "Sunshine X-Box One (virtual)
# pad", but also PS5, Nintendo -- and only the Xbox one would have matched the
# hints below. The button codes are the same whichever it picks.
CONTROLLER_NAME_HINTS = ("xbox", "x-box", "microsoft", "sunshine")
STICK_DEADZONE = 0.15
MOUSE_SENSITIVITY = 18
MOUSE_POLL_HZ = 60
SCROLL_SENSITIVITY = 4
SCROLL_POLL_HZ = 20
TRIGGER_THRESHOLD = 0.5
TERMINAL_COMMAND = "kitty"

# The pad does not exist yet when Sunshine runs its prep commands -- it is
# created with the stream, a moment later. Waiting is the difference between
# this starting and this exiting before the controller shows up.
CONTROLLER_WAIT_SECONDS = 30
CONTROLLER_POLL_SECONDS = 0.5


class GamepadState:
    def __init__(self):
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


def find_controller():
    for path in list_devices():
        device = InputDevice(path)
        name = device.name.lower()
        if not any(hint in name for hint in CONTROLLER_NAME_HINTS):
            continue
        capabilities = device.capabilities()
        absolute_axes = [code for code, _ in capabilities.get(ecodes.EV_ABS, [])]
        if ecodes.ABS_X in absolute_axes and ecodes.ABS_Y in absolute_axes:
            return device
    return None


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


def toggle_control_mode(state):
    state.control_mode_active = not state.control_mode_active
    status = "activado" if state.control_mode_active else "desactivado"
    print(f"Modo mando {status}")
    send_notification(f"Modo mando {status}")


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
    deadline = time.monotonic() + CONTROLLER_WAIT_SECONDS
    while True:
        device = find_controller()
        if device is not None:
            return device
        if time.monotonic() >= deadline:
            return None
        await asyncio.sleep(CONTROLLER_POLL_SECONDS)


async def main():
    device = await await_controller()
    if device is None:
        print("No se encontro un mando conectado")
        send_notification("No se encontro un mando")
        sys.exit(1)

    print(f"Mando detectado: {device.name}")
    send_notification("Mando conectado. L3 + R3 para el modo mando")
    virtual_mouse = create_virtual_mouse()
    state = GamepadState()

    try:
        await asyncio.gather(
            read_controller_events(device, virtual_mouse, state),
            move_mouse_loop(virtual_mouse, state),
            scroll_loop(virtual_mouse, state),
        )
    except OSError:
        # The pad went away underneath us -- which is the normal end of a
        # stream, since Sunshine deletes the device it made. Not an error to
        # report as one.
        print("El mando se desconecto")
    finally:
        if state.control_mode_active:
            send_notification("Modo mando desactivado")


if __name__ == "__main__":
    asyncio.run(main())
