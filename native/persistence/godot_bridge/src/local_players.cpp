// Original MIT. Direct Variant admission; no caller object crosses the worker.
#include "local_players.hpp"
#include "flight/local_players/windows_filesystem.hpp"
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <algorithm>
#include <array>
#include <bit>
#include <charconv>
#include <cmath>
#include <cstring>
#include <limits>

namespace flight::local_players::bridge {
namespace {
using godot::Array; using godot::Dictionary; using godot::String;
using godot::Variant;
static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559&&std::numeric_limits<double>::digits==53);
String gs(std::string_view s) {return String::utf8(s.data(),static_cast<std::int64_t>(s.size()));}
bool is(const Variant& v,std::string_view s) {
 if(v.get_type()!=Variant::STRING)return false;
 const String t=v;
 if(t.length()!=static_cast<std::int64_t>(s.size()))return false;
 for(std::size_t i=0;i<s.size();++i)if(t.unicode_at(i)!=static_cast<unsigned char>(s[i]))return false;
 return true;
}
bool is_null(const Variant& v) {return v.get_type()==Variant::NIL;}
bool one_of(const Variant& v,std::initializer_list<std::string_view> names) {
 for(const auto n:names)if(is(v,n))return true;
 return false;
}
template<class F> bool each_key(const Variant& v,F&& f) {
 Variant it; bool valid=false;
 bool more=v.iter_init(it,valid); if(!valid)return false;
 while(more) {
  Variant key=v.iter_get(it,valid);if(!valid||!f(key))return false;
  more=v.iter_next(it,valid);if(!valid)return false;
 }
 return true;
}
bool closed(const Variant& v,std::initializer_list<std::string_view> keys) {
 if(v.get_type()!=Variant::DICTIONARY)return false;
 const Dictionary d=v;if(d.size()!=static_cast<std::int64_t>(keys.size()))return false;
 return each_key(v,[&](const Variant& k){
  if(k.get_type()!=Variant::STRING)return false;
  for(auto s:keys)if(is(k,s))return true;
  return false;
 });
}
// UTF8 is written directly to a caller-supplied span. No CharString or native
// string mirror. C0 is preserved here; the closed field validator owns legality.
Error utf8(const String& s,std::span<char> out,std::size_t& used,
           std::size_t byte_limit=4096,std::size_t scalar_limit=4096) noexcept {
 used=0;
 if(s.length()<0||static_cast<std::uint64_t>(s.length())>scalar_limit)return Error::payload_limit;
 for(std::int64_t i=0;i<s.length();++i) {
  const auto cp=static_cast<std::uint32_t>(s.unicode_at(i));
  if(cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff))return Error::invalid_record;
  const std::size_t n=cp<0x80?1:cp<0x800?2:cp<0x10000?3:4;
  if(n>byte_limit-used)return Error::payload_limit;
  if(n>out.size()-used)return Error::out_of_memory;
  if(n==1)out[used++]=static_cast<char>(cp);
  else {
   out[used++]=static_cast<char>((n==2?0xc0:n==3?0xe0:0xf0)|(cp>>(6*(n-1))));
   for(std::size_t j=n-1;j>0;--j)out[used++]=static_cast<char>(0x80|((cp>>(6*(j-1)))&63));
  }
 }
 return Error::none;
}
bool bounded_text(const Variant& v,std::span<char> out,std::size_t& used) {
 return v.get_type()==Variant::STRING&&utf8(String(v),out,used)==Error::none;
}
bool kind_of(const Variant& v,JobKind& out) {
 for(unsigned i=0;i<=static_cast<unsigned>(JobKind::delete_recovery);++i) {
  auto k=static_cast<JobKind>(i);if(is(v,kind_name(k))){out=k;return true;}
 }
 return false;
}
bool physical_key(const Variant& v) {
 std::int64_t code=0;
 if(v.get_type()==Variant::INT)code=static_cast<std::int64_t>(v);
 else if(v.get_type()==Variant::FLOAT) {
  double n=v;if(!finite_binary64(n)||n<32||n>2147483647.0||std::trunc(n)!=n)return false;
  code=static_cast<std::int64_t>(n);
 } else return false;
 if(code<32||code>2147483647||code==godot::KEY_UNKNOWN||code==godot::KEY_NONE)return false;
 const auto* os=godot::OS::get_singleton();if(!os)return false;
 const auto key=static_cast<godot::Key>(code);
 return os->find_keycode_from_string(os->get_keycode_string(key))==key;
}

