#include "codec.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <initializer_list>
#include <stdexcept>
namespace flight::bridge {
namespace {
using godot::Dictionary; using godot::Variant; using godot::String;
void keys(const Dictionary& value,std::initializer_list<const char*> expected) {
  if(value.size()!=static_cast<int64_t>(expected.size())) throw std::invalid_argument("Unknown/missing wire fields");
  for(auto key:expected) if(!value.has(key)) throw std::invalid_argument("Missing wire field");
}
std::string text(const Dictionary& value,const char* key) {
  const Variant field=value[key];
  if(field.get_type()!=Variant::STRING) throw std::invalid_argument("Wire string required");
  const auto utf8=static_cast<String>(field).utf8();
  if(utf8.length()>128) throw std::invalid_argument("Wire string exceeds bound");
  return std::string(utf8.get_data(),static_cast<std::size_t>(utf8.length()));
}
std::uint64_t integer(const Dictionary& value,const char* key) {
  const auto parsed=fdm::c::parse_uint64(text(value,key));
  if(!parsed) throw std::invalid_argument("Canonical uint64 string required");
  return *parsed;
}
Dictionary object(const Dictionary& value,const char* key) {
  const Variant field=value[key];
  if(field.get_type()!=Variant::DICTIONARY) throw std::invalid_argument("Wire object required");
  return field;
}
double number(const Dictionary& value,const char* key) {
  const Variant field=value[key];
  if(field.get_type()!=Variant::FLOAT&&field.get_type()!=Variant::INT) throw std::invalid_argument("Wire finite number required");
  const auto result=static_cast<double>(field);
  if(!std::isfinite(result)) throw std::invalid_argument("Wire finite number required");
  return result;
}
bool boolean(const Dictionary& value,const char* key) {
  const Variant field=value[key];
  if(field.get_type()!=Variant::BOOL) throw std::invalid_argument("Wire boolean required");
  return field;
}
void version(const Dictionary& value,const char* type) {
  const Variant field=value["schema_version"];
  if(field.get_type()!=Variant::INT||static_cast<int64_t>(field)!=1||text(value,"type")!=type) throw std::invalid_argument("Unsupported wire type/version");
}
fdm::c::SampleHeader header(const Dictionary& value) {
  auto session=text(value,"session_id");
  if(!fdm::c::stable_id(session)) throw std::invalid_argument("Invalid session identifier");
  return {{integer(value,"tick")},std::move(session)};
}
}
fdm::c::ControlCommand decode_command(const Dictionary& value) {
  keys(value,{"type","schema_version","tick","session_id","sequence","source_id","authority","assistance","payload"}); version(value,"ControlCommand");
  fdm::c::ControlCommand command;
  command.header=header(value); command.sequence={integer(value,"sequence")}; command.source_id=text(value,"source_id");
  // This host exposes one registered pilot source. It cannot self-elevate authority.
  if(command.source_id!="pilot.controls"||text(value,"authority")!="pilot") throw std::invalid_argument("Unregistered authority/source");
  const auto assistance=object(value,"assistance"); keys(assistance,{"profile_id","active"});
  command.assistance.profile_id=text(assistance,"profile_id");
  const Variant active=assistance["active"];
  if(command.assistance.profile_id!="unassisted"||active.get_type()!=Variant::ARRAY||static_cast<godot::Array>(active).size()!=0) throw std::invalid_argument("Unsupported assistance");
  const auto payload=object(value,"payload");
  if(text(payload,"kind")!="axes") throw std::invalid_argument("Unsupported pilot payload");
  keys(payload,{"kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"});
  fdm::c::PilotAxes axes{number(payload,"roll"),number(payload,"pitch"),number(payload,"yaw"),number(payload,"throttle"),
    number(payload,"mixture"),number(payload,"left_brake"),number(payload,"right_brake"),number(payload,"trim")};
  if(!fdm::c::valid(axes)) throw std::invalid_argument("Invalid pilot axes");
  command.payload=axes; return command;
}
fdm::c::SessionControl decode_session_control(const Dictionary& value) {
  keys(value,{"type","schema_version","tick","session_id","sequence","source_id","payload"}); version(value,"SessionControl");
  fdm::c::SessionControl control;
  control.header=header(value); control.sequence={integer(value,"sequence")}; control.source_id=text(value,"source_id");
  if(control.source_id!="session.owner") throw std::invalid_argument("Unregistered lifecycle owner");
  const auto payload=object(value,"payload"); const auto kind=text(payload,"kind");
  if(kind=="pause") { keys(payload,{"kind","paused"}); control.payload=fdm::c::PauseControl{boolean(payload,"paused")}; }
  else if(kind=="time_scale") { keys(payload,{"kind","scale"}); control.payload=fdm::c::TimeScaleControl{number(payload,"scale")}; }
  else throw std::invalid_argument("Unsupported session control");
  return control;
}
}
