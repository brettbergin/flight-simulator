#include "../fixtures/test_support.hpp"
#include "fixtures/literal_payloads.hpp"
#include <flight/ground/grid_payload.hpp>
#include <algorithm>
#include <span>

namespace t = grid_test;
namespace grid = flight::ground::grid::v1;
namespace payload = flight::ground::grid::payload::v1;
using Bytes = std::vector<std::uint8_t>;

Bytes golden() { return {grid_codec_literals::golden_a.begin(),grid_codec_literals::golden_a.end()}; }
grid::Definition decode(const Bytes& bytes) {
  return payload::decode(std::span<const std::uint8_t>(bytes.data(),bytes.size()));
}
void put(Bytes& bytes,std::size_t offset,std::uint64_t value,std::size_t width) {
  if(width>8 || offset>bytes.size() || width>bytes.size()-offset) throw std::logic_error("test patch out of bounds");
  for(std::size_t i=0;i<width;++i)bytes[offset+i]=static_cast<std::uint8_t>((value>>(8U*i))&0xffU);
}
void append(Bytes& bytes,std::uint64_t value,std::size_t width) {
  if(width>8)throw std::logic_error("test append width");
  for(std::size_t i=0;i<width;++i)bytes.push_back(static_cast<std::uint8_t>((value>>(8U*i))&0xffU));
}
void rejected(const Bytes& bytes,std::string_view label) {
  t::rejects_invalid([&]{(void)decode(bytes);},label);
}
void reject_words(std::size_t offset,std::size_t width,std::initializer_list<std::uint64_t> words,
                  std::string_view label) {
  for(const auto word:words){auto bytes=golden();put(bytes,offset,word,width);rejected(bytes,label);}
}

void golden_fields(const grid::Definition& definition) {
  t::check(definition.columns==3 && definition.rows==2 && definition.spacing==grid::Spacing::metres_2,
           "golden dimensions and spacing");
  t::check(definition.missing_vertices==grid::MissingVertices::invalid_data && definition.default_material_index==0,
           "golden missing/default enums");
  t::check(t::bits(definition.anchor.latitude_rad)==0 && t::bits(definition.anchor.longitude_rad)==0
           && t::bits(definition.anchor.ellipsoid_height_m)==0x4059000000000000ULL,"golden anchor raw f64 words");
  t::check(t::bits(definition.east_origin_m)==0xc000000000000000ULL
           && t::bits(definition.south_origin_m)==0xc000000000000000ULL,"golden origins raw f64 words");
  const std::array<std::uint32_t,6> expected{{0,0x3f800000,0x7fc00000,0,0x3f800000,0x7fc00000}};
  t::check(definition.up_m.size()==expected.size(),"golden exact height count");
  if(definition.up_m.size()==expected.size())for(std::size_t i=0;i<expected.size();++i)
    t::check(t::bits(definition.up_m[i])==expected[i],"golden raw f32 height/sentinel word");
  t::check(definition.valid_words==std::vector<std::uint64_t>{0x1b},"golden validity bits0,1,3,4 only");
  t::check(definition.materials.size()==1,"golden one material");
  if(definition.materials.size()==1){
    const auto& material=definition.materials[0];
    t::check(material.id=="grass" && t::bits(material.static_friction)==0x3fe0000000000000ULL
             && t::bits(material.dynamic_friction)==0x3fd0000000000000ULL,"golden material name and raw factors");
  }
  t::check(definition.polygons.size()==1,"golden one polygon");
  if(definition.polygons.size()==1){
    const auto& polygon=definition.polygons[0];
    t::check(polygon.id=="pad" && polygon.material_index==0 && polygon.priority==7,"golden polygon metadata");
    const std::array<grid::PointMm,3> points{{{-1000,-1000},{-1000,1000},{1000,-1000}}};
    t::check(polygon.vertices.size()==points.size(),"golden polygon vertex count");
    if(polygon.vertices.size()==points.size())for(std::size_t i=0;i<points.size();++i)
      t::check(polygon.vertices[i].east_mm==points[i].east_mm && polygon.vertices[i].south_mm==points[i].south_mm,
               "golden signed coordinates and ring order");
  }
}