class Capture final : public AdmissionSource {
 public:
  explicit Capture(const Variant& v):value_(v){}
  Error outer_kind(JobKind& out) const noexcept override {
   if(value_.get_type()!=Variant::DICTIONARY)return Error::invalid_type;
   const Dictionary d=value_;
   if(d.size()!=2)return Error::invalid_request;
   bool string_keys=true;
   if(!each_key(value_,[&](const Variant& k){if(k.get_type()!=Variant::STRING)string_keys=false;return true;}))return Error::invalid_type;
   if(!string_keys)return Error::invalid_type;
   if(!d.has("kind")||!d.has("payload"))return Error::invalid_request;
   if(d["kind"].get_type()!=Variant::STRING)return Error::invalid_type;
   if(!kind_of(d["kind"],out)||out==JobKind::start||out==JobKind::start_management)return Error::invalid_request;
   if(d["payload"].get_type()!=Variant::DICTIONARY)return Error::invalid_type;
   return Error::none;
  }
  Error capture(std::span<JsonCell> cells,std::span<char> text,DocumentView& d) const noexcept override {
   Sink sink{cells,text};std::uint32_t root=no_cell;
   auto error=sink.value(value_,0,root);
   if(error!=Error::none)return error;
   d={std::string_view(text.data(),sink.text_used),cells.first(sink.cells_used),root};
   error=validate_capture(d,Limits{max_message,30000,12,4096,4096},17);
   if(error!=Error::none)return error;
   // Repeat the real closed native validator here, before the OS-only keycode
   // roundtrip. This preserves exact payload/type/domain precedence, normalizes
   // only the owned charged cells, and never mutates the caller's Variant.
   RequestView request;error=validate_request(d,request,false,cells.first(sink.cells_used));
   if(error!=Error::none)return error;
   for(std::uint32_t i=0;i<d.cells.size();++i) {
    if(d.cells[i].kind!=ValueKind::object)continue;
    const auto kind=d.member(i,"kind");
    const bool physical=d.string_is(kind,"physical_keys"),pair=d.string_is(kind,"key_pair");
    if(!physical&&!pair)continue;
    const std::array<std::string_view,2> fields=physical?std::array<std::string_view,2>{"keys",""}:std::array<std::string_view,2>{"negative","positive"};
    for(unsigned field_index=0;field_index<(physical?1u:2u);++field_index) {
     const auto field=fields[field_index];
     const auto array=d.member(i,field);const auto* a=d.at(array);if(!a)return Error::invalid_record;
     for(auto n=a->first;n!=no_cell;n=d.cells[n].next) {
      if(d.cells[n].kind!=ValueKind::integer||!physical_key(Variant(std::bit_cast<std::int64_t>(d.cells[n].scalar))))return Error::invalid_record;
     }
    }
   }
   return Error::none;
  }
 private:
  const Variant& value_;
  struct Sink {
   std::span<JsonCell> cells;std::span<char> text;
   std::size_t cells_used{},text_used{};
   Error literal(const String& s,std::uint32_t& offset,std::uint32_t& length) {
    std::size_t n=0;auto e=utf8(s,text.subspan(text_used),n,std::min<std::size_t>(4096,max_message-text_used));
    if(e!=Error::none)return e;
    offset=static_cast<std::uint32_t>(text_used);length=static_cast<std::uint32_t>(n);text_used+=n;
    return Error::none;
   }
   static std::size_t array_cap(const Variant& key) {
    if(one_of(key,{"keys","negative","positive","sources","systems"}))return 4;
    if(one_of(key,{"devices","axes"}))return 8;
    if(is(key,"actions"))return 64;
    if(is(key,"practice_ids"))return 50;
    if(is(key,"snapshot_ids"))return 2;
    return 30000;
   }
   Error value(const Variant& v,std::size_t parent_depth,std::uint32_t& result,
               std::size_t array_limit=30000) {
    if(cells_used>=30000)return Error::payload_limit;
    if(cells_used>=cells.size())return Error::out_of_memory;
    result=static_cast<std::uint32_t>(cells_used++);
    cells[result]=JsonCell{};auto& c=cells[result];c.flags=1;
    switch(v.get_type()) {
     case Variant::NIL:c.kind=ValueKind::null;return Error::none;
     case Variant::BOOL:c.kind=ValueKind::boolean;c.scalar=bool(v)?1:0;return Error::none;
     case Variant::INT:
      c.kind=ValueKind::integer;c.scalar=std::bit_cast<std::uint64_t>(static_cast<std::int64_t>(v));return Error::none;
     case Variant::FLOAT: {
      const double n=v;if(!finite_binary64(n))return Error::invalid_record;
      c.kind=ValueKind::real;c.scalar=std::bit_cast<std::uint64_t>(n);return Error::none;
     }
     case Variant::STRING:c.kind=ValueKind::string;return literal(String(v),c.offset,c.length);
     case Variant::ARRAY: {
      if(parent_depth>=12)return Error::payload_limit;
      const Array a=v;const auto n=a.size();
      if(n<0||static_cast<std::uint64_t>(n)>array_limit||static_cast<std::uint64_t>(n)>30000-cells_used)return Error::payload_limit;
      c.kind=ValueKind::array;std::uint32_t previous=no_cell;
      for(std::int64_t i=0;i<n;++i) {
       std::uint32_t child;auto e=value(a[i],parent_depth+1,child);if(e!=Error::none)return e;
       if(previous==no_cell)c.first=child;else cells[previous].next=child;previous=child;
      }
      return Error::none;
     }
     case Variant::DICTIONARY: {
      if(parent_depth>=12)return Error::payload_limit;
      const Dictionary d=v;if(d.size()>17)return Error::invalid_record;
      c.kind=ValueKind::object;
      std::array<Variant,17> keys;std::size_t n=0;
      if(!each_key(v,[&](const Variant& k){if(k.get_type()!=Variant::STRING)return false;keys[n++]=k;return true;}))return Error::invalid_type;
      std::sort(keys.begin(),keys.begin()+n,[](const Variant& a,const Variant& b){return String(a)<String(b);});
      std::uint32_t previous=no_cell;
      for(std::size_t i=0;i<n;++i) {
       std::uint32_t ko,kl;auto e=literal(String(keys[i]),ko,kl);if(e!=Error::none)return e;
       std::uint32_t child;e=value(d[keys[i]],parent_depth+1,child,array_cap(keys[i]));if(e!=Error::none)return e;
       cells[child].key_offset=ko;cells[child].key_length=static_cast<std::uint16_t>(kl);
       if(previous==no_cell)c.first=child;else cells[previous].next=child;previous=child;
      }
      return Error::none;
     }
     default:return Error::invalid_type;
    }
   }
  };
};

Dictionary admission(const Admission& a) {
 Dictionary d;d["accepted"]=a.accepted;d["error_code"]=gs(error_name(a.error));
 d["request_id"]=a.accepted?Variant(gs(a.request_id.view())):Variant();return d;
}
Dictionary rejected(Error error) {return admission(Admission{false,error,{}});}
std::string_view state_name(ServiceState s) {
 switch(s) {
  case ServiceState::new_service:return "new";case ServiceState::opening:return "opening";
  case ServiceState::ready:return "ready";case ServiceState::closing:return "closing";
  case ServiceState::closed:return "closed";case ServiceState::read_only:return "read_only";
  case ServiceState::unavailable:return "unavailable";
 }
 return {};
}

