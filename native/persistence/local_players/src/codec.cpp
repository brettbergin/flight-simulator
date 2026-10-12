// Original MIT. Strict bounded JSON and binary64 transport, no JSON decimal doubles.
#include "flight/local_players/codec.hpp"
#include <algorithm>
#include <charconv>
#include <cstring>
#include <limits>

namespace flight::local_players {
namespace {
constexpr char hex[]="0123456789abcdef";
constexpr std::array<std::string_view,40> errors={"","wrong_thread","invalid_state","invalid_request","invalid_type","invalid_record","payload_limit","queue_full","out_of_memory","not_found","identity_conflict","revision_conflict","source_mismatch","tick_regression","invalid_transition","player_limit","history_limit","active_practice","counter_exhausted","store_locked","root_unavailable","unsupported_version","foreign_store","corrupt_store","recovery_required","recovery_limit","snapshot_failed","storage_full","busy","io_error","worker_lost","commit_unknown","verification_failed","target_exists","path_rejected","file_create_failed","file_write_failed","file_flush_failed","file_verify_failed","file_recovery_required"};
int nibble(char c) noexcept { if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1; }
using Cursor=StringCursor;
bool put_utf8(std::uint32_t cp,std::span<char> out,std::size_t& used) noexcept {
 char b[4];std::size_t n=0;if(cp<128)b[n++]=static_cast<char>(cp);else if(cp<2048){b[n++]=static_cast<char>(0xc0|(cp>>6));b[n++]=static_cast<char>(0x80|(cp&63));}else if(cp<65536){b[n++]=static_cast<char>(0xe0|(cp>>12));b[n++]=static_cast<char>(0x80|((cp>>6)&63));b[n++]=static_cast<char>(0x80|(cp&63));}else{b[n++]=static_cast<char>(0xf0|(cp>>18));b[n++]=static_cast<char>(0x80|((cp>>12)&63));b[n++]=static_cast<char>(0x80|((cp>>6)&63));b[n++]=static_cast<char>(0x80|(cp&63));}if(n>out.size()-used)return false;std::memcpy(out.data()+used,b,n);used+=n;return true;
}
bool same(Cursor a,Cursor b) noexcept {std::uint32_t x{},y{};for(;;){bool p=a.next(x),q=b.next(y);if(p!=q||!a.good||!b.good)return false;if(!p)return true;if(x!=y)return false;}}
int key_compare(DocumentView d,std::uint32_t a,std::uint32_t b) noexcept {auto x=string_cursor(d,a,true),y=string_cursor(d,b,true);std::uint32_t p{},q{};for(;;){bool u=x.next(p),v=y.next(q);if(!u||!v)return u?1:v?-1:0;if(p!=q)return p<q?-1:1;}}
struct Duplicate {std::uint32_t parent,node;};
struct Parser {
 std::string_view input; std::span<JsonCell> cells;std::span<std::byte> table;Limits limits;
 std::size_t pos{},used{};Error error{Error::none};
 void fail(Error e=Error::invalid_record) noexcept {if(error==Error::none)error=e;}
 void ws() noexcept {while(pos<input.size()&&(input[pos]==' '||input[pos]=='\t'||input[pos]=='\r'||input[pos]=='\n'))++pos;}
 bool consume(char c) noexcept {ws();if(pos<input.size()&&input[pos]==c){++pos;return true;}return false;}
 bool string_token(std::uint32_t& offset,std::uint32_t& length,bool key=false) noexcept {
  if(pos==input.size()||input[pos++]!='"'){fail();return false;}auto begin=pos;
  while(pos<input.size()){
   auto c=static_cast<unsigned char>(input[pos]);
   if(c=='"')break;
   if(c<32){fail();return false;}
   if(c=='\\'){if(key){fail();return false;}++pos;if(pos==input.size()){fail();return false;}++pos;}else ++pos;
  }
  if(pos==input.size()){fail();return false;}auto raw=input.substr(begin,pos-begin);++pos;
  Cursor cur{raw};std::uint32_t cp{};std::size_t scalar=0,bytes=0;
  while(cur.next(cp)){++scalar;bytes+=cp<128?1:cp<2048?2:cp<65536?3:4;if(scalar>limits.scalars||bytes>limits.string_bytes){fail(Error::payload_limit);return false;}}
  if(!cur.good){fail();return false;}
  if(raw.size()>UINT32_MAX){fail(Error::payload_limit);return false;}
  offset=static_cast<std::uint32_t>(begin);length=static_cast<std::uint32_t>(raw.size());return true;
 }
 bool unique(std::uint32_t parent,std::uint32_t node) noexcept {
  auto key=input.substr(cells[node].key_offset,cells[node].key_length);std::uint64_t h=1469598103934665603ULL^parent;
  for(unsigned char b:key){h^=b;h*=1099511628211ULL;}
  constexpr std::size_t count=65536;std::size_t slot=static_cast<std::size_t>(h)&(count-1);
  for(std::size_t k=0;k<count;++k,slot=(slot+1)&(count-1)){
   Duplicate item{};std::memcpy(&item,table.data()+slot*sizeof(item),sizeof(item));
   if(item.node==no_cell){item={parent,node};std::memcpy(table.data()+slot*sizeof(item),&item,sizeof(item));return true;}
   if(item.parent==parent){auto prior=input.substr(cells[item.node].key_offset,cells[item.node].key_length);if(prior==key){fail();return false;}}
  }fail(Error::out_of_memory);return false;
 }
 std::uint32_t value(std::size_t depth) noexcept {
  ws();if(pos==input.size()){fail();return no_cell;}
  if(used>=limits.values||used>=cells.size()){fail(Error::payload_limit);return no_cell;}
  auto n=static_cast<std::uint32_t>(used++);cells[n]=JsonCell{};auto& c=cells[n];auto begin=pos;char t=input[pos];
  if(t=='{'||t=='['){
   if(depth+1>limits.depth){fail(Error::payload_limit);return no_cell;}++pos;c.kind=t=='{'?ValueKind::object:ValueKind::array;std::uint32_t last=no_cell;
   ws();char closing=t=='{'?'}':']';if(consume(closing)){c.offset=static_cast<std::uint32_t>(begin);c.length=static_cast<std::uint32_t>(pos-begin);return n;}
   for(;;){std::uint32_t ko=0,kl=0;if(t=='{'){ws();if(!string_token(ko,kl,true)||kl>UINT16_MAX||!consume(':')){fail();return no_cell;}}
    auto child=value(depth+1);if(child==no_cell)return no_cell;
    if(t=='{'){cells[child].key_offset=ko;cells[child].key_length=static_cast<std::uint16_t>(kl);if(!unique(n,child))return no_cell;}
    if(last==no_cell)c.first=child;else cells[last].next=child;last=child;
    if(consume(closing))break;if(!consume(',')){fail();return no_cell;}ws();if(pos==input.size()||input[pos]==closing){fail();return no_cell;}
   }
  }else if(t=='"'){c.kind=ValueKind::string;if(!string_token(c.offset,c.length))return no_cell;return n;
  }else if(input.substr(pos,4)=="null"){pos+=4;c.kind=ValueKind::null;
  }else if(input.substr(pos,4)=="true"){pos+=4;c.kind=ValueKind::boolean;c.scalar=1;
  }else if(input.substr(pos,5)=="false"){pos+=5;c.kind=ValueKind::boolean;
  }else{
   bool negative=t=='-';if(negative)++pos;if(pos==input.size()||input[pos]<'0'||input[pos]>'9'){fail();return no_cell;}
   if(input[pos]=='0'){++pos;if(negative){fail();return no_cell;}if(pos<input.size()&&input[pos]>='0'&&input[pos]<='9'){fail();return no_cell;}}
   else while(pos<input.size()&&input[pos]>='0'&&input[pos]<='9')++pos;
   if(pos<input.size()&&(input[pos]=='.'||input[pos]=='e'||input[pos]=='E')){fail();return no_cell;}
   std::int64_t result{};auto r=std::from_chars(input.data()+begin,input.data()+pos,result);if(r.ec!=std::errc{}||r.ptr!=input.data()+pos){fail();return no_cell;}c.kind=ValueKind::integer;c.scalar=std::bit_cast<std::uint64_t>(result);
  }
  c.offset=static_cast<std::uint32_t>(begin);c.length=static_cast<std::uint32_t>(pos-begin);return n;
 }
};
bool write_cursor(Writer& w,Cursor c) noexcept {if(!w.character('"'))return false;std::uint32_t cp{};while(c.next(cp)){
 if(cp=='"'||cp=='\\'){if(!w.character('\\')||!w.character(static_cast<char>(cp)))return false;}
 else if(cp<32){char b[6]={'\\','u','0','0',hex[(cp>>4)&15],hex[cp&15]};if(!w.raw({b,6}))return false;}
 else{char b[4];std::size_t n=0;if(!put_utf8(cp,b,n)||!w.raw({b,n}))return false;}
 }return c.good&&w.character('"');}
} // namespace
bool StringCursor::next(std::uint32_t& cp) noexcept {
 auto& s=source;auto& i=position;
  if(i==s.size())return false;
  auto b=static_cast<unsigned char>(s[i++]);
  if(!literal&&b=='\\') {
   if(i==s.size()){good=false;return false;} char e=s[i++];
   switch(e){case '"':cp='"';return true;case '\\':cp='\\';return true;case '/':cp='/';return true;case 'b':cp=8;return true;case 'f':cp=12;return true;case 'n':cp=10;return true;case 'r':cp=13;return true;case 't':cp=9;return true;case 'u':break;default:good=false;return false;}
   auto unit=[&](std::uint32_t& v){v=0;if(s.size()-i<4)return false;for(int j=0;j<4;++j){int n=nibble(s[i++]);if(n<0)return false;v=(v<<4)|static_cast<unsigned>(n);}return true;};
   std::uint32_t a{};if(!unit(a)){good=false;return false;}
   if(a>=0xd800&&a<=0xdbff){if(s.size()-i<6||s[i]!='\\'||s[i+1]!='u'){good=false;return false;}i+=2;std::uint32_t d{};if(!unit(d)||d<0xdc00||d>0xdfff){good=false;return false;}cp=0x10000+((a-0xd800)<<10)+(d-0xdc00);return true;}
   if(a>=0xdc00&&a<=0xdfff){good=false;return false;}cp=a;return true;
  }
  if(b<0x80){cp=b;return true;}
  unsigned count{};std::uint32_t low{};
  if(b>=0xc2&&b<=0xdf){count=1;cp=b&31;low=0x80;}
  else if(b>=0xe0&&b<=0xef){count=2;cp=b&15;low=0x800;}
  else if(b>=0xf0&&b<=0xf4){count=3;cp=b&7;low=0x10000;}
  else {good=false;return false;}
  if(s.size()-i<count){good=false;return false;}
  for(unsigned j=0;j<count;++j){auto c=static_cast<unsigned char>(s[i++]);if((c&0xc0)!=0x80){good=false;return false;}cp=(cp<<6)|(c&63);}
  if(cp<low||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff)){good=false;return false;}return true;

}
StringCursor string_cursor(DocumentView d,std::uint32_t n,bool key) noexcept {
 auto c=d.at(n);if(!c)return {{},0,true,false};
 std::size_t o=key?c->key_offset:c->offset,len=key?c->key_length:c->length;
 if(o>d.bytes.size()||len>d.bytes.size()-o)return {{},0,true,false};
 return {d.bytes.substr(o,len),0,(c->flags&1)!=0,true};
}
bool string_metrics(DocumentView d,std::uint32_t n,std::size_t& bytes,std::size_t& scalars) noexcept {
 auto p=d.at(n);if(!p||p->kind!=ValueKind::string)return false;
 auto c=string_cursor(d,n);bytes=scalars=0;std::uint32_t cp{};
 while(c.next(cp)){++scalars;bytes+=cp<128?1:cp<2048?2:cp<65536?3:4;}
 return c.good;
}
std::string_view error_name(Error e) noexcept {auto n=static_cast<std::size_t>(e);return n<errors.size()?errors[n]:"invalid_record";}
const JsonCell* DocumentView::at(std::uint32_t n) const noexcept {return n<cells.size()?&cells[n]:nullptr;}
std::uint32_t DocumentView::member(std::uint32_t object,std::string_view key) const noexcept {auto c=at(object);if(!c||c->kind!=ValueKind::object)return no_cell;for(auto n=c->first;n!=no_cell;){auto v=at(n);if(!v)return no_cell;if(key_is(n,key))return n;n=v->next;}return no_cell;}
std::uint32_t DocumentView::size(std::uint32_t node) const noexcept {auto c=at(node);if(!c||(c->kind!=ValueKind::array&&c->kind!=ValueKind::object))return 0;std::uint32_t count=0;for(auto n=c->first;n!=no_cell;){auto v=at(n);if(!v||++count>cells.size())return UINT32_MAX;n=v->next;}return count;}
bool DocumentView::string_is(std::uint32_t n,std::string_view s) const noexcept {auto c=at(n);return c&&c->kind==ValueKind::string&&same(string_cursor(*this,n),Cursor{s,0,true});}
bool DocumentView::key_is(std::uint32_t n,std::string_view s) const noexcept {return at(n)&&same(string_cursor(*this,n,true),Cursor{s,0,true});}
bool valid_utf8(std::string_view s,std::size_t* count) noexcept {Cursor c{s,0,true};std::size_t n=0;std::uint32_t cp{};while(c.next(cp))++n;if(count)*count=n;return c.good;}
bool copy_string(DocumentView d,std::uint32_t n,std::span<char> out,std::size_t& used) noexcept {auto v=d.at(n);if(!v||v->kind!=ValueKind::string)return false;auto c=string_cursor(d,n);used=0;std::uint32_t cp{};while(c.next(cp))if(!put_utf8(cp,out,used))return false;return c.good;}
bool copy_key(DocumentView d,std::uint32_t n,std::span<char> out,std::size_t& used) noexcept {auto c=string_cursor(d,n,true);used=0;std::uint32_t cp{};while(c.next(cp))if(!put_utf8(cp,out,used))return false;return c.good;}
ParseResult parse_json(std::string_view input,std::span<JsonCell> cells,std::span<std::byte> table,Limits limits) noexcept {
 if(input.empty())return {Error::invalid_record,{}};if(input.size()>limits.bytes||input.size()>UINT32_MAX)return {Error::payload_limit,{}};
 if(table.size()<65536*sizeof(Duplicate))return {Error::out_of_memory,{}};
 if(!valid_utf8(input))return {Error::invalid_record,{}};
 std::memset(table.data(),0xff,65536*sizeof(Duplicate));Parser p{input,cells,table,limits};auto root=p.value(0);p.ws();if(p.pos!=input.size())p.fail();
 if(p.error!=Error::none||root==no_cell)return {p.error==Error::none?Error::invalid_record:p.error,{}};
 return {Error::none,{input,cells.first(p.used),root}};
}
bool equal_values(DocumentView a,std::uint32_t x,DocumentView b,std::uint32_t y) noexcept {auto p=a.at(x),q=b.at(y);if(!p||!q||p->kind!=q->kind)return false;switch(p->kind){case ValueKind::null:return true;case ValueKind::boolean:case ValueKind::integer:case ValueKind::real:return p->scalar==q->scalar;case ValueKind::string:return same(string_cursor(a,x),string_cursor(b,y));default:break;}if(a.size(x)!=b.size(y))return false;if(p->kind==ValueKind::array){auto i=p->first,j=q->first;while(i!=no_cell){if(!equal_values(a,i,b,j))return false;i=a.at(i)->next;j=b.at(j)->next;}return true;}for(auto i=p->first;i!=no_cell;i=a.at(i)->next){auto j=q->first;while(j!=no_cell&&!same(string_cursor(a,i,true),string_cursor(b,j,true)))j=b.at(j)->next;if(j==no_cell||!equal_values(a,i,b,j))return false;}return true;}
Error validate_capture(DocumentView d,Limits limits,std::size_t max_members) noexcept {
 if(d.root!=0||d.cells.empty()||d.cells.size()>limits.values||d.bytes.size()>limits.bytes)return Error::payload_limit;
 if(d.cells[0].next!=no_cell)return Error::invalid_record;
 std::size_t cursor=0,encoded_values=d.cells.size();
 auto text=[&](std::uint32_t offset,std::size_t length){
  if(offset>d.bytes.size()||length>d.bytes.size()-offset)return false;
  auto value=d.bytes.substr(offset,length);std::size_t count=0;
  return length<=limits.string_bytes&&valid_utf8(value,&count)&&count<=limits.scalars;
 };
 auto visit=[&](auto&& self,std::size_t depth)->Error {
  if(cursor>=d.cells.size())return Error::invalid_record;
  auto n=static_cast<std::uint32_t>(cursor++);const auto& cell=d.cells[n];
  if(cell.flags!=1||static_cast<unsigned>(cell.kind)>static_cast<unsigned>(ValueKind::object))return Error::invalid_type;
  if(cell.kind==ValueKind::string&&!text(cell.offset,cell.length))return Error::payload_limit;
  if(cell.kind==ValueKind::real){
   if(!finite_binary64(std::bit_cast<double>(cell.scalar)))return Error::invalid_record;
   // Canonical real tags add one string VALUE and one container level. These
   // same transport caps must be known before reservation, not discovered late.
   if(++encoded_values>limits.values||depth+1>limits.depth)return Error::payload_limit;
  }
  if(cell.kind==ValueKind::boolean&&cell.scalar>1)return Error::invalid_type;
  bool object=cell.kind==ValueKind::object,container=object||cell.kind==ValueKind::array;
  if(!container)return cell.first==no_cell?Error::none:Error::invalid_record;
  if(depth+1>limits.depth)return Error::payload_limit;
  // First count the sibling chain with a hard linear bound. A broad malformed
  // object is rejected before O(members^2) duplicate or canonical-order work.
  auto count=d.size(n);if(count==UINT32_MAX)return Error::invalid_record;
  if(object&&count>max_members)return Error::invalid_record;
  auto child=cell.first;
  for(std::uint32_t i=0;i<count;++i){
   if(child!=cursor||child>=d.cells.size())return Error::invalid_record;
   const auto& v=d.cells[child];
   if(object){
    if(!text(v.key_offset,v.key_length))return Error::payload_limit;
    auto key=d.bytes.substr(v.key_offset,v.key_length);
    for(auto prior=cell.first;prior!=child;prior=d.cells[prior].next)
     if(d.bytes.substr(d.cells[prior].key_offset,d.cells[prior].key_length)==key)return Error::invalid_record;
   }else if(v.key_length!=0)return Error::invalid_record;
   auto next=v.next;auto e=self(self,depth+1);if(e!=Error::none)return e;
   if(next!=no_cell&&next!=cursor)return Error::invalid_record;
   child=next;
  }
  return child==no_cell?Error::none:Error::invalid_record;
 };
 auto e=visit(visit,0);return e!=Error::none?e:cursor==d.cells.size()?Error::none:Error::invalid_record;
}
bool Writer::raw(std::string_view s) noexcept {if(!good_||s.size()>limit_-used_){good_=false;return false;}if(!counting_)std::memmove(out_.data()+used_,s.data(),s.size());used_+=s.size();return true;}
bool Writer::character(char c) noexcept {return raw({&c,1});}
bool Writer::string(std::string_view s) noexcept {if(valid_utf8(s)&&write_cursor(*this,Cursor{s,0,true}))return true;good_=false;return false;}
bool Writer::string(DocumentView d,std::uint32_t n) noexcept {if(d.at(n)&&d.at(n)->kind==ValueKind::string&&write_cursor(*this,string_cursor(d,n)))return true;good_=false;return false;}
bool Writer::integer(std::int64_t n) noexcept {char b[24];auto r=std::to_chars(b,b+sizeof(b),n);if(r.ec==std::errc{})return raw({b,static_cast<std::size_t>(r.ptr-b)});good_=false;return false;}
bool finite_binary64(double x) noexcept {static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559);return (std::bit_cast<std::uint64_t>(x)&0x7ff0000000000000ULL)!=0x7ff0000000000000ULL;}
bool Writer::binary64(double x) noexcept {if(!finite_binary64(x)){good_=false;return false;}auto bits=std::bit_cast<std::uint64_t>(x);char b[16];for(unsigned i=0;i<8;++i){unsigned v=static_cast<unsigned>((bits>>(i*8))&255);b[2*i]=hex[v>>4];b[2*i+1]=hex[v&15];}return raw("{\"$binary64_le\":\"")&&raw({b,16})&&raw("\"}");}
bool Writer::value(DocumentView d,std::uint32_t n,bool tags) noexcept {auto c=d.at(n);if(!c){good_=false;return false;}switch(c->kind){case ValueKind::null:return raw("null");case ValueKind::boolean:return raw(c->scalar?"true":"false");case ValueKind::integer:return integer(std::bit_cast<std::int64_t>(c->scalar));case ValueKind::real:if(!tags){good_=false;return false;}return binary64(std::bit_cast<double>(c->scalar));case ValueKind::string:return string(d,n);default:break;}
 bool object=c->kind==ValueKind::object;if(!character(object?'{':'['))return false;auto count=d.size(n);std::uint32_t previous=no_cell;
 for(std::uint32_t k=0;k<count;++k){std::uint32_t selected=no_cell;if(object){for(auto j=c->first;j!=no_cell;j=d.at(j)->next)if((previous==no_cell||key_compare(d,previous,j)<0)&&(selected==no_cell||key_compare(d,j,selected)<0))selected=j;}else selected=k==0?c->first:d.at(previous)->next;if(selected==no_cell){good_=false;return false;}if(k&&!character(','))return false;if(object&&(!write_cursor(*this,string_cursor(d,selected,true))||!character(':'))){good_=false;return false;}if(!value(d,selected,tags))return false;previous=selected;}
 return character(object?'}':']');}