void accepted_literals() {
  auto bytes=golden();
  auto definition=decode(bytes);golden_fields(definition);
  std::fill(bytes.begin(),bytes.end(),std::uint8_t{0});bytes.clear();bytes.shrink_to_fit();
  golden_fields(definition); // No borrowed input span or string may remain.
  const Bytes zeros(grid_codec_literals::signed_zero_b.begin(),grid_codec_literals::signed_zero_b.end());
  const auto zero=decode(zeros);
  t::check(zero.columns==2 && zero.rows==2 && zero.polygons.empty() && zero.materials.size()==1,"signed-zero shape withP0");
  for(const double value:{zero.anchor.latitude_rad,zero.anchor.longitude_rad,zero.anchor.ellipsoid_height_m,zero.east_origin_m})
    t::check(t::bits(value)==0x8000000000000000ULL,"admitted negative f64 zero preserved");
  t::check(t::bits(zero.south_origin_m)==0xc000000000000000ULL,"signed-zero south origin-2");
  const std::array<std::uint32_t,4> expected{{0x80000000,0,0x80000000,0}};
  t::check(zero.up_m.size()==expected.size(),"signed-zero height count");
  if(zero.up_m.size()==expected.size())for(std::size_t i=0;i<expected.size();++i)
    t::check(t::bits(zero.up_m[i])==expected[i],"signed f32 zeros preserved");
  t::check(zero.valid_words==std::vector<std::uint64_t>{15},"signed-zero all four valid");
  if(zero.materials.size()==1)t::check(zero.materials[0].id=="z"
      && t::bits(zero.materials[0].static_friction)==0x8000000000000000ULL
      && t::bits(zero.materials[0].dynamic_friction)==0,"signed-zero material bits preserved");
  Bytes unaligned{0xa5};
  unaligned.insert(unaligned.end(),grid_codec_literals::golden_a.begin(),grid_codec_literals::golden_a.end());
  golden_fields(payload::decode(std::span<const std::uint8_t>(unaligned.data()+1,grid_codec_literals::golden_a.size())));
  for(const std::uint64_t priority:{0ULL,255ULL}){
    auto control=golden();put(control,166,priority,1);
    const auto result=decode(control);
    t::check(result.polygons.size()==1 && result.polygons[0].priority==priority,"entire uint8 priority domain endpoints admitted");
  }
  for(const std::uint64_t reason:{0ULL,1ULL,2ULL}){
    auto control=golden();put(control,57,reason,1);
    t::check(static_cast<unsigned>(decode(control).missing_vertices)==reason,"all missing enums retain exact ordinal");
  }
  {auto control=golden();put(control,56,4,1);t::check(decode(control).spacing==grid::Spacing::metres_4,"4m spacing admitted");}
  {
    auto control=golden();put(control,108,0x0000803f,4);
    const auto result=decode(control);
    t::check(result.up_m.size()==6 && t::bits(result.up_m[1])==0x0000803f,"endian-looking valid subnormal accepted literally, never repaired");
  }
  {
    auto control=golden();put(control,108,0x40800001,4);put(control,120,0x40800001,4);
    const auto formerly_rejected=decode(control);
    t::check(formerly_rejected.up_m.size()==6 && t::bits(formerly_rejected.up_m[1])==0x40800001 && t::bits(formerly_rejected.up_m[4])==0x40800001,
             "former cap2 uniform east plane now admitted under16");
  }
}