// D is a core-produced, already validated canonical Result. The following code
// nevertheless checks every output object's closed shape and schema position.
// It restores only bounded INT positions and declared preference FLOAT slots.
// The final streaming comparison below proves that restoration lost no bytes,
// scalar branch, signed zero, Unicode, collection order or closed member.
bool text(const Variant& v,std::size_t low,std::size_t high) {
 if(v.get_type()!=Variant::STRING)return false;
 const String s=v;return s.length()>=static_cast<std::int64_t>(low)&&s.length()<=static_cast<std::int64_t>(high);
}
// Scalar-only UTF8 scratch has its schema's exact byte ceiling. Variable
// path/name payload stays solely in the final caller-owned Godot String.
template<std::size_t N,class F> bool checked_scalar(const Variant& v,F&& f) {
 std::array<char,N> bytes;std::size_t n;
 return bounded_text(v,bytes,n)&&f(std::string_view(bytes.data(),n));
}
bool hex(const Variant& v,std::size_t n) {return checked_scalar<64>(v,[&](auto s){return lower_hex(s,n);});}
bool parse_u64(const Variant& v,U64& out,bool positive=false) {
 return checked_scalar<20>(v,[&](auto s){return U64::parse(s,out,positive);});
}
bool u64(const Variant& v,bool positive=false) {U64 out;return parse_u64(v,out,positive);}
bool utc(const Variant& v) {return checked_scalar<20>(v,[](auto s){return valid_utc(s);});}
// Count UTF8 bytes directly from Unicode scalars, without CharString/native
// payload mirrors. This matches utf8()'s malformed-scalar rejection.
bool output_string_size(const String& s,std::size_t byte_limit) {
 if(s.length()<0||static_cast<std::uint64_t>(s.length())>byte_limit)return false;
 std::size_t bytes=0;
 for(std::int64_t i=0;i<s.length();++i){
  const auto cp=static_cast<std::uint32_t>(s.unicode_at(i));
  if(cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff))return false;
  const std::size_t n=cp<0x80?1:cp<0x800?2:cp<0x10000?3:4;
  if(n>byte_limit-bytes)return false;bytes+=n;
 }
 return true;
}
bool path(const Variant& v) {
 if(v.get_type()!=Variant::STRING)return false;const String s=v;
 if(s.length()<4||!output_string_size(s,4096))return false;
 const auto drive=s.unicode_at(0);
 if(!((drive>='A'&&drive<='Z')||(drive>='a'&&drive<='z'))||s.unicode_at(1)!=':'||(s.unicode_at(2)!='/'&&s.unicode_at(2)!='\\'))return false;
 std::int64_t begin=3;
 for(std::int64_t i=3;i<=s.length();++i){
  const auto cp=i==s.length()?0:s.unicode_at(i);
  if(i==s.length()||cp=='/'||cp=='\\'){
   const auto length=i-begin;
   if(length==0||(length==1&&s.unicode_at(begin)=='.')||(length==2&&s.unicode_at(begin)=='.'&&s.unicode_at(begin+1)=='.')||s.unicode_at(i-1)=='.'||s.unicode_at(i-1)==' ')return false;
   begin=i+1;
  }else if(cp<32||cp==127||cp==':'||cp=='*'||cp=='?'||cp=='"'||cp=='<'||cp=='>'||cp=='|')return false;
 }
 return true;
}
bool name(const Variant& v) {
 if(v.get_type()!=Variant::STRING)return false;const String s=v;
 if(s.length()<1||s.length()>40||!output_string_size(s,160))return false;
 auto ws=[](std::int64_t cp){return cp==32||cp==0x85||cp==0xa0||cp==0x1680||(cp>=0x2000&&cp<=0x200a)||cp==0x2028||cp==0x2029||cp==0x202f||cp==0x205f||cp==0x3000;};
 for(std::int64_t i=0;i<s.length();++i){const auto cp=s.unicode_at(i);if(cp<32||cp==127)return false;}
 return !ws(s.unicode_at(0))&&!ws(s.unicode_at(s.length()-1));
}
bool boolean(const Variant& v) {return v.get_type()==Variant::BOOL;}
// Every numeric INT position below is <=1GiB, INT32_MAX or tiny enum/count.
// Hence every admitted canonical INT is EXACTLY representable in binary64.
// U64 never enters this function; it remains a canonical String throughout.
bool integer(Variant& v,std::int64_t lo,std::int64_t hi) {
 if(v.get_type()!=Variant::INT&&v.get_type()!=Variant::FLOAT)return false;
 double n=v;if(!finite_binary64(n)||n<static_cast<double>(lo)||n>static_cast<double>(hi)||std::trunc(n)!=n)return false;
 v=static_cast<std::int64_t>(n);return true;
}
bool integer(Dictionary& d,const char* key,std::int64_t lo,std::int64_t hi) {
 Variant v=d[key];if(!integer(v,lo,hi))return false;d[key]=v;return true;
}
bool continuous(Variant& v,double lo,double hi,bool tag_required=false) {
 if(v.get_type()==Variant::DICTIONARY) {
  if(!closed(v,{"$binary64_le"}))return false;
  Dictionary tag=v;Variant s=tag["$binary64_le"];if(!hex(s,16))return false;
  const String h=s;std::uint64_t bits=0;
  auto nibble=[](std::int64_t c)->std::uint64_t{return c<='9'?c-'0':c-'a'+10;};
  for(unsigned i=0;i<8;++i)bits|=((nibble(h.unicode_at(i*2))<<4)|nibble(h.unicode_at(i*2+1)))<<(8*i);
  const double n=std::bit_cast<double>(bits);
  if(!finite_binary64(n)||n<lo||n>hi)return false;
  v=n;return std::bit_cast<std::uint64_t>(static_cast<double>(v))==bits;
 }
 if(tag_required)return false;
 // Continuous INT branch is deliberately retained as INT. A bare canonical
 // decimal FLOAT is never legal D: parity rejects a parser-created FLOAT here.
 return integer(v,static_cast<std::int64_t>(std::ceil(lo)),static_cast<std::int64_t>(std::floor(hi)));
}
bool continuous(Dictionary& d,const char* k,double lo,double hi,bool required=false) {
 Variant v=d[k];if(!continuous(v,lo,hi,required))return false;d[k]=v;return true;
}
template<class F> bool list(Variant& v,std::size_t lo,std::size_t hi,F&& item) {
 if(v.get_type()!=Variant::ARRAY)return false;
 Array a=v;if(a.size()<static_cast<std::int64_t>(lo)||a.size()>static_cast<std::int64_t>(hi))return false;
 for(std::int64_t i=0;i<a.size();++i){Variant x=a[i];if(!item(x))return false;a[i]=x;}
 return true;
}
template<class F> bool field_list(Dictionary& d,const char* k,std::size_t lo,std::size_t hi,F&& item) {
 Variant v=d[k];if(!list(v,lo,hi,item))return false;d[k]=v;return true;
}
bool slot(const Variant& v) {
 if(!text(v,1,32))return false;const String s=v;
 for(std::int64_t i=0;i<s.length();++i){auto c=s.unicode_at(i);
  if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(i>0&&((c>='0'&&c<='9')||c=='.'||c=='_'||c=='-'))))return false;
 }
 return true;
}
bool model(const Variant& v,bool piston) {
 if(!closed(v,{"id","version","backend_model"}))return false;Dictionary d=v;
 return is(d["version"],"0.1.0-prototype")&&
  is(d["id"],piston?"original-piston-prop-v1":"original-interactive-prototype")&&
  is(d["backend_model"],piston?"original-piston-prop":"original-interactive");
}
bool session_id(const Variant& v) {
 if(!text(v,1,128))return false;String s=v;bool separator=false;
 for(std::int64_t i=0;i<s.length();++i){auto c=s.unicode_at(i);bool sep=c=='.'||c=='_'||c=='-';
  if(i==0&&(c<'a'||c>'z'))return false;
  if(!sep&&!((c>='a'&&c<='z')||(c>='0'&&c<='9')))return false;
  if(sep&&(separator||i+1==s.length()))return false;separator=sep;
 }
 return true;
}
bool source(const Variant& v) {
 if(!closed(v,{"session_id","model_identity","source_variant","native_source_fingerprint","prepared_world_sha256","named_start","wind_profile","angular_integration_method"}))return false;
 Dictionary d=v;
 if(!session_id(d["session_id"])||!hex(d["native_source_fingerprint"],64)||!hex(d["prepared_world_sha256"],64))return false;
 if(!one_of(d["source_variant"],{"jsbsim-1.3.1-upstream","jsbsim-1.3.1-event-aware-constant-power-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"}))return false;
 if(model(d["model_identity"],false))return one_of(d["named_start"],{"ground-ready","airborne-prepared"})&&
  one_of(d["wind_profile"],{"calm","from-north","from-west","from-east"})&&is_null(d["angular_integration_method"]);
 if(!model(d["model_identity"],true)||!is(d["named_start"],"piston-cold-ground")||!is(d["wind_profile"],"calm"))return false;
 if(is(d["source_variant"],"jsbsim-1.3.1-event-aware-constant-power-v1"))return is(d["angular_integration_method"],"event_aware_constant_power_v1");
 return one_of(d["source_variant"],{"jsbsim-1.3.1-event-aware-coupled-midpoint-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"})&&is(d["angular_integration_method"],"event_aware_coupled_midpoint_v1");
}
bool keys(Variant& v) {
 if(!list(v,1,4,[](Variant& n){return integer(n,32,2147483647)&&physical_key(n);}))return false;
 Array a=v;for(std::int64_t i=0;i<a.size();++i)for(std::int64_t j=0;j<i;++j)if(a[i]==a[j])return false;
 return true;
}
bool key_field(Dictionary& d,const char* k){Variant v=d[k];if(!keys(v))return false;d[k]=v;return true;}
bool has_slot(const Array& devices,const Variant& slot_value) {
 for(std::int64_t i=0;i<devices.size();++i){Dictionary d=devices[i];if(d["slot"]==slot_value)return true;}
 return false;
}
bool unique_field(const Array& a,const char* key) {
 for(std::int64_t i=0;i<a.size();++i)for(std::int64_t j=0;j<i;++j)if(Dictionary(a[i])[key]==Dictionary(a[j])[key])return false;
 return true;
}
bool input_source(Variant& v,const Array& devices,bool system=false) {
 if(v.get_type()!=Variant::DICTIONARY)return false;Dictionary d=v;
 if(is(d.get("kind",Variant()),"physical_keys"))return closed(v,{"kind","keys"})&&key_field(d,"keys");
 if(is(d.get("kind",Variant()),"joy_button"))return closed(v,{"kind","slot","index"})&&has_slot(devices,d["slot"])&&integer(d,"index",0,127);
 if(is(d.get("kind",Variant()),"mouse_button"))return closed(v,{"kind","button"})&&integer(d,"button",1,9)&&(!system||!(std::int64_t(d["button"])>=4&&std::int64_t(d["button"])<=7));
 return false;
}
bool source_alias(const Dictionary& a,const Dictionary& b) {
 if(a["kind"]!=b["kind"])return false;
 if(is(a["kind"],"joy_button"))return a["slot"]==b["slot"]&&a["index"]==b["index"];
 if(is(a["kind"],"mouse_button"))return a["button"]==b["button"];
 Array ak=a["keys"],bk=b["keys"];if(ak.size()!=bk.size())return false;
 for(std::int64_t i=0;i<ak.size();++i)if(!bk.has(ak[i]))return false;
 return true;
}
bool unique_sources(const Array& a) {
 for(std::int64_t i=0;i<a.size();++i)for(std::int64_t j=0;j<i;++j)if(source_alias(Dictionary(a[i]),Dictionary(a[j])))return false;
 return true;
}
// Bounded visits over the final tree, not a second owner dictionary/registry.
// Identity: physical0/joy-axis1/joy-button2/mouse3, slot, code, binding owner.
template<class F> bool controls(const Dictionary& d,F&& f) {
 Array axes=d["axes"];
 for(std::int64_t i=0;i<axes.size();++i){Dictionary a=axes[i];
  if(is(a["kind"],"key_pair")){for(const char* side:{"negative","positive"}){Array keys=a[side];for(std::int64_t j=0;j<keys.size();++j)if(!f(0,Variant(),std::int64_t(keys[j]),unsigned(i)))return false;}}
  else if(is(a["kind"],"joy_axis")&&!f(1,a["slot"],std::int64_t(a["index"]),unsigned(i)))return false;
 }
 for(unsigned group=0;group<2;++group){Array bindings=d[group?"systems":"actions"];
  for(std::int64_t i=0;i<bindings.size();++i){Dictionary b=bindings[i];Array sources=b["sources"];
   for(std::int64_t j=0;j<sources.size();++j){Dictionary s=sources[j];const unsigned owner=(group?72:8)+unsigned(i);
    if(is(s["kind"],"physical_keys")){Array keys=s["keys"];for(std::int64_t k=0;k<keys.size();++k)if(!f(0,Variant(),std::int64_t(keys[k]),owner))return false;}
    else if(is(s["kind"],"joy_button")){if(!f(2,s["slot"],std::int64_t(s["index"]),owner))return false;}
    else if(!f(3,Variant(),std::int64_t(s["button"]),owner))return false;
   }
  }
 }
 return true;
}
bool no_control_conflicts(const Dictionary& d) {
 return controls(d,[&](int kind,const Variant& slot,std::int64_t code,unsigned owner){
  if(kind==0&&code==godot::KEY_ESCAPE)return false;
  return controls(d,[&](int other,const Variant& other_slot,std::int64_t other_code,unsigned other_owner){
   return owner==other_owner||kind!=other||slot!=other_slot||code!=other_code;
  });
 });
}
bool axis(Variant& v,const Array& devices,bool piston) {
 if(v.get_type()!=Variant::DICTIONARY)return false;Dictionary d=v;
 if(!one_of(d.get("target",Variant()),{"roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"}))return false;
 const bool mixture=is(d["target"],"mixture");
 const double lo=one_of(d["target"],{"roll","pitch","yaw","trim"})?-1.0:0.0;
 if(is(d.get("kind",Variant()),"fixed"))return closed(v,{"target","kind","value"})&&continuous(d,"value",mixture&&!piston?1:lo,1);
 if(mixture&&!piston)return false;
 if(is(d.get("kind",Variant()),"key_pair")) {
  if(!closed(v,{"target","kind","negative","positive","rate","gain","return_to_start"})||
   !key_field(d,"negative")||!key_field(d,"positive")||!continuous(d,"rate",0,4)||!continuous(d,"gain",0,1)||
   double(d["rate"])<=0||double(d["gain"])<=0||!boolean(d["return_to_start"])||
   (bool(d["return_to_start"])&&!one_of(d["target"],{"roll","pitch","yaw"})))return false;
  Array n=d["negative"],p=d["positive"];for(std::int64_t i=0;i<n.size();++i)if(p.has(n[i]))return false;
  return true;
 }
 if(!is(d.get("kind",Variant()),"joy_axis")||!closed(v,{"target","kind","slot","index","range","minimum","center","maximum","invert","deadzone","saturation","gain","slew_per_s"})||
  !has_slot(devices,d["slot"])||!integer(d,"index",0,9)||!one_of(d["range"],{"centered","unsigned"})||
  !boolean(d["invert"])||(mixture&&!is(d["range"],"unsigned")))return false;
 for(const char* k:{"minimum","center","maximum"})if(!continuous(d,k,-1,1))return false;
 if(is(d["range"],"centered")&&(double(d["center"])-double(d["minimum"])<.05||double(d["maximum"])-double(d["center"])<.05))return false;
 if(is(d["range"],"unsigned")&&double(d["maximum"])-double(d["minimum"])<.05)return false;
 return continuous(d,"deadzone",0,.4)&&continuous(d,"saturation",0,1)&&double(d["saturation"])>double(d["deadzone"])&&
  continuous(d,"gain",0,1)&&double(d["gain"])>0&&continuous(d,"slew_per_s",0,4);
}
bool preset(Variant& v,bool piston) {
 if(is_null(v))return true;
 if(!(piston?closed(v,{"type","version","name","devices","axes","actions","profile","capability_revision","systems"}):closed(v,{"type","version","name","devices","axes","actions"})))return false;
 Dictionary d=v;
 if(!is(d["type"],"InputPreset")||!integer(d,"version",piston?2:1,piston?2:1)||!text(d["name"],1,64))return false;
 if(piston&&(!model(d["profile"],true)||!is(d["capability_revision"],"piston-controls-v1")))return false;
 if(!field_list(d,"devices",0,8,[&](Variant& item){
  if(!closed(item,{"slot","label","match"}))return false;Dictionary x=item;
  if(!slot(x["slot"])||!text(x["label"],0,64)||!closed(x["match"],{"guid","name","vendor_id","product_id"}))return false;
  Dictionary m=x["match"];if(!text(m["guid"],0,128)||!text(m["name"],0,128)||!text(m["vendor_id"],0,16)||!text(m["product_id"],0,16))return false;
  return true;
 }))return false;
 const Array devices=d["devices"];if(!unique_field(devices,"slot"))return false;
 if(!field_list(d,"axes",8,8,[&](Variant& item){return axis(item,devices,piston);})||!unique_field(Array(d["axes"]),"target"))return false;
 if(!field_list(d,"actions",0,64,[&](Variant& item){
  if(!closed(item,{"id","sources"}))return false;Dictionary x=item;
  if(!one_of(x["id"],{"pause_menu","restart","start_ground","start_airborne","idle","left_brake","right_brake","both_brakes","brake_hold","view_cycle","view_cockpit","view_chase","view_orbit","view_panel","map_toggle","runway_toggle","map_zoom_in","map_zoom_out","look_hold","view_zoom_in","view_zoom_out","recenter","help","overlay","controller_select","audio","fullscreen","speed_down","speed_up","controls_panel"}))return false;
  return field_list(x,"sources",1,4,[&](Variant& s){return input_source(s,devices);})&&unique_sources(Array(x["sources"]));
 }))return false;
 if(!unique_field(Array(d["actions"]),"id"))return false;
 if(piston){if(!field_list(d,"systems",4,4,[&](Variant& item){
  if(!closed(item,{"id","kind","sources"}))return false;Dictionary x=item;
  if(!one_of(x["id"],{"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"})||!is(x["kind"],is(x["id"],"engine.starter")?"momentary":"toggle"))return false;
  return field_list(x,"sources",1,4,[&](Variant& s){return input_source(s,devices,true);})&&unique_sources(Array(x["sources"]));
 })||!unique_field(Array(d["systems"]),"id"))return false;}
 return !piston||no_control_conflicts(d);
}
bool audio(Variant& v) {
 if(!closed(v,{"enabled","engine_gain","airflow_gain","show_panel_captions"}))return false;Dictionary d=v;
 return boolean(d["enabled"])&&boolean(d["show_panel_captions"])&&continuous(d,"engine_gain",0,1,true)&&continuous(d,"airflow_gain",0,1,true);
}
bool player(Variant& v) {
 if(!closed(v,{"type","version","id","name","created_utc","updated_utc","revision"}))return false;Dictionary d=v;
 return is(d["type"],"LocalPlayer")&&integer(d,"version",1,1)&&hex(d["id"],32)&&name(d["name"])&&utc(d["created_utc"])&&utc(d["updated_utc"])&&u64(d["revision"],true);
}
bool preferences(Variant& v) {
 if(!closed(v,{"type","version","player_id","revision","legacy_input","piston_input","audio"}))return false;Dictionary d=v;
 if(!is(d["type"],"LocalPlayerPreferences")||!integer(d,"version",1,1)||!hex(d["player_id"],32)||!u64(d["revision"],true))return false;
 Variant l=d["legacy_input"],p=d["piston_input"],a=d["audio"];
 if(!preset(l,false)||!preset(p,true)||!audio(a))return false;
 d["legacy_input"]=l;d["piston_input"]=p;d["audio"]=a;return true;
}
bool archive(const Variant& v) {
 if(is_null(v))return true;
 if(!closed(v,{"type","version","absolute_path","payload_sha256","recording_session_id","first_tick","last_tick","linked_utc"}))return false;
 Dictionary d=v;
 if(!is(d["type"],"ExternalRecordedReview")||!integer(d,"version",1,1)||!path(d["absolute_path"])||!hex(d["payload_sha256"],64)||!session_id(d["recording_session_id"])||!utc(d["linked_utc"])||!u64(d["first_tick"])||!u64(d["last_tick"]))return false;
 U64 first,last;
 return parse_u64(d["first_tick"],first)&&parse_u64(d["last_tick"],last)&&U64::compare(first,last)<=0;
}
bool practice(Variant& v,bool summary=false) {
 if(!closed(v,{"type","version","id","player_id","source","started_utc","last_observed_utc","first_tick","last_tick","observed_ticks","tick_rate_hz","status","end_reason","revision","creation_sequence","commit_sequence","archive"}))return false;
 Dictionary d=v;
 if(!is(d["type"],"LocalPractice")||!integer(d,"version",1,1)||!hex(d["id"],32)||!hex(d["player_id"],32)||!source(d["source"])||!utc(d["started_utc"])||!utc(d["last_observed_utc"])||!integer(d,"tick_rate_hz",120,120))return false;
 for(const char* k:{"first_tick","last_tick","observed_ticks"})if(!u64(d[k]))return false;
 for(const char* k:{"revision","creation_sequence","commit_sequence"})if(!u64(d[k],true))return false;
 auto parsed=[&](const char* k,U64& n){return parse_u64(d[k],n);};
 U64 first,last,observed,difference,creation,commit;
 if(!parsed("first_tick",first)||!parsed("last_tick",last)||!parsed("observed_ticks",observed)||!U64::subtract(last,first,difference)||U64::compare(difference,observed)!=0||
  !parsed("creation_sequence",creation)||!parsed("commit_sequence",commit)||U64::compare(creation,commit)>0)return false;
 if(is(d["status"],"active")){if(!is_null(d["end_reason"]))return false;}
 else if(is(d["status"],"manually_ended")){if(!one_of(d["end_reason"],{"user_end","user_restart","user_quit"}))return false;}
 else if(is(d["status"],"source_ended")){if(!is(d["end_reason"],"native_terminal"))return false;}
 else if(is(d["status"],"interrupted")){if(!is(d["end_reason"],"previous_process_incomplete"))return false;}
 else return false;
 if(summary)return closed(d["archive"],{"linked"})&&boolean(Dictionary(d["archive"])["linked"]);
 return archive(d["archive"]);
}
bool id_array(Variant& v,std::size_t cap) {
 if(!list(v,0,cap,[](Variant& x){return hex(x,32);}))return false;
 Array a=v;for(std::int64_t i=0;i<a.size();++i)for(std::int64_t j=0;j<i;++j)if(a[i]==a[j])return false;
 return true;
}
bool deletion(Variant& v) {
 if(!closed(v,{"deleted_ids","retained_ids"}))return false;Dictionary d=v;
 Variant a=d["deleted_ids"],b=d["retained_ids"];
 if(!id_array(a,2)||!id_array(b,2))return false;Array aa=a,bb=b;
 if(aa.size()+bb.size()>2)return false;
 for(std::int64_t i=0;i<aa.size();++i)if(bb.has(aa[i]))return false;
 return true;
}
bool failed_kind_error(JobKind,const Variant&);
bool export_receipt(Variant& v,const Variant& rid,const Variant& result_state,const Variant& error) {
 if(!closed(v,{"operation_id","outcome","phase","target_absolute_path","temporary_absolute_path","installed","bytes","sha256","player_id","preferences_revision","practice_count"}))return false;
 Dictionary d=v;
 if(d["operation_id"]!=rid||!one_of(d["outcome"],{"saved","not_saved","recovery_required"})||
  !one_of(d["phase"],{"read","encode","create","write","flush","verify_temp","move","verify_target","done"})||!path(d["target_absolute_path"])||
  (!is_null(d["temporary_absolute_path"])&&!path(d["temporary_absolute_path"]))||(!is_null(d["installed"])&&!boolean(d["installed"])))return false;
 const bool no_snapshot=is_null(d["player_id"]);
 if(no_snapshot){if(!is_null(d["preferences_revision"])||!is_null(d["practice_count"]))return false;}
 else if(!hex(d["player_id"],32)||!u64(d["preferences_revision"],true)||!integer(d,"practice_count",0,2000))return false;
 if(is_null(d["bytes"])) {if(!is_null(d["sha256"]))return false;}
 else if(!integer(d,"bytes",0,33554432)||!hex(d["sha256"],64))return false;
 if(is(d["outcome"],"saved"))return is(result_state,"read")&&is(error,"")&&!no_snapshot&&is(d["phase"],"done")&&boolean(d["installed"])&&bool(d["installed"])&&is_null(d["temporary_absolute_path"])&&!is_null(d["bytes"]);
 if(is(d["outcome"],"recovery_required"))return is(result_state,"recovery_required")&&is(error,"file_recovery_required")&&one_of(d["phase"],{"move","verify_target","done"});
 if(no_snapshot&&(!is(d["phase"],"read")||!is_null(d["temporary_absolute_path"])||!is_null(d["bytes"])))return false;
 return is(result_state,"failed")&&failed_kind_error(JobKind::export_player,error)&&!is(error,"file_recovery_required")&&boolean(d["installed"])&&!bool(d["installed"]);
}
bool recovery(Variant& v) {
 if(!closed(v,{"id","state","created_utc","bytes","manifest_sha256"}))return false;Dictionary d=v;
 // Summary bytes/state/hash describe the RETAINED recovery-<id> only, at most
 // four data files336MiB plus intent/manifest1MiB. Associated work-<id> is not
 // included; management ownership/deletion of both sets remains the core's job.
 if(!hex(d["id"],32)||!one_of(d["state"],{"complete","partial"})||(!is_null(d["created_utc"])&&!utc(d["created_utc"]))||!integer(d,"bytes",0,353370112)||(!is_null(d["manifest_sha256"])&&!hex(d["manifest_sha256"],64)))return false;
 return !is(d["state"],"complete")||(!is_null(d["created_utc"])&&!is_null(d["manifest_sha256"]));
}
bool known_error(const Variant& v) {
 for(unsigned i=0;i<=static_cast<unsigned>(Error::file_recovery_required);++i)if(is(v,error_name(static_cast<Error>(i))))return true;
 return false;
}
bool failed_kind_error(JobKind kind,const Variant& error) {
 // Recovery/management never access SQLite: use their explicit protocol sets
 // before the common DB-access failures. Unknown recovery worker death maps
 // to snapshot_failed, not worker_lost; malformed results abandon the batch.
 if(kind==JobKind::start_management)return one_of(error,{"store_locked","root_unavailable","recovery_limit","snapshot_failed","io_error","worker_lost"});
 if(kind==JobKind::list_recovery||kind==JobKind::delete_recovery)return one_of(error,{"root_unavailable","snapshot_failed","recovery_limit","io_error"});
 if(one_of(error,{"busy","io_error","worker_lost","storage_full","corrupt_store"}))return true;
 switch(kind) {
  case JobKind::start:return one_of(error,{"store_locked","root_unavailable","foreign_store","unsupported_version","recovery_required","recovery_limit","snapshot_failed","counter_exhausted"});
  case JobKind::create_player:return one_of(error,{"identity_conflict","player_limit","counter_exhausted"});
  case JobKind::load_player:case JobKind::list_practice:case JobKind::load_practice:return is(error,"not_found");
  case JobKind::rename_player:case JobKind::save_preferences:return one_of(error,{"not_found","revision_conflict","counter_exhausted"});
  case JobKind::begin_practice:return one_of(error,{"not_found","identity_conflict","active_practice","history_limit","counter_exhausted"});
  case JobKind::observe_practice:case JobKind::end_practice:return one_of(error,{"not_found","revision_conflict","source_mismatch","tick_regression","invalid_transition","counter_exhausted"});
  case JobKind::link_archive:return one_of(error,{"not_found","revision_conflict","source_mismatch","invalid_transition","counter_exhausted"});
  case JobKind::prune_practice:return one_of(error,{"not_found","active_practice","counter_exhausted"});
  case JobKind::delete_player:return one_of(error,{"not_found","revision_conflict","active_practice","counter_exhausted"});
  case JobKind::export_player:return one_of(error,{"not_found","revision_conflict","target_exists","path_rejected","file_create_failed","file_write_failed","file_flush_failed","file_verify_failed","file_recovery_required"});
  default:return false;
 }
}
bool mutation(JobKind k) {
 return k==JobKind::start||k==JobKind::create_player||k==JobKind::rename_player||k==JobKind::save_preferences||k==JobKind::begin_practice||k==JobKind::observe_practice||k==JobKind::end_practice||k==JobKind::link_archive||k==JobKind::prune_practice||k==JobKind::delete_player;
}
bool successful_value(JobKind k,Variant& v) {
 switch(k) {
  case JobKind::start: {
   if(!closed(v,{"store_version","interrupted_rows","created"}))return false;Dictionary d=v;
   return integer(d,"store_version",1,1)&&integer(d,"interrupted_rows",0,1)&&boolean(d["created"]);
  }
  case JobKind::start_management:return closed(v,{"management_only"})&&boolean(Dictionary(v)["management_only"])&&bool(Dictionary(v)["management_only"]);
  case JobKind::list_players: {
   if(!closed(v,{"players"}))return false;Dictionary d=v;
   return field_list(d,"players",0,8,[](Variant& x){if(!closed(x,{"id","name","revision"}))return false;Dictionary p=x;return hex(p["id"],32)&&name(p["name"])&&u64(p["revision"],true);});
  }
  case JobKind::create_player:case JobKind::load_player:case JobKind::rename_player:case JobKind::save_preferences: {
   if(!closed(v,{"player","preferences"}))return false;Dictionary d=v;Variant p=d["player"],o=d["preferences"];
   if(!player(p)||!preferences(o))return false;Dictionary pp=p,oo=o;
   if(pp["id"]!=oo["player_id"]||pp["revision"]!=oo["revision"])return false;
   d["player"]=p;d["preferences"]=o;return true;
  }
  case JobKind::begin_practice:case JobKind::observe_practice:case JobKind::end_practice:case JobKind::link_archive:case JobKind::load_practice: {
   if(!closed(v,{"practice"}))return false;Dictionary d=v;Variant p=d["practice"];if(!practice(p))return false;d["practice"]=p;return true;
  }
  case JobKind::list_practice: {
   if(!closed(v,{"practice","next_before_creation_sequence"}))return false;Dictionary d=v;
   return (is_null(d["next_before_creation_sequence"])||u64(d["next_before_creation_sequence"]))&&field_list(d,"practice",0,50,[](Variant& x){return practice(x,true);});
  }
  case JobKind::prune_practice: {
   if(!closed(v,{"deleted_ids"}))return false;Dictionary d=v;Variant ids=d["deleted_ids"];return id_array(ids,50);
  }
  case JobKind::delete_player:return closed(v,{"deleted_player_id"})&&hex(Dictionary(v)["deleted_player_id"],32);
  case JobKind::list_recovery: {
   if(!closed(v,{"snapshots"}))return false;Dictionary d=v;return field_list(d,"snapshots",0,2,[](Variant& x){return recovery(x);});
  }
  case JobKind::delete_recovery:return deletion(v)&&Array(Dictionary(v)["retained_ids"]).is_empty();
  default:return false;
 }
}
bool result(Variant& v) {
 if(!closed(v,{"request_id","kind","state","error_code","commit_sequence","value"}))return false;Dictionary d=v;
 JobKind k{};if(!hex(d["request_id"],32)||!kind_of(d["kind"],k)||!known_error(d["error_code"])||
  !one_of(d["state"],{"read","committed","no_change","failed","uncertain","recovery_required"}))return false;
 Variant value=d["value"];
 if(k==JobKind::export_player)return is_null(d["commit_sequence"])&&export_receipt(value,d["request_id"],d["state"],d["error_code"]);
 if(is(d["state"],"recovery_required"))return false;
 if(is(d["state"],"uncertain"))return mutation(k)&&is_null(d["commit_sequence"])&&one_of(d["error_code"],{"commit_unknown","verification_failed"})&&is_null(value);
 if(is(d["state"],"failed"))return is_null(d["commit_sequence"])&&failed_kind_error(k,d["error_code"])&&
  (is_null(value)||(k==JobKind::delete_recovery&&is(d["error_code"],"snapshot_failed")&&deletion(value)));
 if(!is(d["error_code"],""))return false;
 if(is(d["state"],"committed")){if(!mutation(k)||!u64(d["commit_sequence"],true))return false;}
 else if(is(d["state"],"no_change")) {
  if(!mutation(k)||k==JobKind::start||k==JobKind::prune_practice||k==JobKind::delete_player||!u64(d["commit_sequence"],true))return false;
 } else if(!is_null(d["commit_sequence"])||
  (mutation(k)&&k!=JobKind::start))return false;
 if(!successful_value(k,value))return false;d["value"]=value;return true;
}

