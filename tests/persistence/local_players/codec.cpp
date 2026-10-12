// Original MIT. Independent fixed value references; pure codec/records only.
// No database, worker, Godot, OS-key roundtrip or lifecycle qualification.
#include "flight/local_players/codec.hpp"
#include "flight/local_players/records.hpp"
#include <algorithm>
#include <bit>
#include <cfenv>
#include <cstring>
#include <charconv>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#if defined(_M_X64) || defined(__x86_64__)
#include <xmmintrin.h>
#endif

namespace lp = flight::local_players;
namespace {
std::size_t checks{}, applicable{}, deferred{};
void require(bool ok, std::string_view label) {
  ++checks;
  if (!ok) throw std::runtime_error(std::string(label));
}
std::string hash(std::string_view bytes) {
  const auto h = lp::sha256_hex(bytes); return {h.data(),h.size()};
}
std::int64_t integer(std::string_view s) {
  std::int64_t v{}; const auto p = std::from_chars(s.data(),s.data()+s.size(),v);
  require(p.ec==std::errc{} && p.ptr==s.data()+s.size(),"reference signed integer"); return v;
}
std::uint64_t hexword(std::string_view s) {
  require(s.size()==16,"reference binary64 word length"); std::uint64_t v{};
  const auto p=std::from_chars(s.data(),s.data()+s.size(),v,16);
  require(p.ec==std::errc{} && p.ptr==s.data()+s.size(),"reference binary64 hex"); return v;
}
struct Parsed {
  std::string bytes; std::vector<lp::JsonCell> cells;
  std::vector<std::byte> duplicates; lp::DocumentView doc{};
  explicit Parsed(std::string text, bool must_succeed=true,
                  lp::Limits limits={655360,30000,32,8192,65536})
      : bytes(std::move(text)),cells(limits.values),duplicates(524288) {
    const auto r=lp::parse_json(bytes,cells,duplicates,limits);
    if (must_succeed) require(static_cast<bool>(r),"reference/fixture JSON parse");
    doc=r.value;
    if (!r) doc.root=lp::no_cell;
  }
};
std::uint32_t member(lp::DocumentView d,std::uint32_t n,std::string_view key) {
  const auto result=d.member(n,key); require(result!=lp::no_cell,"missing reference member"); return result;
}
const lp::JsonCell& cell(lp::DocumentView d,std::uint32_t n) {
  const auto* p=d.at(n); require(p!=nullptr,"reference cell bounds"); return *p;
}
std::string text(lp::DocumentView d,std::uint32_t n) {
  std::vector<char> out(65536); std::size_t used{};
  require(cell(d,n).kind==lp::ValueKind::string && lp::copy_string(d,n,out,used),"actual String reference");
  return {out.data(),used};
}
std::string field(lp::DocumentView d,std::uint32_t n,std::string_view key) {return text(d,member(d,n,key));}
bool boolean(lp::DocumentView d,std::uint32_t n) {
  const auto& c=cell(d,n); require(c.kind==lp::ValueKind::boolean && c.scalar<=1,"actual BOOL reference"); return c.scalar!=0;
}
std::int64_t number(lp::DocumentView d,std::uint32_t n) {
  const auto& c=cell(d,n); require(c.kind==lp::ValueKind::integer,"actual INT reference"); return std::bit_cast<std::int64_t>(c.scalar);
}
std::vector<std::uint32_t> children(lp::DocumentView d,std::uint32_t n) {
  require(cell(d,n).kind==lp::ValueKind::array || cell(d,n).kind==lp::ValueKind::object,"reference container");
  std::vector<std::uint32_t> out;
  for(auto c=cell(d,n).first;c!=lp::no_cell;c=cell(d,c).next) {
    require(out.size()<30000,"reference child cycle");out.push_back(c);
  }
  return out;
}
// Independent test-side literal typed tree. Does not call a production decoder
// to manufacture expected output. Strings and FLOAT bits are taken from frozen
// descriptors; enums are not normalized here.
struct V {
  lp::ValueKind kind{lp::ValueKind::null}; std::uint64_t bits{}; std::string str;
  std::vector<V> values; std::vector<std::pair<std::string,V>> fields;
  static V null() {return {};}
  static V b(bool x) {V v;v.kind=lp::ValueKind::boolean;v.bits=x?1U:0U;return v;}
  static V i(std::int64_t x) {V v;v.kind=lp::ValueKind::integer;v.bits=std::bit_cast<std::uint64_t>(x);return v;}
  static V f(std::uint64_t x) {V v;v.kind=lp::ValueKind::real;v.bits=x;return v;}
  static V s(std::string x) {V v;v.kind=lp::ValueKind::string;v.str=std::move(x);return v;}
  static V a(std::vector<V> x={}) {V v;v.kind=lp::ValueKind::array;v.values=std::move(x);return v;}
  static V o(std::vector<std::pair<std::string,V>> x) {V v;v.kind=lp::ValueKind::object;v.fields=std::move(x);return v;}
  V& get(std::string_view key) {for(auto& p:fields)if(p.first==key)return p.second;throw std::runtime_error("test builder key");}
};
V descriptor(lp::DocumentView d,std::uint32_t n) {
  const auto type=field(d,n,"type");
  if(type=="FLOAT") return V::f(hexword(field(d,n,"binary64_be_hex")));
  if(type=="INT") return V::i(integer(field(d,n,"decimal")));
  if(type=="BOOL") return V::b(boolean(d,member(d,n,"value")));
  throw std::runtime_error("unsupported independent descriptor");
}
struct Owned {
  std::string bytes;std::vector<lp::JsonCell> cells;
  explicit Owned(const V& v) {append(v,{});}
  std::uint32_t append(const V& v,std::string_view key) {
    require(cells.size()<30000 && key.size()<=UINT16_MAX,"typed test capture bound");
    const auto index=static_cast<std::uint32_t>(cells.size());
    lp::JsonCell c;c.kind=v.kind;c.scalar=v.bits;c.flags=1;
    c.key_offset=static_cast<std::uint32_t>(bytes.size());c.key_length=static_cast<std::uint16_t>(key.size());bytes+=key;
    c.offset=static_cast<std::uint32_t>(bytes.size());c.length=static_cast<std::uint32_t>(v.str.size());bytes+=v.str;
    cells.push_back(c);std::uint32_t previous=lp::no_cell;
    const auto add=[&](const V& item,std::string_view name) {
      const auto child=append(item,name);
      if(previous==lp::no_cell)cells[index].first=child;else cells[previous].next=child;
      previous=child;
    };
    for(const auto& item:v.values)add(item,{});
    for(const auto& item:v.fields)add(item.second,item.first);
    return index;
  }
  lp::DocumentView view() const {return {bytes,cells,0};}
};
V audio(V gain=V::f(UINT64_C(0x3ff0000000000000))) {
  return V::o({{"enabled",V::b(true)},{"engine_gain",std::move(gain)},
    {"airflow_gain",V::f(UINT64_C(0x3ff0000000000000))},{"show_panel_captions",V::b(true)}});
}
V preferences(V revision=V::s("1")) {
  return V::o({{"type",V::s("LocalPlayerPreferences")},{"version",V::i(1)},
    {"player_id",V::s("0123456789abcdef0123456789abcdef")},{"revision",std::move(revision)},
    {"legacy_input",V::null()},{"piston_input",V::null()},{"audio",audio()}});
}
std::string canonical(lp::DocumentView d,std::uint32_t n) {
  std::vector<char> storage(614400);lp::Writer w(storage);
  require(w.value(d,n),"canonical value writer");
  auto measure=lp::Writer::measure(storage.size());
  require(measure.value(d,n) && measure.size()==w.size(),"count-only matches actual bytes");
  require(measure.bytes().empty(),"count-only exposes no output");return std::string(w.bytes());
}
void binary64_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto bits=hexword(field(refs,member(refs,row,"input"),"binary64_be_hex"));
    const auto value=std::bit_cast<double>(bits);const bool finite=boolean(refs,member(refs,row,"finite_primitive"));
    require(lp::finite_binary64(value)==finite,"binary64 finite predicate");
    std::array<char,128> storage{};lp::Writer writer(storage);
    require(writer.binary64(value)==finite,"binary64 writer finite boundary");
    if(finite) {
      const auto expected="{\"$binary64_le\":\""+field(refs,member(refs,row,"expected_tag"),"$binary64_le")+"\"}";
      require(writer.bytes()==expected,"independent little-endian exact tag");
      Parsed encoded(expected);double restored{};
      require(lp::decode_binary64_tag(encoded.doc,encoded.doc.root,restored),"binary64 primitive decode");
      require(std::bit_cast<std::uint64_t>(restored)==bits,"binary64 restored exact bits including signed zero");
    } else require(!writer.good(),"nonfinite writer retains failure");
    Owned a(audio(V::f(bits)));
    require((lp::validate_audio(a.view(),0,false,a.cells)==lp::Error::none)==
      boolean(refs,member(refs,row,"audio_gain_semantic_admission")),"actual typed Audio admission");
    ++applicable;
  }
}
void bundle_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto payload=field(refs,row,"expected_payload_utf8"),envelope=field(refs,row,"expected_envelope_utf8");
    require(payload.size()==static_cast<std::size_t>(number(refs,member(refs,row,"payload_bytes"))) &&
      envelope.size()==static_cast<std::size_t>(number(refs,member(refs,row,"envelope_bytes"))),"independent byte lengths");
    require(hash(payload)==field(refs,row,"payload_sha256") && hash(envelope)==field(refs,row,"envelope_sha256"),"independent SHA256 bytes");
    Parsed p(payload);
    require(lp::validate_preferences(p.doc,p.doc.root,true,
      std::span<lp::JsonCell>(p.cells.data(),p.doc.cells.size()))==lp::Error::none,"whole tagged preferences admit");
    const auto version=member(p.doc,p.doc.root,"version"),revision=member(p.doc,p.doc.root,"revision");
    require(cell(p.doc,version).kind==lp::ValueKind::integer && cell(p.doc,revision).kind==lp::ValueKind::string,"whole restored header types");
    const auto types=member(refs,row,"restored_types"),a=member(p.doc,p.doc.root,"audio");
    for(const auto name:{"engine_gain","airflow_gain"}) {
      const auto actual=member(p.doc,a,name);const auto expected=member(refs,types,std::string("audio.")+name);
      require(cell(p.doc,actual).kind==lp::ValueKind::real && cell(p.doc,actual).scalar==
        hexword(field(refs,expected,"binary64_be_hex")),"whole restored gain type/bits");
    }
    require(cell(p.doc,member(p.doc,p.doc.root,"legacy_input")).kind==lp::ValueKind::null &&
      cell(p.doc,member(p.doc,p.doc.root,"piston_input")).kind==lp::ValueKind::null,"whole null slots retained");
    std::vector<char> output(614400),scratch(614400);lp::Writer w(output);
    require(lp::encode_preferences(p.doc,p.doc.root,w,scratch)==lp::Error::none && w.bytes()==envelope,"whole encoder matches frozen envelope");
    std::vector<lp::JsonCell> decoded_cells(30000);std::vector<char> work(2*1024*1024),decoded_payload(614400);std::atomic_flag lease{};
    const auto decoded=lp::decode_preferences(envelope,{decoded_cells,work,&lease},decoded_payload);
    require(static_cast<bool>(decoded) && lp::equal_values(p.doc,p.doc.root,decoded.value,decoded.value.root),"whole decoder typed equality");
    require(canonical(decoded.value,decoded.value.root)==payload,"whole decode/re-encode exact payload");
    auto corrupt=envelope;const auto digest=field(refs,row,"payload_sha256");const auto where=corrupt.find(digest);
    require(where!=std::string::npos,"fixture hash location");corrupt[where]=digest[0]=='0'?'1':'0';
    require(!lp::decode_preferences(corrupt,{decoded_cells,work,&lease},decoded_payload),"corrupt envelope hash rejection");
    require(!lp::decode_preferences(envelope+"{}",{decoded_cells,work,&lease},decoded_payload),"trailing envelope root rejection");
    ++applicable;
  }
}
void u64_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto input=member(refs,row,"input");const auto type=field(refs,input,"type");
    if(type=="StringName") {std::cout<<"DEFERRED "<<field(refs,row,"id")<<" actual Godot StringName boundary\n";++deferred;continue;}
    const bool generic=boolean(refs,member(refs,row,"canonical_u64")),positive=boolean(refs,member(refs,row,"positive_revision"));
    V revision;
    if(type=="String") {
      const auto s=field(refs,input,"value");lp::U64 result,positive_result;
      require(lp::U64::parse(s,result)==generic,"U64 lexical/full-range result");
      require(lp::U64::parse(s,positive_result,true)==positive,"positive revision U64 result");
      if(generic) { require(result.view()==s,"U64 exact decimal unchanged"); }
      revision=V::s(s);
    } else if(type=="INT")revision=V::i(number(refs,member(refs,input,"value")));
    else if(type=="FLOAT")revision=V::f(hexword(field(refs,input,"value")));
    else if(type=="BOOL")revision=V::b(boolean(refs,member(refs,input,"value")));
    else throw std::runtime_error("unknown U64 descriptor");
    Owned record(preferences(std::move(revision)));
    require((lp::validate_preferences(record.view(),0,false,record.cells)==lp::Error::none)==positive,"actual revision type and positivity boundary");
    ++applicable;
  }
}
void arithmetic_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto operands=children(refs,member(refs,row,"operands"));require(operands.size()==2,"two arithmetic operands");
    lp::U64 a,b,out;require(lp::U64::parse(text(refs,operands[0]),a) && lp::U64::parse(text(refs,operands[1]),b),"U64 input operands");
    require(lp::U64::parse("37",out),"output sentinel");const auto before=out;
    const auto operation=field(refs,row,"operation");const bool accepted=boolean(refs,member(refs,row,"accepted"));
    if(operation=="compare")require(lp::U64::compare(a,b)==number(refs,member(refs,row,"expected")),"U64 compare independent expected");
    else {
      bool actual{};
      if(operation=="checked_add") {require(b.view()=="1","increment-only frozen addition");actual=lp::U64::increment(a,out);}
      else {require(operation=="checked_subtract","known arithmetic operation");actual=lp::U64::subtract(a,b,out);}
      require(actual==accepted,"U64 checked arithmetic acceptance");
      if(actual)require(out.view()==field(refs,row,"expected"),"U64 exact arithmetic result");
      else require(out.view()==before.view(),"U64 failed arithmetic no partial mutation");
    }
    ++applicable;
  }
}
void spelling_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto s=field(refs,row,"input_scalars"),expected=field(refs,row,"expected_canonical_json");
    std::array<char,256> storage{};lp::Writer w(storage);require(lp::valid_utf8(s),"Unicode scalar input");
    require(w.string(s) && w.bytes()==expected,"literal Unicode/lowercase C0 spelling");
    Parsed p(expected);require(text(p.doc,p.doc.root)==s,"Unicode scalar exact restoration without NFC");++applicable;
  }
}
V keys(V value=V::i(65)) {return V::o({{"kind",V::s("physical_keys")},{"keys",V::a({std::move(value)})}});}
V device() {return V::o({{"slot",V::s("Stick")},{"label",V::s("")},{"match",V::o({
  {"guid",V::s("")},{"name",V::s("")},{"vendor_id",V::s("1234")},{"product_id",V::s("")}})}});}