void framing_and_fields() {
  for(std::size_t length=0;length<grid_codec_literals::golden_a.size();++length)
    t::rejects_invalid([&]{(void)payload::decode(std::span<const std::uint8_t>(grid_codec_literals::golden_a.data(),length));},"every golden strict prefix rejects");
  for(std::size_t length=0;length<grid_codec_literals::signed_zero_b.size();++length)
    t::rejects_invalid([&]{(void)payload::decode(std::span<const std::uint8_t>(grid_codec_literals::signed_zero_b.data(),length));},"every signed-zero strict prefix rejects");
  {auto bytes=golden();bytes.push_back(0);rejected(bytes,"append with unchanged total");put(bytes,16,196,8);rejected(bytes,"append with updated total");}
  reject_words(0,1,{71},"wrong magic");
  reject_words(8,4,{0,2,0xffffffffULL},"wrong version");
  reject_words(12,4,{0x04030201},"swapped marker is never repaired");
  reject_words(16,8,{0,104,194,196,std::numeric_limits<std::uint64_t>::max()},"wrong exact total");
  reject_words(24,4,{0,1,8194,0xffffffffULL,0x03000000},"column bounds/endian data");
  reject_words(28,4,{0,1,8194,0xffffffffULL},"row bounds");
  reject_words(32,4,{0,5,7,0xffffffffULL},"derived N");
  reject_words(36,4,{0,2,0xffffffffULL},"derived W");
  reject_words(40,4,{0,33,0xffffffffULL},"material count");
  reject_words(44,4,{129,0xffffffffULL},"polygon count");
  reject_words(48,4,{2,4,4097,0xffffffffULL},"total polygon vertices");
  reject_words(52,4,{1,0xffffffffULL},"default index");
  reject_words(56,1,{0,3,255},"spacing enum");
  reject_words(57,1,{3,255},"missing enum");
  reject_words(58,2,{1,65535},"reserved16");
  reject_words(60,4,{1,0xffffffffULL},"reserved32");
  reject_words(64,8,{0x7ff8000000000000ULL,0x7ff0000000000000ULL,0xfff0000000000000ULL},"anchor nonfinite");
  reject_words(64,8,{t::bits(2.)},"anchor latitude range");
  reject_words(72,8,{t::bits(4.)},"anchor longitude range");
  reject_words(80,8,{t::bits(-501.),t::bits(10001.)},"anchor altitude range");
  reject_words(88,8,{0x3fb999999999999aULL},"origin quantum");
  reject_words(88,8,{t::bits(8192.)},"origin endpoint exceeds8192");
  reject_words(104,4,{0x7fc00000,0x7f800000,0xff800000},"valid heights cannot be nonfinite");
  reject_words(108,4,{0x45800001},"height above4096");
  reject_words(108,4,{0x42000001},"east gradient component16+2^-19 rejects");
  reject_words(112,4,{0x7fc00001,0xffc00000,0x7fa00000,0,0x7f800000},"invalid vertices require exact sentinel");
  reject_words(128,8,{31,91},"valid NaN or nonzero mask padding");
  {auto bytes=golden();for(std::size_t offset=104;offset<128;offset+=4)put(bytes,offset,0x7fc00000,4);put(bytes,128,0,8);rejected(bytes,"all-invalid no usable cell");}
  {auto bytes=golden();put(bytes,104,t::bits(-1000.f),4);put(bytes,120,t::bits(1048.f),4);rejected(bytes,"span beyond2048 (also steep)");}
  reject_words(136,1,{0,129,255},"material ID length");
  reject_words(137,1,{0,71,128},"material ID ASCII grammar");
  reject_words(141,1,{45},"material ID terminal separator");
  reject_words(142,8,{0x7ff8000000000000ULL,0x7ff0000000000000ULL},"friction nonfinite");
  reject_words(150,8,{t::bits(-.25),t::bits(.75),t::bits(6.)},"friction range/order");
  reject_words(158,1,{0,129,255},"polygon ID length");
  reject_words(159,1,{0,80,128},"polygon ID ASCII grammar");
  reject_words(162,4,{1,0xffffffffULL},"polygon material index");
  reject_words(167,4,{0,2,4097,0xffffffffULL},"polygon vertex count");
  reject_words(171,4,{static_cast<std::uint32_t>(-8192001),8192001},"integer point coordinate range");
  {auto bytes=golden();put(bytes,179,static_cast<std::uint32_t>(-1000),4);put(bytes,183,static_cast<std::uint32_t>(-1000),4);rejected(bytes,"duplicate point");}
  {auto bytes=golden();put(bytes,179,1000,4);put(bytes,183,static_cast<std::uint32_t>(-1000),4);put(bytes,187,static_cast<std::uint32_t>(-1000),4);put(bytes,191,1000,4);rejected(bytes,"reverse ring winding");}
  {
    auto bytes=golden();put(bytes,24,8193,4);put(bytes,28,8193,4);put(bytes,32,67125249,4);put(bytes,36,1048833,4);
    put(bytes,88,t::bits(-8192.),8);put(bytes,96,t::bits(-8192.),8);
    rejected(bytes,"maximum legal dimension declaration with short body rejects without huge allocation");
  }
}