// Streaming canonical encoder/comparator, not another JSON parser. The only
// tree is the final caller-owned Godot output. At most17 borrowed key refs and
// a four-byte UTF8 scalar exist on each bounded stack level. No retained mirror.
class Parity final {
 public:
  explicit Parity(std::string_view expected):expected_(expected){}
  bool matches(const Variant& v){return value(v,0)&&position_==expected_.size();}
 private:
  std::string_view expected_;std::size_t position_{},values_{};
  bool raw(std::string_view s) {
   if(s.size()>expected_.size()-position_||expected_.substr(position_,s.size())!=s)return false;
   position_+=s.size();return true;
  }
  bool string(const String& s) {
   if(!raw("\""))return false;constexpr char digits[]="0123456789abcdef";
   for(std::int64_t i=0;i<s.length();++i){auto cp=static_cast<std::uint32_t>(s.unicode_at(i));
    if(cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff))return false;
    if(cp=='"'||cp=='\\'){const char b[]{'\\',static_cast<char>(cp)};if(!raw({b,2}))return false;}
    else if(cp<32){const char b[]{'\\','u','0','0',digits[cp>>4],digits[cp&15]};if(!raw({b,6}))return false;}
    else {char b[4];std::size_t n=cp<0x80?1:cp<0x800?2:cp<0x10000?3:4;
     if(n==1)b[0]=static_cast<char>(cp);else{b[0]=static_cast<char>((n==2?0xc0:n==3?0xe0:0xf0)|(cp>>(6*(n-1))));for(std::size_t j=n-1;j>0;--j)b[n-j]=static_cast<char>(0x80|((cp>>(6*(j-1)))&63));}
     if(!raw({b,n}))return false;
    }
   }
   return raw("\"");
  }
  bool value(const Variant& v,unsigned depth) {
   if(++values_>30000)return false;
   switch(v.get_type()) {
    case Variant::NIL:return raw("null");
    case Variant::BOOL:return raw(bool(v)?"true":"false");
    case Variant::INT:{char b[24];auto r=std::to_chars(b,b+sizeof b,static_cast<std::int64_t>(v));return r.ec==std::errc{}&&raw({b,static_cast<std::size_t>(r.ptr-b)});}
    case Variant::FLOAT:{double n=v;if(!finite_binary64(n))return false;const auto bits=std::bit_cast<std::uint64_t>(n);constexpr char digits[]="0123456789abcdef";char h[16];for(unsigned i=0;i<8;++i){auto byte=(bits>>(8*i))&255;h[2*i]=digits[byte>>4];h[2*i+1]=digits[byte&15];}return raw("{\"$binary64_le\":\"")&&raw({h,16})&&raw("\"}");}
    case Variant::STRING:return string(String(v));
    case Variant::ARRAY:{if(depth>=12||!raw("["))return false;Array a=v;for(std::int64_t i=0;i<a.size();++i){if((i&&!raw(","))||!value(a[i],depth+1))return false;}return raw("]");}
    case Variant::DICTIONARY:{if(depth>=12)return false;Dictionary d=v;if(d.size()>17||!raw("{"))return false;std::array<Variant,17> keys;std::size_t n=0;
     if(!each_key(v,[&](const Variant& k){if(k.get_type()!=Variant::STRING)return false;keys[n++]=k;return true;}))return false;
     std::sort(keys.begin(),keys.begin()+n,[](const Variant& a,const Variant& b){return String(a)<String(b);});
     for(std::size_t i=0;i<n;++i)if((i&&!raw(","))||!string(String(keys[i]))||!raw(":")||!value(d[keys[i]],depth+1))return false;
     return raw("}");
    }
    default:return false;
   }
  }
};
bool convert(DeliveryView delivery,Variant& output) {
 if(delivery.bytes.empty()||delivery.bytes.size()>max_message||!valid_utf8(delivery.bytes))return false;
 auto* db=godot::ClassDBSingleton::get_singleton();if(!db)return false;
 // parse result IS the final caller-owned result. No secondary native tree and
 // no use of a profile-excluded JSON wrapper or NativeWireDecoder.
 output=db->class_call_static("JSON","parse_string",gs(delivery.bytes));
 return result(output)&&Parity(delivery.bytes).matches(output);
}
} // namespace

