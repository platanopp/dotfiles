import QtQuick
import qs.config

// The shell's spring: a NumberAnimation that runs a little past its target
// and settles back (see Theme's springs for when to use it, and when not).
//
//   Behavior on x { Elastic {} }              panels, cards, overlays
//   Behavior on x { Elastic { small: true } } knobs, indicators, chips
//
// Spatial properties only: never opacity, which cannot go past 1, nor a size
// that is shrinking towards nothing, which would overshoot below zero.
NumberAnimation {
    property bool small: false

    duration: small ? Theme.durSpringSmall : Theme.durSpring
    easing.type: Easing.OutBack
    easing.overshoot: small ? Theme.springOvershootSmall : Theme.springOvershoot
}