// Fixed independent payload assembly approved by Root: NOT a Definition encoder.
// Source: exact-admission/reference/expected-v1.json SHA3df724576eeada629a65a18c23c72abeb08937f7e8d5bae6c3d66d29bda32f3a.
// Header104 + heights1026*4 + mask17*8 + literal z-material18 =4362.
// Height offset104, validity offset4208, material offset4344, final4362.
Bytes exact_span_literal(bool negative_subnormal) {
  Bytes bytes(grid_codec_literals::signed_zero_b.begin(),grid_codec_literals::signed_zero_b.begin()+104);
  put(bytes,8,1,4);put(bytes,12,0x01020304,4);put(bytes,16,4362,8);
  put(bytes,24,513,4);put(bytes,28,2,4);put(bytes,32,1026,4);put(bytes,36,17,4);
  put(bytes,40,1,4);put(bytes,44,0,4);put(bytes,48,0,4);put(bytes,52,0,4);
  put(bytes,56,4,1);put(bytes,57,2,1);put(bytes,58,0,2);put(bytes,60,0,4);
  put(bytes,64,0,8);put(bytes,72,0,8);put(bytes,80,t::bits(100.),8);
  put(bytes,88,t::bits(-1024.),8);put(bytes,96,0,8);
  for(std::size_t row=0;row<2;++row) {
    for(std::size_t i=0;i<512;++i)append(bytes,i==0 && negative_subnormal?0x80000001:t::bits(static_cast<float>(4*i)),4);
    append(bytes,0x44ffff00,4);
  }
  if(bytes.size()!=4208)throw std::logic_error("fixed exact-span height offset");
  for(int i=0;i<16;++i)append(bytes,std::numeric_limits<std::uint64_t>::max(),8);
  append(bytes,3,8);
  if(bytes.size()!=4344)throw std::logic_error("fixed exact-span validity offset");
  bytes.insert(bytes.end(),grid_codec_literals::signed_zero_b.begin()+128,grid_codec_literals::signed_zero_b.end());
  constexpr std::array<std::uint8_t,32> count_bytes{{
    1,2,0,0, 2,0,0,0, 2,4,0,0, 17,0,0,0,
    1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
  }};
  constexpr std::array<std::uint8_t,8> total_bytes{{0x0a,0x11,0,0,0,0,0,0}};
  if(bytes.size()!=4362 || !std::equal(count_bytes.begin(),count_bytes.end(),bytes.begin()+24)
      || !std::equal(total_bytes.begin(),total_bytes.end(),bytes.begin()+16)
      || bytes[56]!=4 || bytes[57]!=2)
    throw std::logic_error("fixed exact-span byte count/header changed");
  return bytes;
}

void exact_admission_through_decode() {
  auto control=golden();
  put(control,104,0,4);put(control,108,0x42000000,4);put(control,116,0,4);put(control,120,0x42000000,4);
  const auto admitted=decode(control);
  t::check(admitted.up_m.size()==6 && t::bits(admitted.up_m[0])==0 && t::bits(admitted.up_m[1])==0x42000000
           && t::bits(admitted.up_m[3])==0 && t::bits(admitted.up_m[4])==0x42000000,
           "codec exact norm16 control retains all four frozen usable corners");
  put(control,104,0x80000001,4);
  rejected(control,"codec negative-minsub exact gradient excess rejects");
  const auto span=decode(exact_span_literal(false));
  t::check(span.columns==513 && span.rows==2 && span.up_m.size()==1026 && span.valid_words.size()==17,
           "codec exact span boundary retains dimensions/counts");
  std::vector<std::uint64_t> expected_mask(16,std::numeric_limits<std::uint64_t>::max());expected_mask.push_back(3);
  t::check(span.valid_words==expected_mask,"codec exact span every validity word and padding");
  if(span.up_m.size()==1026)for(std::size_t row=0;row<2;++row)for(std::size_t i=0;i<513;++i) {
    const auto expected=i==512?0x44ffff00U:t::bits(static_cast<float>(4*i));
    t::check(t::bits(span.up_m[row*513+i])==expected,"codec exact span raw height vector matches frozen rule");
  }
  t::check(span.anchor.ellipsoid_height_m==100 && span.east_origin_m==-1024 && span.south_origin_m==0
           && span.spacing==grid::Spacing::metres_4,"codec exact span explicit anchor/origin/spacing");
  rejected(exact_span_literal(true),"codec exact span2048+2^-149 rejects while gradients remain below16");
}

int main() {
  t::section("accepted literal fields and ownership",accepted_literals);
  t::section("framing and malformed fields",framing_and_fields);
  t::section("exact admission through decode",exact_admission_through_decode);
  return t::finish("Resident grid independent codec");
}
