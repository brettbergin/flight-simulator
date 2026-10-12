// Original MIT. Closed records; exact source-independent U64 operations.
#include "flight/local_players/records.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace flight::local_players {
namespace {
constexpr std::string_view kinds[]={"start","start_management","list_players","create_player","load_player","rename_player","save_preferences","begin_practice","observe_practice","end_practice","link_archive","list_practice","load_practice","prune_practice","delete_player","export_player","list_recovery","delete_recovery"};
constexpr std::string_view variants[]={"jsbsim-1.3.1-upstream","jsbsim-1.3.1-event-aware-constant-power-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"};
constexpr std::string_view targets[]={"roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"};
constexpr std::string_view actions[]={"pause_menu","restart","start_ground","start_airborne","idle","left_brake","right_brake","both_brakes","brake_hold","view_cycle","view_cockpit","view_chase","view_orbit","view_panel","map_toggle","runway_toggle","map_zoom_in","map_zoom_out","look_hold","view_zoom_in","view_zoom_out","recenter","help","overlay","controller_select","audio","fullscreen","speed_down","speed_up","controls_panel"};
constexpr std::string_view systems[]={"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"};
Error type(DocumentView d,std::uint32_t n,ValueKind k) noexcept {auto p=d.at(n);return p&&p->kind==k?Error::none:Error::invalid_type;}
Error text(DocumentView d,std::uint32_t n,std::size_t lo,std::size_t hi) noexcept {
 if(auto e=type(d,n,ValueKind::string);e!=Error::none)return e;
 std::size_t bytes{},count{};if(!string_metrics(d,n,bytes,count))return Error::invalid_record;
 if(bytes>4096||count>hi)return Error::payload_limit;
 return count<lo?Error::invalid_record:Error::none;
}
template<std::size_t N> Error text(DocumentView d,std::uint32_t n,std::size_t lo,std::size_t hi,FixedText<N>* result) noexcept {
 auto e=text(d,n,lo,hi);if(e!=Error::none)return e;
 return result->from(d,n)?Error::none:Error::payload_limit;
}
bool player_name_node(DocumentView d,std::uint32_t n) noexcept {
 std::size_t bytes{},scalars{};if(!string_metrics(d,n,bytes,scalars)||bytes>160||scalars<1||scalars>40)return false;
 auto cursor=string_cursor(d,n);std::uint32_t cp{},first{},last{};bool initial=true;
 while(cursor.next(cp)){if(cp<32||cp==127)return false;if(initial){first=cp;initial=false;}last=cp;}
 auto whitespace=[](std::uint32_t c){return c==32||c==0x85||c==0xa0||c==0x1680||(c>=0x2000&&c<=0x200a)||c==0x2028||c==0x2029||c==0x202f||c==0x205f||c==0x3000;};
 return cursor.good&&!initial&&!whitespace(first)&&!whitespace(last);
}
Error exact(DocumentView d,std::uint32_t n,std::string_view value) noexcept {auto e=type(d,n,ValueKind::string);return e!=Error::none?e:d.string_is(n,value)?Error::none:Error::invalid_record;}
Error hexadecimal(DocumentView d,std::uint32_t n,std::size_t count) noexcept {FixedText<64> b;auto e=text(d,n,count,count,&b);return e!=Error::none?e:lower_hex(b.view(),count)?Error::none:Error::invalid_record;}
Error u64(DocumentView d,std::uint32_t n,bool positive=false) noexcept {FixedText<20> b;auto e=text(d,n,1,20,&b);U64 v;return e!=Error::none?e:U64::parse(b.view(),v,positive)?Error::none:Error::invalid_record;}
Error utc(DocumentView d,std::uint32_t n) noexcept {FixedText<20> b;auto e=text(d,n,20,20,&b);return e!=Error::none?e:valid_utc(b.view())?Error::none:Error::invalid_record;}
Error integer(DocumentView d,std::uint32_t n,std::int64_t lo,std::int64_t hi) noexcept {auto e=type(d,n,ValueKind::integer);if(e!=Error::none)return e;auto v=std::bit_cast<std::int64_t>(d.at(n)->scalar);return v>=lo&&v<=hi?Error::none:Error::invalid_record;}
Error collection(DocumentView d,std::uint32_t n,ValueKind kind,std::size_t lo,std::size_t hi) noexcept {auto e=type(d,n,kind);if(e!=Error::none)return e;auto size=d.size(n);return size>hi?Error::payload_limit:size<lo?Error::invalid_record:Error::none;}
// Finite binary64 comparisons do not depend on a caller's DAZ/FTZ mode. Both
// signed zeros compare equal; their original bits remain in the actual cell.
int real_compare(double a,double b) noexcept {
 auto x=std::bit_cast<std::uint64_t>(a),y=std::bit_cast<std::uint64_t>(b);
 if((x&0x7fffffffffffffffULL)==0)x=0;
 if((y&0x7fffffffffffffffULL)==0)y=0;
 auto order=[](std::uint64_t bits){return bits>>63?~bits:bits^0x8000000000000000ULL;};
 x=order(x);y=order(y);return x<y?-1:x>y?1:0;
}
bool integral_real(double a) noexcept {
 auto bits=std::bit_cast<std::uint64_t>(a)&0x7fffffffffffffffULL;
 if(!bits)return true;auto exponent=static_cast<unsigned>(bits>>52);
 if(exponent<1023)return false;if(exponent>=1075)return true;
 return (bits&((std::uint64_t{1}<<(1075-exponent))-1))==0;
}
Error number(DocumentView d,std::uint32_t n,double lo,double hi,bool restore,std::span<JsonCell> mutable_cells,double* output=nullptr,bool float_only=false) noexcept {
 auto p=d.at(n);if(!p)return Error::invalid_type;
 if(restore&&p->kind==ValueKind::object){double value{};if(!decode_binary64_tag(d,n,value))return Error::invalid_record;if(n>=mutable_cells.size()||mutable_cells.data()!=d.cells.data())return Error::out_of_memory;auto& c=mutable_cells[n];c.kind=ValueKind::real;c.scalar=std::bit_cast<std::uint64_t>(value);c.first=no_cell;p=&c;}
 if(p->kind!=ValueKind::real&&(float_only||p->kind!=ValueKind::integer))return Error::invalid_type;
 double x=p->kind==ValueKind::real?std::bit_cast<double>(p->scalar):static_cast<double>(std::bit_cast<std::int64_t>(p->scalar));
 if(!finite_binary64(x)||real_compare(x,lo)<0||real_compare(x,hi)>0)return Error::invalid_record;if(output)*output=x;return Error::none;
}
Error enumeration(DocumentView d,std::uint32_t n,int lo,int hi,bool restore,std::span<JsonCell> mutable_cells) noexcept {
 // Tags are not admitted at enum positions in stored JSON. Actual typed FLOAT
 // caller enums are normalized only before queue ownership is published.
 if(restore)return integer(d,n,lo,hi);
 double x{};auto e=number(d,n,lo,hi,false,{},&x);if(e!=Error::none)return e;if(!integral_real(x))return Error::invalid_record;
 if(d.at(n)->kind==ValueKind::real){if(n>=mutable_cells.size()||mutable_cells.data()!=d.cells.data())return Error::out_of_memory;mutable_cells[n].kind=ValueKind::integer;mutable_cells[n].scalar=std::bit_cast<std::uint64_t>(static_cast<std::int64_t>(x));}return Error::none;
}
bool is_null(DocumentView d,std::uint32_t n) noexcept {auto p=d.at(n);return p&&p->kind==ValueKind::null;}
bool model(DocumentView d,std::uint32_t n,bool piston) noexcept {return closed(d,n,{"id","version","backend_model"})==Error::none&&d.string_is(d.member(n,"id"),piston?"original-piston-prop-v1":"original-interactive-prototype")&&d.string_is(d.member(n,"version"),"0.1.0-prototype")&&d.string_is(d.member(n,"backend_model"),piston?"original-piston-prop":"original-interactive");}
bool physical_key_domain(std::uint32_t code) noexcept {
 // Derived from official Godot4.7.2 keyboard.cpp356..424 / keyboard.h35..255.
 // Independent source review c64ec912 and twenty preconsumer cases bind this
 // predicate. Actual adapter OS roundtrip is still required, not replaced.
 constexpr std::uint32_t base_mask=0x007fffff,modifiers=0x1e000000;
 if(code<32||code==0x007fffff||(code&~(base_mask|modifiers)))return false;
 auto base=code&base_mask;
 if((base>=32&&base<=96)||(base>=123&&base<=126)||base==165||base==167||base==0x007fffff)return true;
 if((base&0x00400000)==0)return false;auto low=base&~0x00400000;
 return (low>=1&&low<=62)||low==66||low==67||low==69||(low>=72&&low<=78)||(low>=84&&low<=115)||(low>=129&&low<=143);
}
Error keys(DocumentView d,std::uint32_t n,bool restore,std::span<JsonCell> cells) noexcept {if(auto e=collection(d,n,ValueKind::array,1,4);e!=Error::none)return e;for(auto j=d.at(n)->first;j!=no_cell;j=d.at(j)->next){auto e=enumeration(d,j,32,2147483647,restore,cells);if(e!=Error::none)return e;auto code=std::bit_cast<std::int64_t>(d.at(j)->scalar);if(!physical_key_domain(static_cast<std::uint32_t>(code)))return Error::invalid_record;for(auto k=d.at(n)->first;k!=j;k=d.at(k)->next)if(d.at(k)->scalar==d.at(j)->scalar)return Error::invalid_record;}return Error::none;}
bool declared_slot(DocumentView d,std::uint32_t devices,std::uint32_t slot) noexcept {for(auto n=d.at(devices)->first;n!=no_cell;n=d.at(n)->next)if(equal_values(d,d.member(n,"slot"),d,slot))return true;return false;}
Error binding_source(DocumentView d,std::uint32_t n,std::uint32_t devices,bool engine,bool restore,std::span<JsonCell> cells) noexcept {
 auto k=d.member(n,"kind");if(auto e=type(d,k,ValueKind::string);e!=Error::none)return e;
 if(d.string_is(k,"physical_keys")){auto e=closed(d,n,{"kind","keys"});return e!=Error::none?e:keys(d,d.member(n,"keys"),restore,cells);}
 if(d.string_is(k,"joy_button")){auto e=closed(d,n,{"kind","slot","index"});if(e!=Error::none)return e;if((e=text(d,d.member(n,"slot"),1,32))!=Error::none)return e;if(!declared_slot(d,devices,d.member(n,"slot")))return Error::invalid_record;return enumeration(d,d.member(n,"index"),0,127,restore,cells);}
 if(d.string_is(k,"mouse_button")){auto e=closed(d,n,{"kind","button"});if(e!=Error::none)return e;e=enumeration(d,d.member(n,"button"),1,9,restore,cells);if(e!=Error::none)return e;auto b=std::bit_cast<std::int64_t>(d.at(d.member(n,"button"))->scalar);return engine&&b>=4&&b<=7?Error::invalid_record:Error::none;}return Error::invalid_record;
}
bool same_source(DocumentView d,std::uint32_t a,std::uint32_t b) noexcept {
 if(!equal_values(d,d.member(a,"kind"),d,d.member(b,"kind")))return false;
 if(!d.string_is(d.member(a,"kind"),"physical_keys"))return equal_values(d,a,d,b);
 auto x=d.member(a,"keys"),y=d.member(b,"keys");if(d.size(x)!=d.size(y))return false;for(auto i=d.at(x)->first;i!=no_cell;i=d.at(i)->next){bool found=false;for(auto j=d.at(y)->first;j!=no_cell;j=d.at(j)->next)found|=d.at(i)->scalar==d.at(j)->scalar;if(!found)return false;}return true;
}
struct Control {std::uint8_t kind{};std::uint32_t slot{no_cell};std::uint64_t code{};};
bool same_control(DocumentView d,const Control&a,const Control&b) noexcept {return a.kind==b.kind&&a.code==b.code&&(a.slot==no_cell?b.slot==no_cell:b.slot!=no_cell&&equal_values(d,a.slot,d,b.slot));}
template<class F> bool controls(DocumentView d,std::uint32_t root,F&& emit) noexcept {
 auto key_list=[&](std::uint32_t list,std::uint32_t owner){for(auto i=d.at(list)->first;i!=no_cell;i=d.at(i)->next)if(!emit(Control{0,no_cell,d.at(i)->scalar},owner))return false;return true;};
 for(auto n=d.at(d.member(root,"axes"))->first;n!=no_cell;n=d.at(n)->next){
  if(d.string_is(d.member(n,"kind"),"key_pair")){if(!key_list(d.member(n,"negative"),n)||!key_list(d.member(n,"positive"),n))return false;}
  else if(d.string_is(d.member(n,"kind"),"joy_axis")&&!emit(Control{1,d.member(n,"slot"),d.at(d.member(n,"index"))->scalar},n))return false;
 }
 for(auto group:{"actions","systems"}){auto list=d.member(root,group);if(list==no_cell)continue;for(auto n=d.at(list)->first;n!=no_cell;n=d.at(n)->next)for(auto s=d.at(d.member(n,"sources"))->first;s!=no_cell;s=d.at(s)->next){
  if(d.string_is(d.member(s,"kind"),"physical_keys")){if(!key_list(d.member(s,"keys"),n))return false;}
  else if(d.string_is(d.member(s,"kind"),"joy_button")){if(!emit(Control{2,d.member(s,"slot"),d.at(d.member(s,"index"))->scalar},n))return false;}
  else if(!emit(Control{3,no_cell,d.at(d.member(s,"button"))->scalar},n))return false;
 }}return true;
}
Error conflicts(DocumentView d,std::uint32_t root) noexcept {
 // Valid closed grammar has at most608 controls (8*8 +30*4*4 +4*4*4).
 // No owned control-payload array escapes the charged codec regions. Bounded
 // re-traversal keeps only two scalar control descriptors; broad objects have
 // already failed closed cardinality/type admission before this routine.
 std::size_t current=0;
 bool good=controls(d,root,[&](Control c,std::uint32_t owner){
  if(current>=608||(c.kind==0&&c.code==4194305))return false;
  std::size_t prior=0;bool collision=false;
  controls(d,root,[&](Control p,std::uint32_t previous_owner){if(prior++>=current)return false;if(owner!=previous_owner&&same_control(d,c,p)){collision=true;return false;}return true;});
  ++current;return !collision;
 });return good?Error::none:Error::invalid_record;
}
// Same local-path grammar as the contiguous public helper, without copying a
// decoded4096-byte payload onto the native stack during codec admission.
bool valid_path_node(DocumentView d,std::uint32_t n) noexcept {
 std::size_t bytes{},scalars{};if(!string_metrics(d,n,bytes,scalars)||bytes<4||bytes>4096)return false;
 auto c=string_cursor(d,n);std::uint32_t cp{};
 if(!c.next(cp)||!((cp>='A'&&cp<='Z')||(cp>='a'&&cp<='z'))||!c.next(cp)||cp!=':'||!c.next(cp)||(cp!='/'&&cp!='\\'))return false;
 std::size_t length=0;std::uint32_t last=0;bool dots=true;
 auto finish=[&]{return length&&last!='.'&&last!=' '&&!(dots&&length<=2);};
 while(c.next(cp)){
  if(cp=='/'||cp=='\\'){if(!finish())return false;length=0;dots=true;}
  else{if(cp<32||cp==127||cp==':'||cp=='*'||cp=='?'||cp=='"'||cp=='<'||cp=='>'||cp=='|')return false;++length;last=cp;dots&=cp=='.';}
 }
 return c.good&&finish();
}
Error session_node(DocumentView d,std::uint32_t n) noexcept {
 auto e=text(d,n,1,128);if(e!=Error::none)return e;
 // Canonical Wire ID: ^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$.
 // Stream scalar-valid UTF8; no Unicode alias, uppercase or separator pair.
 auto cursor=string_cursor(d,n);std::uint32_t cp{};bool first=true,separator=false;
 while(cursor.next(cp)){
  bool letter=cp>='a'&&cp<='z',digit=cp>='0'&&cp<='9';
  if(first){if(!letter)return Error::invalid_record;first=false;}
  else if(letter||digit)separator=false;
  else if((cp=='.'||cp=='_'||cp=='-')&&!separator)separator=true;
  else return Error::invalid_record;
 }
 return cursor.good&&!first&&!separator?Error::none:Error::invalid_record;
}
Error archive(DocumentView d,std::uint32_t n,std::uint32_t source) noexcept {if(is_null(d,n))return Error::none;auto e=closed(d,n,{"type","version","absolute_path","payload_sha256","recording_session_id","first_tick","last_tick","linked_utc"});if(e!=Error::none)return e;
 for(auto key:{"absolute_path","first_tick","last_tick","linked_utc","payload_sha256","recording_session_id","type"})if((e=type(d,d.member(n,key),ValueKind::string))!=Error::none)return e;
 if(!valid_path_node(d,d.member(n,"absolute_path")))return Error::invalid_record;
 if((e=exact(d,d.member(n,"type"),"ExternalRecordedReview"))!=Error::none||(e=integer(d,d.member(n,"version"),1,1))!=Error::none||(e=hexadecimal(d,d.member(n,"payload_sha256"),64))!=Error::none||(e=session_node(d,d.member(n,"recording_session_id")))!=Error::none||(e=u64(d,d.member(n,"first_tick")))!=Error::none||(e=u64(d,d.member(n,"last_tick")))!=Error::none||(e=utc(d,d.member(n,"linked_utc")))!=Error::none)return e;
 FixedText<20>a,b;U64 x,y;a.from(d,d.member(n,"first_tick"));b.from(d,d.member(n,"last_tick"));U64::parse(a.view(),x);U64::parse(b.view(),y);if(U64::compare(x,y)>0)return Error::invalid_record;if(source!=no_cell&&!equal_values(d,d.member(n,"recording_session_id"),d,d.member(source,"session_id")))return Error::invalid_record;return Error::none;
}
} // namespace
bool U64::parse(std::string_view s,U64& out,bool positive) noexcept {if(s.empty()||s.size()>20||(s.size()>1&&s.front()=='0')||(positive&&s=="0"))return false;for(char c:s)if(c<'0'||c>'9')return false;if(s.size()==20&&s>"18446744073709551615")return false;U64 v;v.size=static_cast<std::uint8_t>(s.size());std::memcpy(v.digits.data(),s.data(),s.size());out=v;return true;}
int U64::compare(const U64&a,const U64&b) noexcept {if(a.size!=b.size)return a.size<b.size?-1:1;auto x=a.view().compare(b.view());return x<0?-1:x>0?1:0;}
bool U64::increment(const U64&a,U64&out) noexcept {if(a.view()=="18446744073709551615"||!a.size)return false;auto v=a;int i=v.size-1;while(i>=0&&v.digits[i]=='9')v.digits[i--]='0';if(i>=0)++v.digits[i];else{for(int j=v.size;j>0;--j)v.digits[j]=v.digits[j-1];v.digits[0]='1';++v.size;}out=v;return true;}
bool U64::subtract(const U64&a,const U64&b,U64&out) noexcept {if(compare(a,b)<0||!a.size||!b.size)return false;char digits[20]{};int borrow=0;for(int i=0;i<a.size;++i){int x=a.digits[a.size-1-i]-'0'-borrow-(i<b.size?b.digits[b.size-1-i]-'0':0);borrow=x<0;if(borrow)x+=10;digits[a.size-1-i]=static_cast<char>('0'+x);}std::size_t start=0;while(start+1<a.size&&digits[start]=='0')++start;return parse({digits+start,a.size-start},out);}
bool valid_utc(std::string_view s) noexcept {if(s.size()!=20||s[4]!='-'||s[7]!='-'||s[10]!='T'||s[13]!=':'||s[16]!=':'||s[19]!='Z')return false;for(unsigned i:{0,1,2,3,5,6,8,9,11,12,14,15,17,18})if(s[i]<'0'||s[i]>'9')return false;auto pair=[&](int i){return (s[i]-'0')*10+s[i+1]-'0';};int y=pair(0)*100+pair(2),m=pair(5),day=pair(8);if(y<2000||m<1||m>12||pair(11)>23||pair(14)>59||pair(17)>59)return false;int days[]={31,28,31,30,31,30,31,31,30,31,30,31};if(y%4==0&&(y%100!=0||y%400==0))days[1]=29;return day>=1&&day<=days[m-1];}
bool valid_player_name(std::string_view s) noexcept {std::size_t count{};if(s.size()>160||!valid_utf8(s,&count)||count<1||count>40)return false;auto ws=[](std::uint32_t c){return c==32||c==0x85||c==0xa0||c==0x1680||(c>=0x2000&&c<=0x200a)||c==0x2028||c==0x2029||c==0x202f||c==0x205f||c==0x3000;};std::uint32_t first=0,last=0;bool initial=true;for(std::size_t i=0;i<s.size();){auto c=static_cast<unsigned char>(s[i++]);std::uint32_t cp=c;unsigned n=c<128?0:c<224?1:c<240?2:3;if(n)cp=c&(n==1?31:n==2?15:7);while(n--)cp=(cp<<6)|(static_cast<unsigned char>(s[i++])&63);if(cp<32||cp==127)return false;if(initial){first=cp;initial=false;}last=cp;}return !ws(first)&&!ws(last);}
bool valid_local_absolute_path(std::string_view s) noexcept {if(s.size()<4||s.size()>4096||!valid_utf8(s)||!((s[0]>='A'&&s[0]<='Z')||(s[0]>='a'&&s[0]<='z'))||s[1]!=':'||(s[2]!='/'&&s[2]!='\\'))return false;std::size_t begin=3;for(std::size_t i=3;i<=s.size();++i){if(i==s.size()||s[i]=='/'||s[i]=='\\'){auto part=s.substr(begin,i-begin);if(part.empty()||part=="."||part==".."||part.back()=='.'||part.back()==' ')return false;begin=i+1;}else if(static_cast<unsigned char>(s[i])<32||s[i]==127||s[i]==':'||s[i]=='*'||s[i]=='?'||s[i]=='"'||s[i]=='<'||s[i]=='>'||s[i]=='|')return false;}return true;}
Error closed(DocumentView d,std::uint32_t n,std::initializer_list<std::string_view> names) noexcept {auto e=type(d,n,ValueKind::object);if(e!=Error::none)return e;if(d.size(n)!=names.size())return Error::invalid_record;for(auto key:names)if(d.member(n,key)==no_cell)return Error::invalid_record;return Error::none;}
Error validate_source(DocumentView d,std::uint32_t n) noexcept {auto e=closed(d,n,{"session_id","model_identity","source_variant","native_source_fingerprint","prepared_world_sha256","named_start","wind_profile","angular_integration_method"});if(e!=Error::none)return e;
 for(auto key:{"session_id","source_variant","native_source_fingerprint","prepared_world_sha256","named_start","wind_profile"})if((e=type(d,d.member(n,key),ValueKind::string))!=Error::none)return e;
 if((e=session_node(d,d.member(n,"session_id")))!=Error::none||(e=hexadecimal(d,d.member(n,"native_source_fingerprint"),64))!=Error::none||(e=hexadecimal(d,d.member(n,"prepared_world_sha256"),64))!=Error::none)return e;
 auto m=d.member(n,"model_identity");if((e=closed(d,m,{"id","version","backend_model"}))!=Error::none)return e;for(auto key:{"id","version","backend_model"})if((e=type(d,d.member(m,key),ValueKind::string))!=Error::none)return e;
 int variant=-1;for(unsigned i=0;i<4;++i)if(d.string_is(d.member(n,"source_variant"),variants[i]))variant=static_cast<int>(i);if(variant<0)return Error::invalid_record;
 bool piston=model(d,m,true);if(!piston&&!model(d,m,false))return Error::invalid_record;
 auto start=d.member(n,"named_start"),wind=d.member(n,"wind_profile"),method=d.member(n,"angular_integration_method");
 // ADR027: both apron starts require calm; only piston cold apron requires local-window-v2.
 // Keep all historical start/wind/variant/method rules below byte-identical.
 if(d.string_is(start,piston?"piston-cold-apron":"apron-ready")){
  if((piston&&variant!=3)||!d.string_is(wind,"calm"))return Error::invalid_record;
  return piston?exact(d,method,"event_aware_coupled_midpoint_v1"):(is_null(d,method)?Error::none:Error::invalid_record);
 }
 if(piston){if(!d.string_is(start,"piston-cold-ground")||!d.string_is(wind,"calm")||variant==0)return Error::invalid_record;return exact(d,method,variant==1?"event_aware_constant_power_v1":"event_aware_coupled_midpoint_v1");}
 if(!d.string_is(start,"ground-ready")&&!d.string_is(start,"airborne-prepared"))return Error::invalid_record;if(!d.string_is(wind,"calm")&&!d.string_is(wind,"from-north")&&!d.string_is(wind,"from-west")&&!d.string_is(wind,"from-east"))return Error::invalid_record;return is_null(d,method)?Error::none:Error::invalid_record;
}
Error validate_player(DocumentView d,std::uint32_t n) noexcept {auto e=closed(d,n,{"type","version","id","name","created_utc","updated_utc","revision"});if(e!=Error::none)return e;
 if((e=utc(d,d.member(n,"created_utc")))!=Error::none||(e=hexadecimal(d,d.member(n,"id"),32))!=Error::none||(e=text(d,d.member(n,"name"),1,40))!=Error::none||(e=u64(d,d.member(n,"revision"),true))!=Error::none||(e=exact(d,d.member(n,"type"),"LocalPlayer"))!=Error::none||(e=utc(d,d.member(n,"updated_utc")))!=Error::none||(e=integer(d,d.member(n,"version"),1,1))!=Error::none)return e;return player_name_node(d,d.member(n,"name"))?Error::none:Error::invalid_record;}