LocalPlayersBoundary::LocalPlayersBoundary(Origin origin) noexcept:owner_(std::this_thread::get_id()),origin_(origin){}
LocalPlayersBoundary::~LocalPlayersBoundary() {
 // Destruction cannot detach or free an unjoined worker. Failure retains the
 // arena and its registry entry for Root's owner-driven pre-unload coordinator.
 if(service_)Service::destroy(service_);
}
bool LocalPlayersBoundary::owner() const noexcept {return std::this_thread::get_id()==owner_;}
bool LocalPlayersBoundary::configure_test_access(StoreAccess&& access) noexcept {
 if(!owner()||origin_!=Origin::isolated_test||service_||closing_||closed_||!access.isolated_test())return false;
 service_=Service::create(std::move(access));return service_!=nullptr;
}
Dictionary LocalPlayersBoundary::start(bool management) {
 if(!owner())return rejected(Error::wrong_thread);
 if(closing_||closed_)return rejected(Error::invalid_state);
 if(service_){Status s;if(!service_->status(s)||s.state!=ServiceState::new_service)return rejected(Error::invalid_state);}
 else {
  if(origin_!=Origin::production)return rejected(Error::invalid_state);
  // Structural production token on this AUTOMATIC call frame; factory performs
  // no KnownFolder/root IO. On allocation failure discard it; retry mints fresh.
  auto access=WindowsFileSystem::production();
  if(!access.valid())return rejected(Error::out_of_memory);
  service_=Service::create(std::move(access));if(!service_)return rejected(Error::out_of_memory);
 }
 return admission(service_->start(management));
}
Dictionary LocalPlayersBoundary::submit(const Variant& request) {
 if(!owner())return rejected(Error::wrong_thread);
 if(!service_||closing_||closed_)return rejected(Error::invalid_state);
 return admission(service_->submit(Capture(request)));
}
Variant LocalPlayersBoundary::status() const {
 if(!owner())return Variant();
 Status s;
 if(service_){if(!service_->status(s))return Variant();}
 else s.state=closed_?ServiceState::closed:closing_?ServiceState::closing:ServiceState::new_service;
 if(state_name(s.state).empty()||static_cast<unsigned>(s.error)>static_cast<unsigned>(Error::file_recovery_required)||s.pending>16||s.undelivered>16||unsigned(s.pending)+s.undelivered>16||
  (s.has_root&&!valid_local_absolute_path(s.resolved_root.view())))return Variant();
 Dictionary d;d["state"]=gs(state_name(s.state));d["error_code"]=gs(error_name(s.error));
 d["pending"]=std::int64_t(s.pending);d["undelivered"]=std::int64_t(s.undelivered);d["writer_alive"]=s.writer_alive;
 d["resolved_root"]=s.has_root?Variant(gs(s.resolved_root.view())):Variant();d["store_version"]=s.has_store_version?Variant(std::int64_t{1}):Variant();
 return d;
}
Variant LocalPlayersBoundary::poll(const Variant& maximum) {
 if(!owner()||maximum.get_type()!=Variant::INT)return Variant();
 const auto limit=static_cast<std::int64_t>(maximum);if(limit<1||limit>16)return Variant();
 Array delivered;if(!service_)return delivered;
 std::array<DeliveryView,16> views;std::array<std::uint64_t,16> leases;std::uint8_t count=0;
 if(!service_->peek(static_cast<std::uint8_t>(limit),views,count)||count>limit)return Variant();
 if(count==0)return delivered; // no outstanding batch/lease was created
 for(std::uint8_t i=0;i<count;++i)leases[i]=views[i].lease;
 const auto batch=std::span<const std::uint64_t>(leases.data(),count);
 struct Batch {
  Service* service;std::span<const std::uint64_t> leases;bool active{true};
  ~Batch(){if(active)service->abandon(leases);}
 } held{service_,batch};
 // Whole unique batch remains outstanding until every final owned tree passes.
 // Never deliver a prefix or acknowledge a partly converted result.
 try {
  for(std::uint8_t i=0;i<count;++i){Variant dto;if(!convert(views[i],dto))return Variant();delivered.append(dto);}
  if(!service_->acknowledge(batch))return Variant();
  held.active=false;return delivered;
 } catch(...) {
  // A catchable caller-output construction failure cannot consume the batch.
  // Engine-level fatal allocation failure is not misrepresented as recoverable.
  return Variant();
 }
}
bool LocalPlayersBoundary::begin_shutdown() noexcept {
 if(!owner())return false;if(service_)return service_->begin_shutdown();closing_=true;return true;
}
bool LocalPlayersBoundary::try_join() noexcept {
 if(!owner())return false;if(service_)return service_->try_join();if(!closing_&&!closed_)return false;closing_=false;closed_=true;return true;
}
Dictionary LocalPlayers::start(){return boundary_.start();}
Dictionary LocalPlayers::start_management(){return boundary_.start(true);}
Dictionary LocalPlayers::submit(const Variant& request){return boundary_.submit(request);}
Variant LocalPlayers::poll(const Variant& maximum){return boundary_.poll(maximum);}
Variant LocalPlayers::status() const{return boundary_.status();}
bool LocalPlayers::begin_shutdown(){return boundary_.begin_shutdown();}
bool LocalPlayers::try_join(){return boundary_.try_join();}
bool LocalPlayers::close_all() noexcept {
 if(!Service::begin_shutdown_registered())return false;
 return Service::try_join_registered();
}
void LocalPlayers::_bind_methods() {
 godot::ClassDB::bind_method(godot::D_METHOD("start"),&LocalPlayers::start);
 godot::ClassDB::bind_method(godot::D_METHOD("start_management"),&LocalPlayers::start_management);
 godot::ClassDB::bind_method(godot::D_METHOD("submit","request"),&LocalPlayers::submit);
 godot::ClassDB::bind_method(godot::D_METHOD("poll","max_results"),&LocalPlayers::poll,DEFVAL(std::int64_t{8}));
 godot::ClassDB::bind_method(godot::D_METHOD("status"),&LocalPlayers::status);
 godot::ClassDB::bind_method(godot::D_METHOD("begin_shutdown"),&LocalPlayers::begin_shutdown);
 godot::ClassDB::bind_method(godot::D_METHOD("try_join"),&LocalPlayers::try_join);
}
} // namespace flight::local_players::bridge