V preset(int version) {
  std::vector<V> axes;
  for(const auto name:{"roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"})
    axes.push_back(V::o({{"target",V::s(name)},{"kind",V::s("fixed")},{"value",V::i(std::string_view(name)=="mixture"?1:0)}}));
  V p=V::o({{"type",V::s("InputPreset")},{"version",V::i(version)},{"name",V::s("Independent codec fixture")},
    {"devices",V::a({device()})},{"axes",V::a(std::move(axes))},{"actions",V::a()}});
  if(version==2) {
    p.fields.push_back({"profile",V::o({{"id",V::s("original-piston-prop-v1")},
      {"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})});
    p.fields.push_back({"capability_revision",V::s("piston-controls-v1")});
    std::vector<V> systems;std::int64_t key=75;
    for(const auto id:{"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"})
      systems.push_back(V::o({{"id",V::s(id)},{"kind",V::s(std::string_view(id)=="engine.starter"?"momentary":"toggle")},
        {"sources",V::a({keys(V::i(key++))})}}));
    p.fields.push_back({"systems",V::a(std::move(systems))});
  }
  return p;
}
V pair_axis() {return V::o({{"target",V::s("pitch")},{"kind",V::s("key_pair")},
  {"negative",V::a({V::i(65)})},{"positive",V::a({V::i(68)})},{"rate",V::i(1)},
  {"gain",V::i(1)},{"return_to_start",V::b(true)}});}
V joy_axis() {return V::o({{"target",V::s("roll")},{"kind",V::s("joy_axis")},
  {"slot",V::s("Stick")},{"index",V::i(0)},{"range",V::s("centered")},
  {"minimum",V::i(-1)},{"center",V::i(0)},{"maximum",V::i(1)},{"invert",V::b(false)},
  {"deadzone",V::i(0)},{"saturation",V::i(1)},{"gain",V::i(1)},{"slew_per_s",V::i(0)}});}
V source_for(int n,V value) {
  if(n==14 || n==17)return keys(std::move(value));
  if(n==15 || n==18)return V::o({{"kind",V::s("joy_button")},{"slot",V::s("Stick")},{"index",std::move(value)}});
  return V::o({{"kind",V::s("mouse_button")},{"button",std::move(value)}});
}
// Complete context for every field-only witness. The independent reference's
// engine.fuel_feed path denotes the accepted v2 binding id fuel.feed. All FOUR
// actual required system bindings are present, not a one-system surrogate.
V family_fixture(int n,V value) {
  if(n==20)return audio(std::move(value));
  V p=preset(n==5 || n>=17?2:1);
  if(n==1)p.get("version")=std::move(value);
  else if(n>=2 && n<=5)p.get("axes").values[n==2?0U:n==3?3U:4U].get("value")=std::move(value);
  else if(n>=6 && n<=8) {
    V axis=pair_axis();
    if(n==6)axis.get("negative").values[0]=std::move(value);
    else axis.get(n==7?"rate":"gain")=std::move(value);
    p.get("axes").values[1]=std::move(axis);
  } else if(n>=9 && n<=13) {
    V axis=joy_axis();const std::array<std::string_view,5> names{"index","minimum","deadzone","saturation","slew_per_s"};
    axis.get(names[static_cast<std::size_t>(n-9)])=std::move(value);p.get("axes").values[0]=std::move(axis);
  } else if(n>=14 && n<=16) {
    p.get("actions").values.push_back(V::o({{"id",V::s("help")},{"sources",V::a({source_for(n,std::move(value))})}}));
  } else {
    require(n>=17 && n<=19,"known numeric family");p.get("systems").values[3].get("sources").values[0]=source_for(n,std::move(value));
  }
  return p;
}
std::uint32_t nth(lp::DocumentView d,std::uint32_t n,std::size_t index) {
  const auto all=children(d,n);require(index<all.size(),"test path index");return all[index];
}
std::uint32_t family_leaf(lp::DocumentView d,int n) {
  if(n==20)return member(d,0,"engine_gain");
  if(n==1)return member(d,0,"version");
  if(n>=2 && n<=5)return member(d,nth(d,member(d,0,"axes"),n==2?0U:n==3?3U:4U),"value");
  if(n>=6 && n<=8) {
    const auto axis=nth(d,member(d,0,"axes"),1);
    return n==6?nth(d,member(d,axis,"negative"),0):member(d,axis,n==7?"rate":"gain");
  }
  if(n>=9 && n<=13) {
    const std::array<std::string_view,5> names{"index","minimum","deadzone","saturation","slew_per_s"};
    return member(d,nth(d,member(d,0,"axes"),0),names[static_cast<std::size_t>(n-9)]);
  }
  const auto binding=nth(d,member(d,0,n>=17?"systems":"actions"),n>=17?3U:0U);
  const auto source=nth(d,member(d,binding,"sources"),0);
  if(n==14 || n==17)return nth(d,member(d,source,"keys"),0);
  return member(d,source,n==15 || n==18?"index":"button");
}
lp::Error validate_family(Owned& o,int n,bool mutable_span=true) {
  const auto cells=mutable_span?std::span<lp::JsonCell>(o.cells):std::span<lp::JsonCell>{};
  return n==20?lp::validate_audio(o.view(),0,false,cells):
    lp::validate_preset(o.view(),0,n==5 || n>=17?2:1,false,cells);
}
void family_cases(lp::DocumentView refs,std::uint32_t group) {
  int n=0;
  for(const auto row:children(refs,group)) {
    ++n;const auto original=descriptor(refs,member(refs,row,"admitted_field_input"));
    const auto expected=descriptor(refs,member(refs,row,"expected_normalized_field"));
    Owned good(family_fixture(n,original));
    require(lp::validate_capture(good.view())==lp::Error::none,"independent direct capture structural admission");
    require(validate_family(good,n)==lp::Error::none,"complete numeric-family positive context");
    const auto leaf=family_leaf(good.view(),n);const auto& c=cell(good.view(),leaf);
    require(c.kind==expected.kind && c.scalar==expected.bits,"numeric-family exact normalization/type/bits");
    const auto storage=member(refs,row,"expected_storage");std::string expected_bytes;
    if(cell(refs,storage).kind==lp::ValueKind::string)expected_bytes=text(refs,storage);
    else expected_bytes="{\"$binary64_le\":\""+field(refs,storage,"$binary64_le")+"\"}";
    require(canonical(good.view(),leaf)==expected_bytes,"numeric-family exact encoded leaf");
    Owned bad(family_fixture(n,descriptor(refs,member(refs,row,"rejected_field_input"))));
    require(validate_family(bad,n)!=lp::Error::none,"complete numeric-family negative context");
    if(original.kind==lp::ValueKind::real && expected.kind==lp::ValueKind::integer) {
      Owned no_copy(family_fixture(n,original));
      require(validate_family(no_copy,n,false)==lp::Error::out_of_memory,"enum normalization requires owned mutable span");
      require(cell(no_copy.view(),family_leaf(no_copy.view(),n)).kind==lp::ValueKind::real,"no mutation through const-only capture");
    }
    ++applicable;
  }
  require(n==20,"all twenty independent numeric families consumed");
}
std::string envelope_for(std::string_view payload) {
  Owned e(V::o({{"format",V::s("LocalPlayerPreferences")},{"version",V::i(1)},
    {"payload_json",V::s(std::string(payload))},{"payload_sha256",V::s(hash(payload))}}));
  return canonical(e.view(),0);
}
void replace_once(std::string& input,std::string_view before,std::string_view after) {
  const auto pos=input.find(before);require(pos!=std::string::npos && input.find(before,pos+before.size())==std::string::npos,"unique malformed fixture location");
  input.replace(pos,before.size(),after);
}
void negative_cases(lp::DocumentView refs,std::uint32_t group) {
  for(const auto row:children(refs,group)) {
    const auto id=field(refs,row,"id"),fragment=field(refs,row,"encoded_fragment");
    V bundle=preferences();bundle.get("legacy_input")=preset(1);Owned valid(bundle);
    require(lp::validate_preferences(valid.view(),0,false,valid.cells)==lp::Error::none,"negative control baseline is valid");
    auto payload=canonical(valid.view(),0);
    if(id=="N_naked_fraction" || id=="N_naked_exponent" || id=="N_wrong_tag_key" ||
        id=="N_uppercase_tag" || id=="N_short_tag" || id=="N_tag_extra")
      replace_once(payload,"\"engine_gain\":{\"$binary64_le\":\"000000000000f03f\"}","\"engine_gain\":"+fragment);
    else if(id=="N_negative_integer_zero" || id=="N_leading_integer_zero")
      replace_once(payload,"\"target\":\"roll\",\"value\":0","\"target\":\"roll\",\"value\":"+fragment);
    else if(id=="N_enum_tag") {
      const auto start=payload.find("\"legacy_input\":");require(start!=std::string::npos,"legacy slot");
      const auto pos=payload.find("\"version\":1",start);require(pos!=std::string::npos,"preset version location");
      payload.replace(pos,11,"\"version\":"+fragment);
    } else if(id=="N_revision_number")replace_once(payload,"\"revision\":\"1\"","\"revision\":"+fragment);
    else if(id=="N_digit_vendor_number")replace_once(payload,"\"vendor_id\":\"1234\"","\"vendor_id\":"+fragment);
    else if(id=="N_duplicate_key")payload.insert(1,"\"version\":1,");
    else if(id=="N_escaped_key")replace_once(payload,"\"type\":\"LocalPlayerPreferences\"","\"t\\u0079pe\":\"LocalPlayerPreferences\"");
    else if(id=="N_lone_surrogate")replace_once(payload,"\"name\":\"Independent codec fixture\"","\"name\":"+fragment);
    else if(id=="N_trailing_comma")payload.insert(payload.size()-1,",");
    else if(id=="N_trailing_root")payload+="{}";
    else throw std::runtime_error("unmapped encoded negative");
    std::vector<lp::JsonCell> cells(30000);std::vector<char> work(2*1024*1024),scratch(614400);std::atomic_flag lease{};
    // Correct outer SHA ensures rejection is for the bad inner structure/type,
    // not a meaningless hash mismatch masking the intended negative.
    require(!lp::decode_preferences(envelope_for(payload),{cells,work,&lease},scratch),"contextual frozen encoded rejection");++applicable;
  }
}
// Exact independent literals projected from the frozen hypothetical taxi
// packet 0ae22514067840455e4e01fb65cde1c39015e731937ff6971df030ce81a0d811.
// No current native fingerprint is asserted. Ten export rows test ONLY their
// complete summary Practice projection, not envelopes/SQL/transaction state.
void apron_source_domain() {
  const auto source_check=[](V value,bool accepted,std::string_view label) {
    Owned capture(value);const auto bytes=capture.bytes;const auto cells=capture.cells;
    require((lp::validate_source(capture.view(),0)==lp::Error::none)==accepted,label);
    require(capture.bytes==bytes && capture.cells.size()==cells.size() &&
      std::memcmp(capture.cells.data(),cells.data(),cells.size()*sizeof(lp::JsonCell))==0,
      "PracticeSource admission never mutates owned input");
  };
  const V legacy=V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}});
  const V piston=V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}});
  const char* variants[]={"jsbsim-1.3.1-upstream","jsbsim-1.3.1-event-aware-constant-power-v1",
    "jsbsim-1.3.1-event-aware-coupled-midpoint-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"};
  for(const auto& pair:std::vector<std::pair<V,bool>>{{legacy,false},{piston,true}}) {
    source_check(pair.first,true,"frozen calm-only apron source valid");
    for(const auto wind:{"from-north","from-west","from-east"}) {
      V bad=pair.first;bad.get("wind_profile")=V::s(wind);source_check(bad,false,"apron noncalm rejection");
    }
    for(int variant=0;variant<4;++variant) {
      V admitted=pair.first;admitted.get("source_variant")=V::s(variants[variant]);
      source_check(admitted,!pair.second||variant==3,"legacy apron preserves all four variants; piston apron requires local-window-v2");
      for(const auto wind:{"from-north","from-west","from-east"}) {
        V windy=admitted;windy.get("wind_profile")=V::s(wind);source_check(windy,false,"every apron variant rejects noncalm wind");
      }
      V wrong_method=admitted;
      wrong_method.get("angular_integration_method")=pair.second?V::null():V::s("event_aware_coupled_midpoint_v1");
      source_check(wrong_method,false,"every apron variant retains exact profile angular method");
      V crossed_model=admitted;V other_model=pair.second?legacy:piston;
      crossed_model.get("model_identity")=other_model.get("model_identity");
      source_check(crossed_model,false,"every apron variant rejects crossed model/start");
      V extra_field=admitted;extra_field.fields.push_back({"extra",V::null()});
      source_check(extra_field,false,"every apron variant rejects extra source fields");
    }
    V typed_variant=pair.first;typed_variant.get("source_variant")=V::i(3);
    source_check(typed_variant,false,"apron source variant requires String");
    V crossed=pair.first;V other=pair.second?legacy:piston;crossed.get("model_identity")=other.get("model_identity");
    source_check(crossed,false,"crossed apron model rejects");
    V extra=pair.first;extra.fields.push_back({"extra",V::null()});source_check(extra,false,"closed eight-key source rejects extra field");
    V wrong=pair.first;wrong.get("named_start")=V::i(0);source_check(wrong,false,"start String type remains strict");
    V unknown=pair.first;unknown.get("source_variant")=V::s("unknown");source_check(unknown,false,"unknown source variant rejects");
    V angular=pair.first;angular.get("angular_integration_method")=pair.second?V::null():V::s("event_aware_coupled_midpoint_v1");
    source_check(angular,false,"apron angular method remains profile exact");
    V oldmethod=pair.first;oldmethod.get("angular_integration_method")=V::s("event_aware_constant_power_v1");
    source_check(oldmethod,false,"apron rejects historical constant-power method");
  }
  for(const auto start:{"ground-ready","airborne-prepared"})
    for(const auto wind:{"calm","from-north","from-west","from-east"})
      for(const auto variant:variants) {
        V old=legacy;old.get("named_start")=V::s(start);old.get("wind_profile")=V::s(wind);old.get("source_variant")=V::s(variant);
        source_check(old,true,"all eight historical legacy tuples preserve all old variants");
      }
  for(int variant=0;variant<4;++variant) {
    V old=piston;old.get("named_start")=V::s("piston-cold-ground");old.get("source_variant")=V::s(variants[variant]);
    old.get("angular_integration_method")=V::s(variant==1?"event_aware_constant_power_v1":"event_aware_coupled_midpoint_v1");
    source_check(old,variant!=0,"old cold-ground variant/method admission preserved");
    for(const auto wind:{"from-north","from-west","from-east"}) {
      V windy=old;windy.get("wind_profile")=V::s(wind);source_check(windy,false,"old cold-ground calm-only rejection preserved");
    }
  }
  struct PracticeCase {const char* id;bool summary;bool valid;V value;};
  const std::vector<PracticeCase> rows={
    {"legacy-practice-max-u64-active",false,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:00Z")},{"first_tick",V::s("18446744073709551615")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("0")},{"tick_rate_hz",V::i(120)},{"status",V::s("active")},{"end_reason",V::null()},{"revision",V::s("1")},{"creation_sequence",V::s("18446744073709551615")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"legacy-practice-max-u64-active-export",true,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:00Z")},{"first_tick",V::s("18446744073709551615")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("0")},{"tick_rate_hz",V::i(120)},{"status",V::s("active")},{"end_reason",V::null()},{"revision",V::s("1")},{"creation_sequence",V::s("18446744073709551615")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"legacy-practice-max-u64-ended",false,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551614")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"legacy-practice-max-u64-ended-export",true,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551614")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"legacy-practice-u64-bad-leading-zero",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("00")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"legacy-practice-u64-bad-leading-zero-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("00")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"legacy-practice-u64-bad-actual-int",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::i(0)},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"legacy-practice-u64-bad-actual-int-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::i(0)},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"legacy-practice-u64-bad-overflow",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551616")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"legacy-practice-u64-bad-overflow-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("5fcc5f1fcf2983157c57140ebfa35f9b")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-legacy")},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("apron-ready")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551616")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"piston-practice-max-u64-active",false,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:00Z")},{"first_tick",V::s("18446744073709551615")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("0")},{"tick_rate_hz",V::i(120)},{"status",V::s("active")},{"end_reason",V::null()},{"revision",V::s("1")},{"creation_sequence",V::s("18446744073709551615")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"piston-practice-max-u64-active-export",true,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:00Z")},{"first_tick",V::s("18446744073709551615")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("0")},{"tick_rate_hz",V::i(120)},{"status",V::s("active")},{"end_reason",V::null()},{"revision",V::s("1")},{"creation_sequence",V::s("18446744073709551615")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"piston-practice-max-u64-ended",false,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551614")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"piston-practice-max-u64-ended-export",true,true,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551614")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"piston-practice-u64-bad-leading-zero",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("00")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"piston-practice-u64-bad-leading-zero-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("00")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"piston-practice-u64-bad-actual-int",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::i(0)},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"piston-practice-u64-bad-actual-int-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::i(0)},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
    {"piston-practice-u64-bad-overflow",false,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551616")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::null()}})},
    {"piston-practice-u64-bad-overflow-export",true,false,V::o({{"type",V::s("LocalPractice")},{"version",V::i(1)},{"id",V::s("f80f43578e6ac601fb3f21c83f3b8761")},{"player_id",V::s("c9dc330519d98a40814b2d5b0a384ec9")},{"source",V::o({{"session_id",V::s("hypothetical-taxi-piston")},{"model_identity",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}})},{"source_variant",V::s("jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")},{"native_source_fingerprint",V::s("44f5320f3d63e0ff6f9942ec4a4f29177f51b18cbf1c2742650294c45541054b")},{"prepared_world_sha256",V::s("04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5")},{"named_start",V::s("piston-cold-apron")},{"wind_profile",V::s("calm")},{"angular_integration_method",V::s("event_aware_coupled_midpoint_v1")}})},{"started_utc",V::s("2026-10-11T00:00:00Z")},{"last_observed_utc",V::s("2026-10-11T00:00:01Z")},{"first_tick",V::s("18446744073709551495")},{"last_tick",V::s("18446744073709551615")},{"observed_ticks",V::s("120")},{"tick_rate_hz",V::i(120)},{"status",V::s("manually_ended")},{"end_reason",V::s("user_end")},{"revision",V::s("2")},{"creation_sequence",V::s("18446744073709551616")},{"commit_sequence",V::s("18446744073709551615")},{"archive",V::o({{"linked",V::b(false)}})}})},
  };
  require(rows.size()==20,"exact twenty frozen taxi whole-value Practice projections");
  for(const auto& row:rows) {
    Owned practice(row.value);const auto bytes=practice.bytes;const auto cells=practice.cells;
    const auto source=member(practice.view(),0,"source");
    require(lp::validate_source(practice.view(),source)==lp::Error::none,"all twenty numeric witnesses have valid apron sources");
    require((lp::validate_practice(practice.view(),0,row.summary)==lp::Error::none)==row.valid,row.id);
    require(practice.bytes==bytes && practice.cells.size()==cells.size() &&
      std::memcmp(practice.cells.data(),cells.data(),cells.size()*sizeof(lp::JsonCell))==0,
      "exact full-U64 String/INT and rejection leave owned Practice unchanged");
  }
  std::cout<<"APRON_PRACTICE_VALUE_REFERENCES rows=20 direct=10 export_summary_projections=10 scope=pure_records_no_export_encoder_or_SQLite\n";
}