Error validate_audio(DocumentView d,std::uint32_t n,bool restore,std::span<JsonCell> cells) noexcept {auto e=closed(d,n,{"enabled","engine_gain","airflow_gain","show_panel_captions"});if(e!=Error::none)return e;for(auto key:{"airflow_gain","engine_gain"})if((e=number(d,d.member(n,key),0,1,restore,cells,nullptr,true))!=Error::none)return e;for(auto key:{"enabled","show_panel_captions"})if((e=type(d,d.member(n,key),ValueKind::boolean))!=Error::none)return e;return Error::none;}

Error validate_preset(DocumentView d,std::uint32_t n,int version,bool restore,std::span<JsonCell> cells) noexcept {
 if(version!=1&&version!=2)return Error::invalid_record;
 auto e=version==1?closed(d,n,{"type","version","name","devices","axes","actions"}):closed(d,n,{"type","version","name","devices","axes","actions","profile","capability_revision","systems"});if(e!=Error::none)return e;
 if((e=exact(d,d.member(n,"type"),"InputPreset"))!=Error::none||(e=enumeration(d,d.member(n,"version"),version,version,restore,cells))!=Error::none||(e=text(d,d.member(n,"name"),1,64))!=Error::none)return e;
 auto devices=d.member(n,"devices"),axes=d.member(n,"axes"),acts=d.member(n,"actions");if((e=collection(d,devices,ValueKind::array,0,8))!=Error::none||(e=collection(d,axes,ValueKind::array,8,8))!=Error::none||(e=collection(d,acts,ValueKind::array,0,64))!=Error::none)return e;
 for(auto v=d.at(devices)->first;v!=no_cell;v=d.at(v)->next){
  if((e=closed(d,v,{"slot","label","match"}))!=Error::none)return e;FixedText<32>s;
  if((e=text(d,d.member(v,"slot"),1,32,&s))!=Error::none||(e=text(d,d.member(v,"label"),0,64))!=Error::none)return e;
  for(std::size_t i=0;i<s.size;++i){char c=s.data[i];if(!((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(i&&((c>='0'&&c<='9')||c=='-'||c=='.'||c=='_'))))return Error::invalid_record;}
  for(auto k=d.at(devices)->first;k!=v;k=d.at(k)->next)if(equal_values(d,d.member(v,"slot"),d,d.member(k,"slot")))return Error::invalid_record;
  auto match=d.member(v,"match");if((e=closed(d,match,{"guid","name","vendor_id","product_id"}))!=Error::none)return e;
  for(auto key:{"guid","name","vendor_id","product_id"})if((e=text(d,d.member(match,key),0,key==std::string_view("guid")||key==std::string_view("name")?128:16))!=Error::none)return e;
 }
 for(auto a=d.at(axes)->first;a!=no_cell;a=d.at(a)->next){
  int target=-1;for(unsigned i=0;i<8;++i)if(d.string_is(d.member(a,"target"),targets[i]))target=static_cast<int>(i);
  if(target<0)return type(d,d.member(a,"target"),ValueKind::string)==Error::none?Error::invalid_record:Error::invalid_type;
  for(auto k=d.at(axes)->first;k!=a;k=d.at(k)->next)if(equal_values(d,d.member(a,"target"),d,d.member(k,"target")))return Error::invalid_record;
  auto kind=d.member(a,"kind");if((e=type(d,kind,ValueKind::string))!=Error::none)return e;double low=target<=2||target==7?-1:0;
  if(d.string_is(kind,"fixed")){if((e=closed(d,a,{"target","kind","value"}))!=Error::none)return e;double min=version==1&&target==4?1:low;if((e=number(d,d.member(a,"value"),min,1,restore,cells))!=Error::none)return e;continue;}
  if(version==1&&target==4)return Error::invalid_record;
  if(d.string_is(kind,"key_pair")){
   if((e=closed(d,a,{"target","kind","negative","positive","rate","gain","return_to_start"}))!=Error::none)return e;
   auto neg=d.member(a,"negative"),pos=d.member(a,"positive");if((e=keys(d,neg,restore,cells))!=Error::none||(e=keys(d,pos,restore,cells))!=Error::none)return e;
   for(auto x=d.at(neg)->first;x!=no_cell;x=d.at(x)->next)for(auto y=d.at(pos)->first;y!=no_cell;y=d.at(y)->next)if(d.at(x)->scalar==d.at(y)->scalar)return Error::invalid_record;
   double rate{},gain{};if((e=number(d,d.member(a,"rate"),0,4,restore,cells,&rate))!=Error::none||(e=number(d,d.member(a,"gain"),0,1,restore,cells,&gain))!=Error::none||(e=type(d,d.member(a,"return_to_start"),ValueKind::boolean))!=Error::none)return e;
   if(!(real_compare(rate,0)>0&&real_compare(gain,0)>0)||(d.at(d.member(a,"return_to_start"))->scalar&&target>2))return Error::invalid_record;continue;
  }
  if(d.string_is(kind,"joy_axis")){
   if((e=closed(d,a,{"target","kind","slot","index","range","minimum","center","maximum","invert","deadzone","saturation","gain","slew_per_s"}))!=Error::none)return e;
   if((e=text(d,d.member(a,"slot"),1,32))!=Error::none||(e=enumeration(d,d.member(a,"index"),0,9,restore,cells))!=Error::none||(e=type(d,d.member(a,"range"),ValueKind::string))!=Error::none||(e=type(d,d.member(a,"invert"),ValueKind::boolean))!=Error::none)return e;
   if(!declared_slot(d,devices,d.member(a,"slot")))return Error::invalid_record;
   bool centered=d.string_is(d.member(a,"range"),"centered"),uns=d.string_is(d.member(a,"range"),"unsigned");if((!centered&&!uns)||(version==2&&target==4&&!uns))return Error::invalid_record;
   double mi{},ce{},ma{},dead{},sat{},gain{};
   if((e=number(d,d.member(a,"minimum"),-1,1,restore,cells,&mi))!=Error::none||(e=number(d,d.member(a,"center"),-1,1,restore,cells,&ce))!=Error::none||(e=number(d,d.member(a,"maximum"),-1,1,restore,cells,&ma))!=Error::none||(e=number(d,d.member(a,"deadzone"),0,.4,restore,cells,&dead))!=Error::none||(e=number(d,d.member(a,"saturation"),0,1,restore,cells,&sat))!=Error::none||(e=number(d,d.member(a,"gain"),0,1,restore,cells,&gain))!=Error::none||(e=number(d,d.member(a,"slew_per_s"),0,4,restore,cells))!=Error::none)return e;
   if(centered?(ce-mi<.05||ma-ce<.05):ma-mi<.05)return Error::invalid_record;if(!(real_compare(sat,dead)>0&&real_compare(gain,0)>0))return Error::invalid_record;continue;
  }return Error::invalid_record;
 }
 for(auto group:{"actions","systems"}){
  if(version==1&&group==std::string_view("systems"))continue;auto list=d.member(n,group);bool engine=group==std::string_view("systems");
  if(engine){if(!model(d,d.member(n,"profile"),true))return Error::invalid_record;if((e=exact(d,d.member(n,"capability_revision"),"piston-controls-v1"))!=Error::none||(e=collection(d,list,ValueKind::array,4,4))!=Error::none)return e;}
  for(auto a=d.at(list)->first;a!=no_cell;a=d.at(a)->next){
   e=engine?closed(d,a,{"id","kind","sources"}):closed(d,a,{"id","sources"});if(e!=Error::none)return e;auto id=d.member(a,"id");if((e=type(d,id,ValueKind::string))!=Error::none)return e;
   bool known=false;if(engine){for(auto item:systems)known|=d.string_is(id,item);if((e=exact(d,d.member(a,"kind"),d.string_is(id,"engine.starter")?"momentary":"toggle"))!=Error::none)return e;}else for(auto item:actions)known|=d.string_is(id,item);if(!known)return Error::invalid_record;
   for(auto b=d.at(list)->first;b!=a;b=d.at(b)->next)if(equal_values(d,id,d,d.member(b,"id")))return Error::invalid_record;
   auto sources=d.member(a,"sources");if((e=collection(d,sources,ValueKind::array,1,4))!=Error::none)return e;
   for(auto source=d.at(sources)->first;source!=no_cell;source=d.at(source)->next){if((e=binding_source(d,source,devices,engine,restore,cells))!=Error::none)return e;for(auto prior=d.at(sources)->first;prior!=source;prior=d.at(prior)->next)if(same_source(d,source,prior))return Error::invalid_record;}
  }
 }
 // Closed-schema bound, not a new accepted cap: at most8 devices*2304,
 //8 axes*1024,30 UNIQUE actions*512,4 systems*512 and1024 header bytes
 // =45056 tagged canonical bytes. Each allowance includes6-byte C0 escaping;
 // fixed ASCII key/slot IDs and every binary64 tag are included. Restored
 // decimal binary64 tokens are shorter than the35-byte tag. Thus every valid
 // closed preset fits both the existing65536 restored and262144 encoded caps.
 auto encoded=Writer::measure(65536);if(!encoded.value(d,n)||!encoded.good())return Error::payload_limit;
 return version==2?conflicts(d,n):Error::none;
}
Error validate_preferences(DocumentView d,std::uint32_t n,bool restore,std::span<JsonCell> cells) noexcept {
 auto e=closed(d,n,{"type","version","player_id","revision","legacy_input","piston_input","audio"});if(e!=Error::none)return e;
 if((e=validate_audio(d,d.member(n,"audio"),restore,cells))!=Error::none)return e;
 for(auto key:{"legacy_input","piston_input"}){auto p=d.member(n,key);if(!is_null(d,p)&&(e=validate_preset(d,p,key==std::string_view("legacy_input")?1:2,restore,cells))!=Error::none)return e;}
 if((e=hexadecimal(d,d.member(n,"player_id"),32))!=Error::none||(e=u64(d,d.member(n,"revision"),true))!=Error::none||(e=exact(d,d.member(n,"type"),"LocalPlayerPreferences"))!=Error::none||(e=integer(d,d.member(n,"version"),1,1))!=Error::none)return e;return Error::none;
}
Error validate_practice(DocumentView d,std::uint32_t n,bool summary) noexcept {
 auto e=closed(d,n,{"type","version","id","player_id","source","started_utc","last_observed_utc","first_tick","last_tick","observed_ticks","tick_rate_hz","status","end_reason","revision","creation_sequence","commit_sequence","archive"});if(e!=Error::none)return e;
 auto source=d.member(n,"source");if((e=validate_source(d,source))!=Error::none)return e;
 if(summary){auto a=d.member(n,"archive");if((e=closed(d,a,{"linked"}))!=Error::none||(e=type(d,d.member(a,"linked"),ValueKind::boolean))!=Error::none)return e;}else if((e=archive(d,d.member(n,"archive"),source))!=Error::none)return e;
 for(auto key:{"id","player_id"})if((e=hexadecimal(d,d.member(n,key),32))!=Error::none)return e;
 for(auto key:{"first_tick","last_tick","observed_ticks","creation_sequence","commit_sequence","revision"})if((e=u64(d,d.member(n,key),key==std::string_view("revision")||key==std::string_view("creation_sequence")||key==std::string_view("commit_sequence")))!=Error::none)return e;
 for(auto key:{"started_utc","last_observed_utc"})if((e=utc(d,d.member(n,key)))!=Error::none)return e;
 if((e=integer(d,d.member(n,"tick_rate_hz"),120,120))!=Error::none||(e=exact(d,d.member(n,"type"),"LocalPractice"))!=Error::none||(e=integer(d,d.member(n,"version"),1,1))!=Error::none||(e=type(d,d.member(n,"status"),ValueKind::string))!=Error::none)return e;
 auto get=[&](std::string_view key){FixedText<20>b;U64 value;b.from(d,d.member(n,key));U64::parse(b.view(),value);return value;};
 auto first=get("first_tick"),last=get("last_tick"),difference=get("observed_ticks"),creation=get("creation_sequence"),commit=get("commit_sequence");U64 actual;
 if(!U64::subtract(last,first,actual)||U64::compare(actual,difference)||U64::compare(creation,commit)>0)return Error::invalid_record;
 if(!summary&&!is_null(d,d.member(n,"archive"))){
  auto link=d.member(n,"archive");FixedText<20> a,b;U64 begin,end;
  if(!a.from(d,d.member(link,"first_tick"))||!b.from(d,d.member(link,"last_tick"))||!U64::parse(a.view(),begin)||!U64::parse(b.view(),end)||U64::compare(begin,first)<0||U64::compare(end,last)>0)return Error::invalid_record;
 }
 auto status=d.member(n,"status"),reason=d.member(n,"end_reason");if(d.string_is(status,"active"))return is_null(d,reason)?Error::none:Error::invalid_record;
 if((e=type(d,reason,ValueKind::string))!=Error::none)return e;
 if(d.string_is(status,"manually_ended"))return d.string_is(reason,"user_end")||d.string_is(reason,"user_restart")||d.string_is(reason,"user_quit")?Error::none:Error::invalid_record;
 if(d.string_is(status,"source_ended"))return exact(d,reason,"native_terminal");if(d.string_is(status,"interrupted"))return exact(d,reason,"previous_process_incomplete");return Error::invalid_record;
}
std::string_view kind_name(JobKind k) noexcept {auto i=static_cast<unsigned>(k);return i<std::size(kinds)?kinds[i]:std::string_view{};}
bool parse_kind(std::string_view s,JobKind& kind) noexcept {for(unsigned i=0;i<std::size(kinds);++i)if(s==kinds[i]){kind=static_cast<JobKind>(i);return true;}return false;}

Error validate_request(DocumentView d,RequestView& out,bool restore,std::span<JsonCell> cells) noexcept {
 if(type(d,d.root,ValueKind::object)!=Error::none)return Error::invalid_type;
 if(d.size(d.root)!=2)return Error::invalid_request;
 if(closed(d,d.root,{"kind","payload"})!=Error::none)return Error::invalid_request;
 auto kn=d.member(d.root,"kind"),p=d.member(d.root,"payload");
 if(type(d,kn,ValueKind::string)!=Error::none)return Error::invalid_type;
 FixedText<64> kind;if(!kind.from(d,kn))return Error::invalid_request;
 JobKind k;if(!parse_kind(kind.view(),k)||k==JobKind::start||k==JobKind::start_management)return Error::invalid_request;
 if(type(d,p,ValueKind::object)!=Error::none)return Error::invalid_type;
 out={k,d,p};Error e=Error::none;
 auto check=[&](std::initializer_list<std::string_view> names){return closed(d,p,names);};
 switch(k){
 case JobKind::list_players:case JobKind::list_recovery:return check({});
 case JobKind::create_player:e=check({"id","name","utc"});break;
 case JobKind::load_player:e=check({"player_id"});break;
 case JobKind::rename_player:e=check({"player_id","expected_revision","name","utc"});break;
 case JobKind::save_preferences:e=check({"player_id","expected_revision","seed","utc"});break;
 case JobKind::begin_practice:e=check({"seed"});break;
 case JobKind::observe_practice:e=check({"practice_id","player_id","expected_revision","expected_source","last_tick","utc"});break;
 case JobKind::end_practice:e=check({"practice_id","player_id","expected_revision","expected_source","last_tick","utc","status","end_reason"});break;
 case JobKind::link_archive:e=check({"practice_id","player_id","expected_revision","expected_source","archive"});break;
 case JobKind::list_practice:e=check({"player_id","before_creation_sequence","limit"});break;
 case JobKind::load_practice:e=check({"player_id","practice_id"});break;
 case JobKind::prune_practice:e=check({"player_id","practice_ids"});break;
 case JobKind::delete_player:e=check({"player_id","expected_revision"});break;
 case JobKind::export_player:e=check({"player_id","expected_revision","target_absolute_path"});break;
 case JobKind::delete_recovery:e=check({"snapshot_ids"});break;
 default:return Error::invalid_request;
 }if(e!=Error::none)return e;
 constexpr std::string_view fields[]={"archive","before_creation_sequence","end_reason","expected_revision","expected_source","id","last_tick","limit","name","player_id","practice_id","practice_ids","seed","snapshot_ids","status","target_absolute_path","utc"};
 for(auto key:fields){auto n=d.member(p,key);if(n==no_cell)continue;
  if(key=="archive")e=archive(d,n,d.member(p,"expected_source"));
  else if(key=="before_creation_sequence")e=is_null(d,n)?Error::none:u64(d,n);
  else if(key=="end_reason")e=text(d,n,1,32);
  else if(key=="expected_revision")e=u64(d,n,true);
  else if(key=="expected_source")e=validate_source(d,n);
  else if(key=="id"||key=="player_id"||key=="practice_id")e=hexadecimal(d,n,32);
  else if(key=="last_tick")e=u64(d,n);
  else if(key=="limit")e=integer(d,n,1,50);
  else if(key=="name"){e=text(d,n,1,40);if(e==Error::none&&!player_name_node(d,n))e=Error::invalid_record;}
  else if(key=="practice_ids"||key=="snapshot_ids"){
   e=collection(d,n,ValueKind::array,1,key=="practice_ids"?50:2);
   if(e==Error::none)for(auto a=d.at(n)->first;a!=no_cell;a=d.at(a)->next){
    if((e=hexadecimal(d,a,32))!=Error::none)break;
    for(auto b=d.at(n)->first;b!=a;b=d.at(b)->next)if(equal_values(d,a,d,b)){e=Error::invalid_record;break;}
    if(e!=Error::none)break;
   }
  }else if(key=="seed"){
   if(k==JobKind::save_preferences){
    e=closed(d,n,{"legacy_input","piston_input","audio"});if(e==Error::none)e=validate_audio(d,d.member(n,"audio"),restore,cells);
    for(auto slot:{"legacy_input","piston_input"})if(e==Error::none&&!is_null(d,d.member(n,slot)))e=validate_preset(d,d.member(n,slot),slot==std::string_view("legacy_input")?1:2,restore,cells);
   }else{
    e=closed(d,n,{"id","player_id","source","started_utc","first_tick"});
    if(e==Error::none)e=u64(d,d.member(n,"first_tick"));if(e==Error::none)e=hexadecimal(d,d.member(n,"id"),32);
    if(e==Error::none)e=hexadecimal(d,d.member(n,"player_id"),32);if(e==Error::none)e=validate_source(d,d.member(n,"source"));
    if(e==Error::none)e=utc(d,d.member(n,"started_utc"));
   }
  }else if(key=="status")e=text(d,n,1,32);
  else if(key=="target_absolute_path"){e=text(d,n,1,4096);if(e==Error::none&&!valid_path_node(d,n))e=Error::invalid_record;}
  else if(key=="utc")e=utc(d,n);
  if(e!=Error::none)return e;
 }
 if(k==JobKind::link_archive&&is_null(d,d.member(p,"archive")))return Error::invalid_record;
 if(k==JobKind::end_practice){auto s=d.member(p,"status"),r=d.member(p,"end_reason");
  if(d.string_is(s,"manually_ended")){if(!d.string_is(r,"user_end")&&!d.string_is(r,"user_restart")&&!d.string_is(r,"user_quit"))return Error::invalid_record;}
  else if(!d.string_is(s,"source_ended")||!d.string_is(r,"native_terminal"))return Error::invalid_record;
 }return Error::none;
}
Error encode_preferences(DocumentView d,std::uint32_t n,Writer& envelope,std::span<char> payload) noexcept {
 auto e=validate_preferences(d,n);if(e!=Error::none)return e;Writer inner(payload);if(!inner.value(d,n))return Error::payload_limit;
 auto hash=sha256_hex(inner.bytes());
 if(!envelope.raw("{\"format\":\"LocalPlayerPreferences\",\"payload_json\":")||!envelope.string(inner.bytes())||!envelope.raw(",\"payload_sha256\":")||!envelope.string({hash.data(),hash.size()})||!envelope.raw(",\"version\":1}"))return Error::payload_limit;
 return envelope.bytes().size()<=max_preferences?Error::none:Error::payload_limit;
}
ParseResult decode_preferences(std::string_view input,CodecWorkspace workspace,std::span<char> payload) noexcept {
 Limits outer{max_preferences,30000,12,max_preferences,max_preferences};
 auto p=parse_json(input,workspace.cells,std::as_writable_bytes(workspace.text),outer);if(!p)return p;
 auto d=p.value;auto e=closed(d,d.root,{"format","version","payload_json","payload_sha256"});if(e!=Error::none)return {e,{}};
 if((e=exact(d,d.member(d.root,"format"),"LocalPlayerPreferences"))!=Error::none||(e=integer(d,d.member(d.root,"version"),1,1))!=Error::none||(e=hexadecimal(d,d.member(d.root,"payload_sha256"),64))!=Error::none)return {e,{}};
 std::size_t used{};if(!copy_string(d,d.member(d.root,"payload_json"),payload,used))return {Error::payload_limit,{}};
 auto raw=std::string_view(payload.data(),used);auto hash=sha256_hex(raw);
 if(!d.string_is(d.member(d.root,"payload_sha256"),{hash.data(),hash.size()}))return {Error::corrupt_store,{}};
 p=parse_json(raw,workspace.cells,std::as_writable_bytes(workspace.text));if(!p)return p;
 e=validate_preferences(p.value,p.value.root,true,workspace.cells);if(e!=Error::none)return {e,{}};
 // Hash equality is not canonical grammar admission. Re-encode restored types
 // and compare both exact layers, rejecting spacing/order/escape/tag aliases.
 Writer canonical(workspace.text);if(!canonical.value(p.value,p.value.root)||canonical.bytes()!=raw)return {Error::corrupt_store,{}};
 canonical.reset();canonical.raw("{\"format\":\"LocalPlayerPreferences\",\"payload_json\":");canonical.string(raw);canonical.raw(",\"payload_sha256\":");canonical.string({hash.data(),hash.size()});canonical.raw(",\"version\":1}");
 if(!canonical.good()||canonical.bytes()!=input)return {Error::corrupt_store,{}};
 return p;
}
} // namespace flight::local_players