bool rewrite_object(Writer& w,DocumentView d,std::uint32_t n,std::span<const Replacement> replacements) noexcept {auto c=d.at(n);if(!c||c->kind!=ValueKind::object)return false;for(std::size_t i=0;i<replacements.size();++i){if(d.member(n,replacements[i].key)==no_cell)return false;for(std::size_t j=0;j<i;++j)if(replacements[j].key==replacements[i].key)return false;}if(!w.character('{'))return false;std::uint32_t prior=no_cell;for(std::uint32_t i=0;i<d.size(n);++i){std::uint32_t selected=no_cell;for(auto j=c->first;j!=no_cell;j=d.at(j)->next)if((prior==no_cell||key_compare(d,prior,j)<0)&&(selected==no_cell||key_compare(d,j,selected)<0))selected=j;if(i&&!w.character(','))return false;if(!write_cursor(w,string_cursor(d,selected,true))||!w.character(':'))return false;bool replaced=false;for(auto& r:replacements)if(d.key_is(selected,r.key)){if(!w.raw(r.canonical_value))return false;replaced=true;break;}if(!replaced&&!w.value(d,selected))return false;prior=selected;}return w.character('}');}
bool lower_hex(std::string_view s,std::size_t size) noexcept {if(s.size()!=size)return false;for(char c:s)if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;return true;}
bool decode_binary64_tag(DocumentView d,std::uint32_t n,double& result) noexcept {auto c=d.at(n);if(!c||c->kind!=ValueKind::object||d.size(n)!=1)return false;auto leaf=d.member(n,"$binary64_le");char b[16];std::size_t used{};if(!copy_string(d,leaf,b,used)||!lower_hex({b,used},16))return false;std::uint64_t bits{};for(unsigned i=0;i<8;++i)bits|=static_cast<std::uint64_t>((nibble(b[2*i])<<4)|nibble(b[2*i+1]))<<(8*i);result=std::bit_cast<double>(bits);return finite_binary64(result);}
namespace {
constexpr std::uint32_t K[64]={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
}
Sha256::Sha256() noexcept : state_{0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19} {}
void Sha256::compress() noexcept {std::uint32_t w[64];for(unsigned i=0;i<16;++i){w[i]=0;for(unsigned j=0;j<4;++j)w[i]=(w[i]<<8)|std::to_integer<unsigned>(block_[i*4+j]);}for(unsigned i=16;i<64;++i){auto a=w[i-15],b=w[i-2];w[i]=w[i-16]+(std::rotr(a,7)^std::rotr(a,18)^(a>>3))+w[i-7]+(std::rotr(b,17)^std::rotr(b,19)^(b>>10));}auto a=state_[0],b=state_[1],c=state_[2],d=state_[3],e=state_[4],f=state_[5],g=state_[6],h=state_[7];for(unsigned i=0;i<64;++i){auto t=h+(std::rotr(e,6)^std::rotr(e,11)^std::rotr(e,25))+((e&f)^(~e&g))+K[i]+w[i];auto u=(std::rotr(a,2)^std::rotr(a,13)^std::rotr(a,22))+((a&b)^(a&c)^(b&c));h=g;g=f;f=e;e=d+t;d=c;c=b;b=a;a=t+u;}state_[0]+=a;state_[1]+=b;state_[2]+=c;state_[3]+=d;state_[4]+=e;state_[5]+=f;state_[6]+=g;state_[7]+=h;}
void Sha256::update(std::span<const std::byte> bytes) noexcept {bytes_+=bytes.size();for(auto b:bytes){block_[used_++]=b;if(used_==64){compress();used_=0;}}}
std::array<std::byte,32> Sha256::finish() noexcept {auto bits=bytes_*8;block_[used_++]=std::byte{0x80};if(used_>56){while(used_<64)block_[used_++]=std::byte{};compress();used_=0;}while(used_<56)block_[used_++]=std::byte{};for(int i=7;i>=0;--i)block_[used_++]=static_cast<std::byte>((bits>>(8*i))&255);compress();std::array<std::byte,32> result{};for(unsigned i=0;i<8;++i)for(unsigned j=0;j<4;++j)result[i*4+j]=static_cast<std::byte>((state_[i]>>(24-j*8))&255);return result;}
std::array<char,64> sha256_hex(std::string_view s) noexcept {Sha256 h;h.update(s);auto digest=h.finish();std::array<char,64> result{};for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(digest[i]);result[i*2]=hex[b>>4];result[i*2+1]=hex[b&15];}return result;}
} // namespace flight::local_players
