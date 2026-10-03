#pragma once
#include <flight/fdm/session.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/variant.hpp>
namespace flight::bridge {
fdm::c::ControlCommand decode_command(const godot::Dictionary& value);
fdm::c::SessionControl decode_session_control(const godot::Dictionary& value);
}