void supplemental() {
  require(hash("")=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","independent empty SHA vector");
  require(hash("abc")=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","independent abc SHA vector");
  for(const auto& raw:{std::string("\xc0\x80",2),std::string("\xed\xa0\x80",3),std::string("\xf4\x90\x80\x80",4),std::string("\x80",1)})
    require(!lp::valid_utf8(raw),"UTF8 overlong/surrogate/out-of-range/continuation rejection");
  Parsed duplicate("{\"a\":0,\"a\":1}",false);require(duplicate.doc.root==lp::no_cell,"generic duplicate scanner rejection");
  std::vector<lp::JsonCell> cells(16);std::vector<std::byte> pairs(524288);
  require(!lp::parse_json("[0,1]",cells,pairs,lp::Limits{1024,2,12,1024,4096}),"value count cap counts root and values");
  require(static_cast<bool>(lp::parse_json("{\"a\":0}",cells,pairs,lp::Limits{1024,2,12,1024,4096})),"keys do not add scanner values");
  require(!lp::parse_json("[[]]",cells,pairs,lp::Limits{1024,16,1,1024,4096}),"nested container depth cap");
  require(static_cast<bool>(lp::parse_json("[0]",cells,pairs,lp::Limits{1024,16,1,1024,4096})),"primitive does not add container depth");
  std::array<char,3> output{'x','x','x'};lp::Writer small(output);require(!small.string("long"),"writer output bound");
  auto count=lp::Writer::measure(3);require(!count.string("long"),"count-only output bound");
  Owned structure(V::a({V::i(1)}));structure.cells[1].next=1;
  require(lp::validate_capture(structure.view())!=lp::Error::none,"captured child cycle rejects");
  Owned alias(V::a({V::i(1)}));alias.cells.push_back(lp::JsonCell{});
  require(lp::validate_capture(alias.view())!=lp::Error::none,"unreachable capture cell rejects");
}
void deferred_groups(lp::DocumentView refs,std::uint32_t root) {
  for(const auto group:{"paging","revision_recipes","copy_and_boundary_recipes"})
    for(const auto row:children(refs,member(refs,root,group))) {
      std::cout<<"DEFERRED "<<field(refs,row,"id")<<" actual store/service/bridge gate; not a codec pass\n";++deferred;
    }
}
void references(const std::string& bytes) {
  require(bytes.size()==54200 && hash(bytes)=="1ffaa82ae54a18dc5c9ec3d6c49760ed3b2d6c27abf77783572c6a9b3902d962","frozen original reference raw size/SHA");
  Parsed p(bytes);const auto d=p.doc;const auto r=d.root;
  require(lp::closed(d,r,{"schema","status","license","scope","binary64","numeric_families","canonical_bundles","u64","arithmetic","paging","encoded_rejections","revision_recipes","copy_and_boundary_recipes","string_spelling","limitations","case_counts","total_cases"})==lp::Error::none,"closed reference root");
  require(field(d,r,"schema")=="IndependentLocalPlayersValueReferences/v1" && number(d,member(d,r,"total_cases"))==114,"reference schema/count");
  const std::array<std::pair<std::string_view,std::size_t>,10> counts{{{"binary64",18},{"numeric_families",20},{"canonical_bundles",3},{"u64",23},{"arithmetic",13},{"paging",5},{"encoded_rejections",16},{"revision_recipes",5},{"copy_and_boundary_recipes",8},{"string_spelling",3}}};
  std::set<std::string> ids;std::size_t total=0;
  for(const auto& [name,count]:counts) {
    const auto rows=children(d,member(d,r,name));require(rows.size()==count,"exact reference category roster");
    require(number(d,member(d,member(d,r,"case_counts"),name))==static_cast<std::int64_t>(count),"declared category count");total+=count;
    if(name!="string_spelling")for(const auto row:rows)require(ids.insert(field(d,row,"id")).second,"unique reference ID");
  }
  require(total==114,"all frozen reference rows accounted");
  binary64_cases(d,member(d,r,"binary64"));family_cases(d,member(d,r,"numeric_families"));
  bundle_cases(d,member(d,r,"canonical_bundles"));u64_cases(d,member(d,r,"u64"));
  arithmetic_cases(d,member(d,r,"arithmetic"));negative_cases(d,member(d,r,"encoded_rejections"));
  spelling_cases(d,member(d,r,"string_spelling"));deferred_groups(d,r);
  require(applicable==95 && deferred==19,"explicit applicable/deferred roster; not 114 codec passes");
}

// The accepted full-record fixture is an independent typed/byte oracle. This
// reader restores its literal descriptor bits; it never normalizes expectations
// through a production decoder. STRING_NAME remains a real Godot-only case.
std::string unhex(std::string_view value) {
  require(value.size()%2==0,"frozen even lowercase hex bytes");
  std::string out;out.reserve(value.size()/2);
  const auto nibble=[](char c)->unsigned {
    require((c>='0'&&c<='9')||(c>='a'&&c<='f'),"frozen lowercase hex digit");
    return c<='9'?static_cast<unsigned>(c-'0'):static_cast<unsigned>(c-'a'+10);
  };
  for(std::size_t i=0;i<value.size();i+=2)
    out.push_back(static_cast<char>((nibble(value[i])<<4)|nibble(value[i+1])));
  return out;
}
V full_descriptor(lp::DocumentView d,std::uint32_t n) {
  const auto type=field(d,n,"type");
  if(type=="NIL")return V::null();
  if(type=="BOOL")return V::b(boolean(d,member(d,n,"value")));
  if(type=="INT")return V::i(integer(field(d,n,"decimal")));
  if(type=="STRING")return V::s(field(d,n,"value"));
  if(type=="FLOAT") {
    const auto raw=unhex(field(d,n,"binary64_le"));require(raw.size()==8,"frozen eight-byte FLOAT");
    std::uint64_t bits{};
    for(std::size_t i=0;i<8;++i)bits|=static_cast<std::uint64_t>(static_cast<unsigned char>(raw[i]))<<(8*i);
    return V::f(bits);
  }
  if(type=="ARRAY") {
    V out=V::a();for(const auto v:children(d,member(d,n,"values")))out.values.push_back(full_descriptor(d,v));return out;
  }
  require(type=="DICTIONARY","frozen supported typed descriptor, no StringName coercion");
  V out=V::o({});std::set<std::string> keys;
  for(const auto entry:children(d,member(d,n,"entries"))) {
    auto key=field(d,entry,"key");require(keys.insert(key).second,"unique frozen descriptor key");
    out.fields.emplace_back(std::move(key),full_descriptor(d,member(d,entry,"value")));
  }
  return out;
}
bool exact_tree(lp::DocumentView a,std::uint32_t x,lp::DocumentView b,std::uint32_t y) {
  const auto& u=cell(a,x);const auto& v=cell(b,y);
  if(u.kind!=v.kind)return false;
  if(u.kind==lp::ValueKind::real||u.kind==lp::ValueKind::integer||u.kind==lp::ValueKind::boolean)return u.scalar==v.scalar;
  if(u.kind==lp::ValueKind::string)return text(a,x)==text(b,y);
  if(u.kind==lp::ValueKind::null)return true;
  const auto ac=children(a,x),bc=children(b,y);if(ac.size()!=bc.size())return false;
  for(std::size_t i=0;i<ac.size();++i) {
    auto other=bc[i];
    if(u.kind==lp::ValueKind::object) {
      std::array<char,128> key{};std::size_t used{};
      require(lp::copy_key(a,ac[i],key,used),"actual normalized key bytes");
      other=b.member(y,{key.data(),used});if(other==lp::no_cell)return false;
    }
    if(!exact_tree(a,ac[i],b,other))return false;
  }
  return true;
}
bool unchanged(const Owned& value,const std::string& bytes,const std::vector<lp::JsonCell>& cells) {
  return value.bytes==bytes&&value.cells.size()==cells.size()&&
    std::memcmp(value.cells.data(),cells.data(),cells.size()*sizeof(lp::JsonCell))==0;
}
std::string frozen_bytes(lp::DocumentView d,std::uint32_t n) {
  const auto raw=unhex(field(d,n,"utf8_hex"));
  require(raw.size()==static_cast<std::size_t>(number(d,member(d,n,"bytes")))&&hash(raw)==field(d,n,"sha256"),
    "independent complete byte/count/digest witness");return raw;
}
std::string read_frozen(const std::filesystem::path& path,std::size_t size,std::string_view digest) {
  require(std::filesystem::is_regular_file(std::filesystem::symlink_status(path)),"ordinary full-record reference");
  std::ifstream in(path,std::ios::binary);require(static_cast<bool>(in),"full-record reference opens");
  std::string raw(size+1,'\0');in.read(raw.data(),static_cast<std::streamsize>(raw.size()));raw.resize(static_cast<std::size_t>(in.gcount()));
  require(!in.bad()&&raw.size()==size&&hash(raw)==digest,"frozen full-record size and SHA");return raw;
}
void full_preferences(lp::DocumentView d,std::uint32_t row) {
  const auto expected=member(d,row,"expected");const bool valid=boolean(d,member(d,expected,"valid"));
  Owned original(full_descriptor(d,member(d,row,"input")));const auto bytes=original.bytes;const auto cells=original.cells;
  Owned working=original;
  const auto error=lp::validate_preferences(working.view(),0,false,working.cells);
  require((error==lp::Error::none)==valid,"complete preferences expected admission");
  require(unchanged(original,bytes,cells),"normalization/rejection never touches caller-owned source copy");
  if(!valid) {
    // Rejection may normalize the private working capture before discovering a
    // later invalid field. Do not falsely demand transactional in-place enums.
    std::vector<char> out(lp::max_preferences),scratch(lp::max_preferences);lp::Writer writer(out);
    require(lp::encode_preferences(working.view(),0,writer,scratch)!=lp::Error::none,
      "rejected whole preferences cannot be encoded");return;
  }
  Owned normalized(full_descriptor(d,member(d,expected,"normalized")));
  require(exact_tree(working.view(),0,normalized.view(),0),"complete normalized expected types/bits/strings");
  const auto payload=frozen_bytes(d,member(d,expected,"payload")),envelope=frozen_bytes(d,member(d,expected,"envelope"));
  require(canonical(working.view(),0)==payload,"complete normalized canonical payload exact bytes");
  const auto working_bytes=working.bytes;const auto working_cells=working.cells;
  require(lp::validate_preferences(working.view(),0,false,working.cells)==lp::Error::none&&unchanged(working,working_bytes,working_cells),
    "complete normalization idempotent without changing continuous INT/FLOAT bits");
  std::vector<char> out(lp::max_preferences),scratch(lp::max_preferences);lp::Writer writer(out);
  require(lp::encode_preferences(working.view(),0,writer,scratch)==lp::Error::none&&writer.bytes()==envelope,
    "complete preferences encoder exact independently frozen envelope");
  require(unchanged(working,working_bytes,working_cells),"encoder preserves normalized owned input");
  std::vector<lp::JsonCell> restored_cells(30000);std::vector<char> workspace(2*1024*1024),decoded_payload(lp::max_preferences);std::atomic_flag lease{};
  const auto restored=lp::decode_preferences(envelope,{restored_cells,workspace,&lease},decoded_payload);
  require(static_cast<bool>(restored),"complete preferences decoder admits frozen envelope");
  Owned decoded(full_descriptor(d,member(d,expected,"decoded")));
  require(exact_tree(restored.value,restored.value.root,decoded.view(),0),"complete decoded independent types/bits/strings");
  require(canonical(restored.value,restored.value.root)==payload,"complete decoded canonical payload exact bytes");
  writer.reset();require(lp::encode_preferences(restored.value,restored.value.root,writer,scratch)==lp::Error::none&&writer.bytes()==envelope,
    "complete decoded envelope exact re-encoding");
}
void full_plain_record(lp::DocumentView d,std::uint32_t row,std::string_view group) {
  Owned input(full_descriptor(d,member(d,row,"input")));const auto bytes=input.bytes;const auto cells=input.cells;
  const auto expected=member(d,row,"expected");
  const bool valid=boolean(d,member(d,expected,group=="complete_source"?"shape_and_tuple_valid":"valid"));
  const auto error=group=="complete_player"?lp::validate_player(input.view(),0):
    group=="complete_source"?lp::validate_source(input.view(),0):lp::validate_practice(input.view(),0);
  require((error==lp::Error::none)==valid,"complete Player/Practice/source admission");
  require(unchanged(input,bytes,cells),"complete record admission/rejection preserves all input bytes/cells");
  if(group=="complete_source")require(!boolean(d,member(d,expected,"current_flight_authority")),"source fixture grants no current flight authority");
  const auto canonical_node=d.member(expected,"canonical");
  if(valid&&canonical_node!=lp::no_cell&&cell(d,canonical_node).kind!=lp::ValueKind::null)
    require(canonical(input.view(),0)==frozen_bytes(d,canonical_node),"complete record canonical frozen bytes");
}
void full_wire(lp::DocumentView d,std::uint32_t row) {
  const auto wire=frozen_bytes(d,member(d,row,"input")),before=wire;
  std::vector<lp::JsonCell> cells(30000);std::vector<char> work(2*1024*1024),payload(lp::max_preferences);std::atomic_flag lease{};
  const auto result=lp::decode_preferences(wire,{cells,work,&lease},payload);
  require(!boolean(d,member(d,member(d,row,"expected"),"valid"))&&!result&&result.value.root==lp::no_cell,
    "complete frozen corruption rejects without published partial document");
  require(wire==before,"corrupt decoder leaves exact wire unchanged");
}
void full_scanner(lp::DocumentView d,std::uint32_t row,std::string_view group) {
  const auto input=member(d,row,"input"),expected=member(d,row,"expected");
  std::string raw;lp::Limits limits;lp::Error wanted=lp::Error::invalid_record;
  if(group=="scanner_negative")raw=unhex(field(d,input,"utf8_hex"));
  else {
    const bool within=boolean(d,member(d,expected,"within_this_cap_only"));
    require(!boolean(d,member(d,expected,"semantic_record_admission")),"scanner pass is never semantic admission");
    const auto expansion=d.member(input,"expand_exact");
    if(expansion==lp::no_cell) {
      raw=unhex(field(d,input,"utf8_hex"));wanted=within?lp::Error::none:lp::Error::payload_limit;
    } else {
      const auto kind=text(d,expansion);const auto count=static_cast<std::size_t>(number(d,member(d,input,"count")));
      const auto limit=static_cast<std::size_t>(number(d,member(d,input,"limit")));
      if(kind=="UTF8_ASCII_SPACE") {
        raw.assign(count,' ');limits.bytes=limit;wanted=within?lp::Error::invalid_record:lp::Error::payload_limit;
      } else if(kind=="U+1F600") {
        raw="\"";for(std::size_t i=0;i<count;++i)raw+="\xf0\x9f\x98\x80";raw+='"';
        wanted=within?lp::Error::none:lp::Error::payload_limit;
      } else {
        require(kind=="ARRAY_TOTAL_VALUES_INCLUDING_ROOT"&&count>=1,"fixed original value-count expansion");
        raw="[";for(std::size_t i=1;i<count;++i){if(i>1)raw+=',';raw+='0';}raw+=']';
        wanted=within?lp::Error::none:lp::Error::payload_limit;
      }
    }
  }
  const auto before=raw;std::vector<lp::JsonCell> cells(30001);std::vector<std::byte> duplicates(524288);
  const auto parsed=lp::parse_json(raw,cells,duplicates,limits);
  require(parsed.error==wanted,"actual scanner fixed grammar/byte/value/depth/scalar boundary error");
  require(raw==before,"scanner leaves exact supplied bytes unchanged");
}
// These projected checks exercise actual codec APIs, not the store's optimistic
// revision decisions or selected-player export implementation. Report partial.
void full_projection(lp::DocumentView d,std::uint32_t row,std::string_view group) {
  const auto input=member(d,row,"input");const auto id=field(d,row,"id");
  if(group=="equality_revision") {
    Owned a(full_descriptor(d,member(d,input,"current_preferences"))),b(full_descriptor(d,member(d,input,"new_preferences")));
    const auto ab=a.bytes,bb=b.bytes;const auto ac=a.cells,bc=b.cells;
    require(lp::validate_preferences(a.view(),0,false,a.cells)==lp::Error::none&&
      lp::validate_preferences(b.view(),0,false,b.cells)==lp::Error::none,"full equality operands admitted");
    require(lp::equal_values(a.view(),0,b.view(),0)==(id!="E_signed_zero_changes"),"frozen equality projection preserves signed zero distinction");
    require(unchanged(a,ab,ac)&&unchanged(b,bb,bc),"already-normalized equality operands unchanged");
    return;
  }
  Owned snapshot(full_descriptor(d,member(d,input,"snapshot")));const auto before=snapshot.bytes;const auto cells=snapshot.cells;
  const auto payload=canonical(snapshot.view(),0);const auto expected=member(d,row,"expected");
  Owned envelope(V::o({{"format",V::s("LocalPlayerSummary")},{"payload_json",V::s(payload)},
    {"payload_sha256",V::s(hash(payload))},{"version",V::i(1)}}));
  const auto actual=canonical(envelope.view(),0);
  if(id=="EXPORT_empty_history")require(actual==frozen_bytes(d,member(d,expected,"envelope")),"empty-summary generic Writer exact frozen envelope");
  else {
    require(payload==frozen_bytes(d,member(d,expected,"payload")),"two-summary generic Writer exact frozen payload");
    const auto file=member(d,expected,"file");
    require(actual.size()==static_cast<std::size_t>(number(d,member(d,file,"bytes")))&&hash(actual)==field(d,file,"sha256"),
      "two-summary generic Writer independent exact envelope length/hash");
  }
  require(unchanged(snapshot,before,cells),"generic summary Writer leaves all snapshot data unchanged");
}
void full_unicode(lp::DocumentView d,std::uint32_t row) {
  const auto input=member(d,row,"input"),expected=member(d,row,"expected");
  Owned a(full_descriptor(d,member(d,input,"composed"))),b(full_descriptor(d,member(d,input,"decomposed")));
  const auto ab=a.bytes,bb=b.bytes;const auto ac=a.cells,bc=b.cells;
  require(lp::validate_player(a.view(),0)==lp::Error::none&&lp::validate_player(b.view(),0)==lp::Error::none&&
    boolean(d,member(d,expected,"both_names_valid")),"both complete Unicode Player records valid");
  require(lp::equal_values(a.view(),0,b.view(),0)==boolean(d,member(d,expected,"records_equal")),"full Unicode equality without normalization");
  require(canonical(a.view(),0)==frozen_bytes(d,member(d,expected,"composed"))&&
    canonical(b.view(),0)==frozen_bytes(d,member(d,expected,"decomposed")),"both exact Unicode canonical byte witnesses");
  require(unchanged(a,ab,ac)&&unchanged(b,bb,bc),"Unicode validation/equality/Writer leaves complete inputs unchanged");
}
void full_references(const std::filesystem::path& scalar_path) {
  const auto path=scalar_path.parent_path().parent_path()/"full_record_reference"/"expected-v1.json";
  const auto raw=read_frozen(path,3427125,"164aad9b74de33b04a6a69734116eab899dceaf696135137b9963f679968b722");
  // Fixture transport only:53561 JSON values,42321 keys,26 container levels.
  // These larger test-fixture read limits never enter production record APIs.
  Parsed reference(raw,true,lp::Limits{4*1024*1024,60000,32,65536,65536});const auto d=reference.doc;
  require(field(d,d.root,"schema")=="IndependentLocalPlayersFullRecordReferences/v1"&&
    number(d,member(d,d.root,"case_count"))==110,"exact accepted full-record fixture schema/roster");
  const auto rows=children(d,member(d,d.root,"rows"));require(rows.size()==110,"all110 fixed full-record rows accounted");
  std::size_t complete{},partial{},remaining{};std::set<std::string> ids;
  for(const auto row:rows) {
    const auto id=field(d,row,"id"),group=field(d,row,"group");require(ids.insert(id).second,"unique full-record fixture ID");
    std::cout<<"FULL_RECORD_BEGIN "<<id<<std::endl;
    if(id=="PN_StringName_kind"||id=="CAP_export_cap_plus_one"||group=="cross_column"||group=="schema"||group=="cursor"||group=="complete_bounded_expansion") {
      std::cout<<"FULL_RECORD_DEFERRED "<<id<<" actual_SQLite_service_ClassDB_or_export_gate\n";++remaining;continue;
    }
    if(group=="canonical_export"||(group=="equality_revision"&&id!="E_unicode_not_normalized")) {
      full_projection(d,row,group);std::cout<<"FULL_RECORD_PARTIAL "<<id<<" generic_Writer_or_equality_only_not_store_outcome\n";++partial;continue;
    }
    if(group=="complete_preferences"||group=="complete_preferences_negative")full_preferences(d,row);
    else if(group=="complete_player"||group=="complete_practice"||group=="complete_practice_negative"||group=="complete_source")full_plain_record(d,row,group);
    else if(group=="complete_encoded_preferences")full_wire(d,row);
    else if(group=="scanner_gate_only"||group=="scanner_negative")full_scanner(d,row,group);
    else {require(id=="E_unicode_not_normalized","no unassigned full-record fixture group");full_unicode(d,row);}
    std::cout<<"FULL_RECORD_CODEC "<<id<<'\n';++complete;
  }
  require(complete==76&&partial==5&&remaining==29,"honest full-record complete/projected/deferred roster");
  require(hash(reference.bytes)=="164aad9b74de33b04a6a69734116eab899dceaf696135137b9963f679968b722",
    "full-record fixture never mutated");
  std::cout<<"LOCAL_PLAYERS_FULL_RECORD_CODEC complete=76 projected=5 deferred=29 total=110 scope=pure_codec_records_not_SQLite_ClassDB_or_store_export\n";
}

} // namespace

int main(int argc,char** argv) {
  try {
    require(argc==3 && std::string_view(argv[1])=="--reference","exact CLI --reference <frozen expected-v1.json>");
    const std::filesystem::path path(argv[2]);
    require(path.filename()=="expected-v1.json" && std::filesystem::is_regular_file(std::filesystem::symlink_status(path)),"ordinary named reference file");
    std::ifstream stream(path,std::ios::binary);require(static_cast<bool>(stream),"reference opens");
    std::string bytes(54201,'\0');stream.read(bytes.data(),static_cast<std::streamsize>(bytes.size()));bytes.resize(static_cast<std::size_t>(stream.gcount()));
    require(!stream.bad() && bytes.size()==54200,"bounded complete reference read");
    const int rounding=std::fegetround(),flags=std::fetestexcept(FE_ALL_EXCEPT);
#if defined(_M_X64) || defined(__x86_64__)
    const auto csr=_mm_getcsr();
#endif
    supplemental();references(bytes);apron_source_domain();full_references(path);
    require(std::fegetround()==rounding && std::fetestexcept(FE_ALL_EXCEPT)==flags,"pure codec preserves caller FP rounding/sticky status");
#if defined(_M_X64) || defined(__x86_64__)
    require(_mm_getcsr()==csr,"pure codec preserves complete caller MXCSR");
#endif
    std::cout<<"LOCAL_PLAYERS_CODEC_PASS checks="<<checks<<" applicable_reference_rows="<<applicable<<" deferred_reference_rows="<<deferred
      <<" original_reference_rows=114 scope=pure_codec_records_no_storage_runtime\n";return 0;
  } catch(const std::exception& error) {
    std::cerr<<"LOCAL_PLAYERS_CODEC_FAIL checks="<<checks<<" error="<<error.what()<<'\n';return 1;
  }
}
