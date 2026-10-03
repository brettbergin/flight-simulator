#include <flight/reconstruction/recipe.hpp>
#include <flight/fdm/model.hpp>
#include <bit>
#include <fstream>
#include <stdexcept>

namespace flight::reconstruction::proof {
namespace {
constexpr std::size_t limit = 4 * 1024 * 1024;
struct Writer {
  Bytes bytes;
  void integer(std::uint64_t value, unsigned count) {
    for(unsigned i=0;i<count;++i) bytes.push_back(static_cast<std::uint8_t>(value>>(8*i)));
  }
  void real(double value) { if(!std::isfinite(value)) throw std::invalid_argument("Nonfinite replay value"); integer(std::bit_cast<std::uint64_t>(value),8); }
  void text(const std::string& value) {
    if(value.empty()||value.size()>256) throw std::invalid_argument("Replay string bound");
    for(unsigned char ch:value) if(ch<32||ch>126) throw std::invalid_argument("Replay ASCII string");
    integer(value.size(),2); bytes.insert(bytes.end(),value.begin(),value.end());
  }
};
struct Reader {
  std::span<const std::uint8_t> bytes; std::size_t offset{};
  std::span<const std::uint8_t> take(std::size_t count) {
    if(count>bytes.size()-offset) throw std::invalid_argument("Truncated replay packet");
    auto result=bytes.subspan(offset,count);offset+=count;return result;
  }
  std::uint64_t integer(unsigned count) {std::uint64_t value=0;const auto data=take(count);for(unsigned i=0;i<count;++i)value|=std::uint64_t{data[i]}<<(8*i);return value;}
  double real() {const auto value=std::bit_cast<double>(integer(8));if(!std::isfinite(value))throw std::invalid_argument("Nonfinite replay value");return value;}
  std::string text() {
    const auto size=integer(2);if(size==0||size>256)throw std::invalid_argument("Replay string bound");
    const auto data=take(static_cast<std::size_t>(size));for(auto ch:data)if(ch<32||ch>126)throw std::invalid_argument("Replay ASCII string");
    return std::string(data.begin(),data.end());
  }
};
bool hash(const std::string& value) {return value.size()==64&&std::all_of(value.begin(),value.end(),[](char ch){return(ch>='0'&&ch<='9')||(ch>='a'&&ch<='f');});}
void valid_identity(const Identity& value) {
  for(std::size_t i=0;i<5;++i)if(!hash(value[i]))throw std::invalid_argument("Replay identity hash");
  for(std::size_t i=5;i<7;++i) {if(value[i].empty()||value[i].size()>256)throw std::invalid_argument("Replay build identity");for(unsigned char ch:value[i])if(ch<32||ch>126)throw std::invalid_argument("Replay build identity ASCII");}
}
void write_identity(Writer& writer,const Identity& value) {valid_identity(value);for(const auto& text:value)writer.text(text);}
Identity identity(Reader& reader) {Identity result;for(auto& text:result)text=reader.text();valid_identity(result);return result;}
void write_axes(Writer& writer,c::PilotAxes a) {for(double v:{a.roll,a.pitch,a.yaw,a.throttle,a.mixture,a.left_brake,a.right_brake,a.trim})writer.real(v);}
c::PilotAxes axes(Reader& reader) {return {reader.real(),reader.real(),reader.real(),reader.real(),reader.real(),reader.real(),reader.real(),reader.real()};}
void control_fields(Writer& w,const c::SampleHeader& h,c::Sequence seq,const std::string& source) {w.text(h.session_id);w.integer(h.tick.value,8);w.integer(seq.value,8);w.text(source);}
}
Bytes read_bounded(const std::filesystem::path& path) {
  const auto size=std::filesystem::file_size(path);if(size>limit)throw std::invalid_argument("Replay file bound");
  Bytes data(static_cast<std::size_t>(size));std::ifstream input(path,std::ios::binary);input.read(reinterpret_cast<char*>(data.data()),static_cast<std::streamsize>(size));if(!input)throw std::runtime_error("Replay file read");return data;
}
void write_checked(const std::filesystem::path& path,std::span<const std::uint8_t> bytes) {
  std::ofstream output(path,std::ios::binary|std::ios::trunc);output.write(reinterpret_cast<const char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));output.close();if(!output)throw std::runtime_error("Replay file write");
}
Identity read_identity(std::span<const std::uint8_t> bytes) {Reader reader{bytes};auto value=identity(reader);if(reader.offset!=bytes.size())throw std::invalid_argument("Identity trailing bytes");return value;}
void validate(const Recipe& recipe) {
  valid_identity(recipe.identity);
  if(recipe.initial_request.empty()||recipe.initial_request.size()>limit||recipe.checkpoint_tick.value>72000||recipe.checkpoint_tick.value==0||recipe.admissions.empty()||recipe.admissions.size()>4096)throw std::invalid_argument("Replay recipe bounds");
  c::Tick previous{};
  for(const auto& record:recipe.admissions) {
    if(record.received_after_tick<previous||record.received_after_tick>recipe.checkpoint_tick)throw std::invalid_argument("Replay admission order");previous=record.received_after_tick;
    if(const auto* registration=std::get_if<Registration>(&record.input)) {
      if(!c::stable_id(registration->source_id)||registration->authority>c::Authority::instructor)throw std::invalid_argument("Replay registration");
    } else if(const auto* command=std::get_if<c::ControlCommand>(&record.input)) {
      const auto* a=std::get_if<c::PilotAxes>(&command->payload);
      if(!c::stable_id(command->header.session_id)||!c::stable_id(command->source_id)||command->authority>c::Authority::instructor||!a||!c::valid(*a)||a->mixture!=1||a->left_brake!=0||a->right_brake!=0||command->assistance.profile_id!="unassisted"||!command->assistance.active.empty()||command->header.tick.value<=record.received_after_tick.value||command->header.tick.value>144000)throw std::invalid_argument("Unsupported replay command");
    } else {
      const auto& control=std::get<c::SessionControl>(record.input);
      if(!c::stable_id(control.header.session_id)||!c::stable_id(control.source_id)||control.header.tick!=record.received_after_tick)throw std::invalid_argument("Replay lifecycle boundary");
      if(const auto* scale=std::get_if<c::TimeScaleControl>(&control.payload))if(scale->scale!=.25&&scale->scale!=.5&&scale->scale!=1&&scale->scale!=2&&scale->scale!=4)throw std::invalid_argument("Replay scale");
    }
  }
  const auto* final=std::get_if<c::SessionControl>(&recipe.admissions.back().input);
  const auto* pause=final?std::get_if<c::PauseControl>(&final->payload):nullptr;
  if(!pause||!pause->paused||final->header.tick!=recipe.checkpoint_tick)throw std::invalid_argument("Only canonical paused fixed-step boundary supported");
}
Bytes encode(const Recipe& recipe) {
  validate(recipe);Writer w;for(char ch:std::string("FSRPLY01"))w.bytes.push_back(static_cast<std::uint8_t>(ch));w.integer(1,4);write_identity(w,recipe.identity);
  w.integer(recipe.checkpoint_tick.value,8);w.integer(recipe.initial_request.size(),4);w.bytes.insert(w.bytes.end(),recipe.initial_request.begin(),recipe.initial_request.end());w.integer(recipe.admissions.size(),4);
  for(const auto& record:recipe.admissions) {
    w.integer(record.received_after_tick.value,8);
    if(const auto* reg=std::get_if<Registration>(&record.input)) {w.integer(0,1);w.text(reg->source_id);w.integer(static_cast<std::uint8_t>(reg->authority),1);}
    else if(const auto* command=std::get_if<c::ControlCommand>(&record.input)) {w.integer(1,1);control_fields(w,command->header,command->sequence,command->source_id);w.integer(static_cast<std::uint8_t>(command->authority),1);write_axes(w,std::get<c::PilotAxes>(command->payload));}
    else {
      const auto& control=std::get<c::SessionControl>(record.input);const auto* pause=std::get_if<c::PauseControl>(&control.payload);
      w.integer(pause?2:3,1);control_fields(w,control.header,control.sequence,control.source_id);if(pause)w.integer(pause->paused?1:0,1);else w.real(std::get<c::TimeScaleControl>(control.payload).scale);
    }
  }
  if(w.bytes.size()>limit-64)throw std::invalid_argument("Replay packet bound");const auto checksum=f::sha256(w.bytes);w.bytes.insert(w.bytes.end(),checksum.begin(),checksum.end());return w.bytes;
}
Recipe decode(std::span<const std::uint8_t> bytes,const Identity& expected) {
  valid_identity(expected);if(bytes.size()<76||bytes.size()>limit)throw std::invalid_argument("Replay packet bound");
  const auto payload=bytes.first(bytes.size()-64);const auto digest=bytes.last(64);
  if(f::sha256(payload)!=std::string(digest.begin(),digest.end()))throw std::invalid_argument("Replay checksum mismatch");
  Reader r{payload};const auto magic=r.take(8);if(std::string(magic.begin(),magic.end())!="FSRPLY01"||r.integer(4)!=1)throw std::invalid_argument("Unsupported replay version");
  Recipe recipe;recipe.identity=identity(r);if(recipe.identity!=expected)throw std::invalid_argument("Incompatible replay identity");
  recipe.checkpoint_tick={r.integer(8)};const auto size=r.integer(4);const auto request=r.take(static_cast<std::size_t>(size));recipe.initial_request.assign(request.begin(),request.end());
  const auto count=r.integer(4);if(count>4096)throw std::invalid_argument("Replay admission bound");
  for(std::uint64_t i=0;i<count;++i) {
    const c::Tick received{r.integer(8)};const auto kind=r.integer(1);
    if(kind==0) {auto source=r.text();const auto authority=r.integer(1);recipe.admissions.push_back({received,Registration{std::move(source),static_cast<c::Authority>(authority)}});}
    else if(kind>=1&&kind<=3) {
      auto session=r.text();const c::Tick tick{r.integer(8)};const c::Sequence seq{r.integer(8)};auto source=r.text();
      if(kind==1) {const auto authority=r.integer(1);auto a=axes(r);recipe.admissions.push_back({received,c::ControlCommand{{tick,std::move(session)},seq,std::move(source),static_cast<c::Authority>(authority),{"unassisted",{}},a}});}
      else {c::SessionControl control{{tick,std::move(session)},seq,std::move(source),c::PauseControl{false}};if(kind==2) {const auto flag=r.integer(1);if(flag>1)throw std::invalid_argument("Replay pause flag");control.payload=c::PauseControl{flag==1};}else control.payload=c::TimeScaleControl{r.real()};recipe.admissions.push_back({received,std::move(control)});}
    } else throw std::invalid_argument("Replay operation kind");
  }
  if(r.offset!=payload.size())throw std::invalid_argument("Replay trailing bytes");validate(recipe);return recipe;
}
f::SessionConfig configuration(const Recipe& recipe,const std::filesystem::path& root) {
  validate(recipe);auto request=f::transport::decode(recipe.initial_request,root);
  if(!request.commands.empty()||request.config.clock.tick_rate_hz!=120||request.config.clock.purpose!=c::ClockPurpose::runtime||request.duration_ticks!=recipe.checkpoint_tick.value)throw std::invalid_argument("Unsupported replay initial recipe");
  request.config.future_horizon_ticks=144000;return request.config;
}
void admit(f::Session& session,const Admission& record) {
  if(session.latest_snapshot().header.tick!=record.received_after_tick)throw std::invalid_argument("Replay receiving boundary mismatch");
  if(const auto* registration=std::get_if<Registration>(&record.input)) {if(!session.register_host_source(registration->source_id,registration->authority))throw std::invalid_argument("Replay registration rejected");}
  else if(const auto* command=std::get_if<c::ControlCommand>(&record.input)) {if(!session.submit(*command).queued)throw std::invalid_argument("Replay command rejected");}
  else if(session.apply(std::get<c::SessionControl>(record.input))!=c::SessionControlRejection::none)throw std::invalid_argument("Replay lifecycle rejected");
}
} // namespace flight::reconstruction::proof
