// Original MIT. ADR026 single-worker repository; SQLite has no flight authority.
#include "flight/local_players/store.hpp"
#include <sqlite3.h>
#include <algorithm>
#include <cstring>
#include <thread>
#include <new>
#include <type_traits>

namespace flight::local_players {
namespace {
constexpr std::string_view ddl=R"SQL(CREATE TABLE meta (
  singleton INTEGER PRIMARY KEY CHECK(singleton=1),
  schema_version INTEGER NOT NULL CHECK(schema_version=1),
  schema_fingerprint TEXT NOT NULL CHECK(length(schema_fingerprint)=64 AND schema_fingerprint NOT GLOB '*[^0-9a-f]*'),
  codec_fingerprint TEXT NOT NULL CHECK(length(codec_fingerprint)=64 AND codec_fingerprint NOT GLOB '*[^0-9a-f]*'),
  store_id TEXT NOT NULL CHECK(length(store_id)=32 AND store_id NOT GLOB '*[^0-9a-f]*'),
  owner_run_id TEXT NOT NULL CHECK(length(owner_run_id)=32 AND owner_run_id NOT GLOB '*[^0-9a-f]*'),
  created_utc TEXT NOT NULL CHECK(length(created_utc)=20),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND (commit_sequence='0' OR substr(commit_sequence,1,1)!='0') AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615'))
) STRICT;
CREATE TABLE players (
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT;
CREATE TABLE preferences (
  player_id TEXT PRIMARY KEY NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 614400),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT;
CREATE TABLE practices (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  source_fingerprint TEXT NOT NULL CHECK(length(source_fingerprint)=64 AND source_fingerprint NOT GLOB '*[^0-9a-f]*'),
  source_session TEXT NOT NULL CHECK(length(source_session) BETWEEN 1 AND 128),
  creation_sequence TEXT NOT NULL UNIQUE CHECK(length(creation_sequence) BETWEEN 1 AND 20 AND creation_sequence NOT GLOB '*[^0-9]*' AND substr(creation_sequence,1,1) BETWEEN '1' AND '9' AND (length(creation_sequence)<20 OR creation_sequence COLLATE BINARY<='18446744073709551615')),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  status TEXT NOT NULL CHECK(status IN ('active','manually_ended','source_ended','interrupted')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*'),
  UNIQUE(source_fingerprint,source_session)
) STRICT;
CREATE UNIQUE INDEX practices_one_active ON practices(status) WHERE status='active';
CREATE INDEX practices_player_creation ON practices(player_id,length(creation_sequence) DESC,creation_sequence COLLATE BINARY DESC);
)SQL";
constexpr std::string_view sqlite_version="3.53.4";
constexpr std::string_view sqlite_source="bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc";
struct Lease {
 std::atomic_flag* flag{};
 explicit Lease(WorkingMemory& m) noexcept:flag(m.codec_lease){while(flag&&flag->test_and_set(std::memory_order_acquire))std::this_thread::yield();}
 ~Lease(){if(flag)flag->clear(std::memory_order_release);}
};
// Scalar trace of actual SQLite API returns for post-verification observations.
// Semantic record rejection does not fabricate SQLITE_CORRUPT as an API return.
struct SqlTrace;
thread_local SqlTrace* active_sql_trace{};
struct SqlTrace {
 SqlTrace* previous{active_sql_trace};int result{},first_failure{};bool actual{},failed{};
 int observed_result()const noexcept{return failed?first_failure:result;}
 SqlTrace()noexcept{active_sql_trace=this;}~SqlTrace(){active_sql_trace=previous;}
};
int trace_sql(int rc)noexcept {
 if(active_sql_trace){auto& trace=*active_sql_trace;trace.result=rc;trace.actual=true;const int primary=rc&255;
  if(!trace.failed&&primary!=SQLITE_OK&&primary!=SQLITE_ROW&&primary!=SQLITE_DONE){trace.first_failure=rc;trace.failed=true;}}
 return rc;
}
struct Statement {
 sqlite3_stmt* p{};int rc{SQLITE_OK};
 Statement(sqlite3* db,std::string_view sql) noexcept {const char* tail{};rc=trace_sql(sqlite3_prepare_v3(db,sql.data(),static_cast<int>(sql.size()),0,&p,&tail));if(rc==SQLITE_OK&&tail!=sql.data()+sql.size()){sqlite3_finalize(p);p=nullptr;rc=SQLITE_MISUSE;}}
 ~Statement(){close();}
 int close() noexcept {if(!p)return SQLITE_OK;auto* actual=p;p=nullptr;return sqlite3_finalize(actual);}
 bool text(int n,std::string_view s) noexcept {if(!p||rc!=SQLITE_OK)return false;rc=trace_sql(sqlite3_bind_text64(p,n,s.data(),s.size(),SQLITE_TRANSIENT,SQLITE_UTF8));return rc==SQLITE_OK;}
 bool blob(int n,std::string_view s) noexcept {if(!p||rc!=SQLITE_OK)return false;rc=trace_sql(sqlite3_bind_blob64(p,n,s.data(),s.size(),SQLITE_TRANSIENT));return rc==SQLITE_OK;}
 int step() noexcept {return p&&rc==SQLITE_OK?trace_sql(sqlite3_step(p)):rc;}
};
std::string_view col(sqlite3_stmt* s,int n) noexcept {auto p=sqlite3_column_text(s,n);int z=sqlite3_column_bytes(s,n);return p&&z>=0?std::string_view(reinterpret_cast<const char*>(p),static_cast<std::size_t>(z)):std::string_view{};}
std::string_view blob(sqlite3_stmt* s,int n) noexcept {auto p=sqlite3_column_blob(s,n);int z=sqlite3_column_bytes(s,n);return p&&z>=0?std::string_view(static_cast<const char*>(p),static_cast<std::size_t>(z)):std::string_view{};}
Error sql_error(int rc) noexcept {switch(rc&255){case SQLITE_OK:case SQLITE_ROW:case SQLITE_DONE:return Error::none;case SQLITE_BUSY:case SQLITE_LOCKED:return Error::busy;case SQLITE_FULL:return Error::storage_full;case SQLITE_NOMEM:return Error::storage_full;case SQLITE_CORRUPT:case SQLITE_NOTADB:return Error::corrupt_store;default:return Error::io_error;}}
int exec(sqlite3* db,std::string_view sql) noexcept {Statement s(db,sql);return s.rc==SQLITE_OK?s.step():s.rc;}
int scalar(sqlite3* db,std::string_view sql,std::int64_t& value) noexcept {Statement s(db,sql);int r=s.step();if(r!=SQLITE_ROW||sqlite3_column_type(s.p,0)!=SQLITE_INTEGER)return r==SQLITE_ROW?SQLITE_CORRUPT:r;value=sqlite3_column_int64(s.p,0);return s.step()==SQLITE_DONE?SQLITE_OK:SQLITE_CORRUPT;}
bool text_scalar(sqlite3* db,std::string_view sql,std::string_view expected) noexcept {Statement s(db,sql);return s.step()==SQLITE_ROW&&sqlite3_column_type(s.p,0)==SQLITE_TEXT&&col(s.p,0)==expected&&s.step()==SQLITE_DONE;}
NativeObservation observation(sqlite3* db,Phase phase,Scope scope,Edge edge,std::uint64_t occurrence,int rc=SQLITE_OK,bool actual=false) noexcept {NativeObservation o;o.phase=phase;o.scope=scope;o.edge=edge;o.occurrence=occurrence;o.has_result=actual;o.sqlite_result=rc;if(db){o.autocommit=sqlite3_get_autocommit(db)!=0;o.txn_state=static_cast<std::uint8_t>(sqlite3_txn_state(db,"main"));}return o;}
struct EffectState {bool mutation_possible{},commit_attempted{},committed{};};
int observed_exec(sqlite3* db,std::string_view sql,Phase phase,NativeContext& c,EffectState* effect=nullptr) {
 auto n=c.next(phase,Scope::original);c.event(observation(db,phase,Scope::original,Edge::before,n));
 // Set only after the before-site returns, immediately before the REAL call.
 if(effect&&sql=="BEGIN IMMEDIATE")effect->mutation_possible=true;
 if(effect&&sql=="COMMIT")effect->commit_attempted=true;
 auto rc=exec(db,sql);
 if(effect&&sql=="BEGIN IMMEDIATE"&&sqlite3_get_autocommit(db)==1&&sqlite3_txn_state(db,"main")==SQLITE_TXN_NONE)effect->mutation_possible=false;
 if(effect&&sql=="COMMIT"&&rc==SQLITE_DONE&&sqlite3_get_autocommit(db)==1&&sqlite3_txn_state(db,"main")==SQLITE_TXN_NONE)effect->committed=true;
 if(effect&&sql=="ROLLBACK"&&(rc==SQLITE_DONE||rc==SQLITE_OK)&&sqlite3_get_autocommit(db)==1&&sqlite3_txn_state(db,"main")==SQLITE_TXN_NONE)*effect={};
 c.event(observation(db,phase,Scope::original,Edge::after,n,rc,true));return rc;
}
int row_step(sqlite3* db,Statement& statement,NativeContext& c) {
 auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db,Phase::row_write,Scope::original,Edge::before,n));auto rc=statement.step();c.event(observation(db,Phase::row_write,Scope::original,Edge::after,n,rc,true));return rc;
}
bool rollback(sqlite3* db,NativeContext& c,EffectState* effect=nullptr) {auto rc=observed_exec(db,"ROLLBACK",Phase::rollback,c,effect);return (rc==SQLITE_DONE||rc==SQLITE_OK)&&sqlite3_get_autocommit(db)==1&&sqlite3_txn_state(db,"main")==SQLITE_TXN_NONE;}

RepositoryResult failure(Error e,bool ro=false,bool un=false) noexcept {return {ResultState::failed,e,{},false,0,ro,un,false};}
RepositoryResult result(ResultState state,U64 seq={}) noexcept {RepositoryResult r;r.state=state;r.error=Error::none;r.commit_sequence=seq;r.has_sequence=state==ResultState::committed||state==ResultState::no_change;return r;}
ParseResult document(std::string_view raw,WorkingMemory& m,Limits limits={max_message,30000,12,4096,4096}) noexcept {return parse_json(raw,m.codec.cells,std::as_writable_bytes(m.codec.text),limits);}
std::string_view raw_node(DocumentView d,std::uint32_t n) noexcept {auto c=d.at(n);if(!c||c->offset>d.bytes.size()||c->length>d.bytes.size()-c->offset)return {};if(c->kind==ValueKind::string){if(!c->offset||c->length+2>d.bytes.size()-c->offset+1)return {};return d.bytes.substr(c->offset-1,c->length+2);}return d.bytes.substr(c->offset,c->length);}
bool u64_at(DocumentView d,std::uint32_t n,U64& out,bool positive=false) noexcept {FixedText<20> text;return text.from(d,n)&&U64::parse(text.view(),out,positive);}
struct Plan {
 JobKind kind{};FixedText<32> player,id;FixedText<160> name;FixedText<20> utc;
 U64 revision{},tick{},cursor{};bool has_cursor{};int limit{};
 FixedText<4096> target;FixedText<8192> archive;FixedText<1536> source;
 FixedText<32> status,end_reason;std::array<FixedText<32>,50> ids{};std::uint8_t count{};
 std::string_view preference_seed{};
};
Error plan(std::string_view request,WorkingMemory& m,Plan& out) {
 Lease lease(m);auto parsed=document(request,m);if(!parsed)return parsed.error;RequestView r;auto e=validate_request(parsed.value,r,true,m.codec.cells);if(e!=Error::none)return e;out.kind=r.kind;auto d=r.document;auto p=r.payload;
 auto get=[&](std::string_view key,auto& value){auto n=d.member(p,key);return n==no_cell||value.from(d,n);};
 if(!get("player_id",out.player)||!get("practice_id",out.id)||!get("id",out.id)||!get("name",out.name)||!get("utc",out.utc)||!get("target_absolute_path",out.target)||!get("status",out.status)||!get("end_reason",out.end_reason))return Error::invalid_record;
 auto rev=d.member(p,"expected_revision");if(rev!=no_cell&&!u64_at(d,rev,out.revision,true))return Error::invalid_record;
 auto tick=d.member(p,"last_tick");if(tick!=no_cell&&!u64_at(d,tick,out.tick))return Error::invalid_record;
 auto source=d.member(p,"expected_source");if(source!=no_cell){Writer w({out.source.data.data(),out.source.data.size()-1});if(!w.value(d,source))return Error::payload_limit;out.source.size=static_cast<std::uint32_t>(w.bytes().size());}
 auto archive=d.member(p,"archive");if(archive!=no_cell){Writer w({out.archive.data.data(),out.archive.data.size()-1});if(!w.value(d,archive))return Error::payload_limit;out.archive.size=static_cast<std::uint32_t>(w.bytes().size());}
 if(out.kind==JobKind::begin_practice){auto seed=d.member(p,"seed");out.id.from(d,d.member(seed,"id"));out.player.from(d,d.member(seed,"player_id"));out.utc.from(d,d.member(seed,"started_utc"));u64_at(d,d.member(seed,"first_tick"),out.tick);Writer w({out.source.data.data(),out.source.data.size()-1});if(!w.value(d,d.member(seed,"source")))return Error::payload_limit;out.source.size=static_cast<std::uint32_t>(w.bytes().size());}
 if(out.kind==JobKind::save_preferences)out.preference_seed=raw_node(d,d.member(p,"seed"));
 if(out.kind==JobKind::list_practice){auto c=d.member(p,"before_creation_sequence");out.has_cursor=d.at(c)->kind!=ValueKind::null;if(out.has_cursor&&!u64_at(d,c,out.cursor))return Error::invalid_record;out.limit=static_cast<int>(std::bit_cast<std::int64_t>(d.at(d.member(p,"limit"))->scalar));}
 auto ids=d.member(p,out.kind==JobKind::delete_recovery?"snapshot_ids":"practice_ids");if(ids!=no_cell)for(auto n=d.at(ids)->first;n!=no_cell;n=d.at(n)->next)out.ids[out.count++].from(d,n);
 return Error::none;
}
struct Row {
 FixedText<8192> bytes;FixedText<32> id,player,source_session;FixedText<128> session;
 FixedText<64> source_fp;FixedText<32> status;U64 revision{},creation{},sequence{},tick{},first{};
};
// Fixed simultaneously-live worker payloads belong to the charged row region.
// Primary/secondary/qualification rows have disjoint storage even when a
// post-COMMIT qualification traverses rows while earlier witnesses remain live.
// No Row/Plan/payload copy is hidden in the excluded native thread stack.
struct WorkerFrame {
 EffectState effects;
 Plan plan;
 std::array<Row,3> rows;
 FixedText<8192> changed;
 FixedText<12288> uri;
 std::array<char,1024> name_json;FixedText<160> name;FixedText<128> session;
 RecoverySet recovery;FileSet original;
 ExportReceipt export_receipt;
 std::array<RecoverySummary,2> summaries;
 std::array<char,8256> pair_prefix;
};
static_assert(sizeof(Plan)<=17408&&sizeof(Row)<=8704);
static_assert(sizeof(RecoverySet)<=9216&&sizeof(ExportReceipt)<=8704);
static_assert(sizeof(WorkerFrame)<=98304&&alignof(WorkerFrame)<=64);
static_assert(std::is_trivially_destructible_v<WorkerFrame>);
static_assert(offsetof(WorkerFrame,plan)+sizeof(Plan)<=offsetof(WorkerFrame,rows));
static_assert(offsetof(WorkerFrame,rows)+sizeof(std::array<Row,3>)<=offsetof(WorkerFrame,changed));
static_assert(offsetof(WorkerFrame,changed)+sizeof(FixedText<8192>)<=offsetof(WorkerFrame,uri));
static_assert(offsetof(WorkerFrame,pair_prefix)+8256<=sizeof(WorkerFrame));
WorkerFrame& frame(WorkingMemory& m) noexcept {
 return *std::launder(reinterpret_cast<WorkerFrame*>(m.row.data()));
}
template<class T> T& renew(T& value) noexcept {
 value.~T();return *new(&value)T{};
}
Error fetch(sqlite3* db,bool practice,std::string_view id,Row& out) noexcept {
 Statement s(db,practice?"SELECT id,player_id,source_fingerprint,source_session,creation_sequence,commit_sequence,revision,status,record,record_sha256 FROM practices WHERE id=?1":"SELECT id,id,'','',commit_sequence,commit_sequence,revision,'',record,record_sha256 FROM players WHERE id=?1");if(!s.text(1,id))return sql_error(s.rc);int rc=s.step();if(rc==SQLITE_DONE)return Error::not_found;if(rc!=SQLITE_ROW)return sql_error(rc);
 for(int i=0;i<8;++i)if(sqlite3_column_type(s.p,i)!=SQLITE_TEXT)return Error::corrupt_store;
 if(sqlite3_column_type(s.p,8)!=SQLITE_BLOB||sqlite3_column_type(s.p,9)!=SQLITE_TEXT)return Error::corrupt_store;
 auto bytes=blob(s.p,8);auto hash=sha256_hex(bytes);if(sqlite3_column_type(s.p,8)!=SQLITE_BLOB||sqlite3_column_type(s.p,9)!=SQLITE_TEXT||!out.bytes.assign(bytes)||col(s.p,9)!=std::string_view(hash.data(),64)||!out.id.assign(col(s.p,0))||!out.player.assign(col(s.p,1))||!out.source_fp.assign(col(s.p,2))||!out.session.assign(col(s.p,3))||!U64::parse(col(s.p,4),out.creation,true)||!U64::parse(col(s.p,5),out.sequence,true)||!U64::parse(col(s.p,6),out.revision,true)||!out.status.assign(col(s.p,7)))return Error::corrupt_store;
 return s.step()==SQLITE_DONE?Error::none:Error::corrupt_store;
}
Error validate_row(Row& row,bool practice,WorkingMemory& m) {
 Lease lease(m);auto p=document(row.bytes.view(),m);if(!p)return Error::corrupt_store;auto d=p.value;auto e=practice?validate_practice(d,d.root):validate_player(d,d.root);if(e!=Error::none)return Error::corrupt_store;
 if(!d.string_is(d.member(d.root,"id"),row.id.view())||!d.string_is(d.member(d.root,"revision"),row.revision.view()))return Error::corrupt_store;
 Writer canonical(m.codec.text);if(!canonical.value(d,d.root)||canonical.bytes()!=row.bytes.view())return Error::corrupt_store;
 if(practice){auto source=d.member(d.root,"source");if(!d.string_is(d.member(d.root,"player_id"),row.player.view())||!d.string_is(d.member(d.root,"creation_sequence"),row.creation.view())||!d.string_is(d.member(d.root,"commit_sequence"),row.sequence.view())||!d.string_is(d.member(d.root,"status"),row.status.view())||!d.string_is(d.member(source,"native_source_fingerprint"),row.source_fp.view())||!d.string_is(d.member(source,"session_id"),row.session.view())||!u64_at(d,d.member(d.root,"first_tick"),row.first)||!u64_at(d,d.member(d.root,"last_tick"),row.tick))return Error::corrupt_store;}
 return Error::none;
}
bool quoted(std::span<char> output,std::string_view input,std::string_view& encoded) noexcept {Writer w(output);if(!w.string(input))return false;encoded=w.bytes();return true;}
Error write_player(sqlite3* db,const Row& row,NativeContext& c) {Statement s(db,"INSERT INTO players(commit_sequence,id,revision,record,record_sha256) VALUES(?1,?2,?3,?4,?5) ON CONFLICT(id) DO UPDATE SET commit_sequence=excluded.commit_sequence,revision=excluded.revision,record=excluded.record,record_sha256=excluded.record_sha256");auto hash=sha256_hex(row.bytes.view());if(!s.text(1,row.sequence.view())||!s.text(2,row.id.view())||!s.text(3,row.revision.view())||!s.blob(4,row.bytes.view())||!s.text(5,{hash.data(),64}))return Error::io_error;auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db,Phase::row_write,Scope::original,Edge::before,n));auto rc=s.step();c.event(observation(db,Phase::row_write,Scope::original,Edge::after,n,rc,true));return rc==SQLITE_DONE&&sqlite3_changes(db)==1?Error::none:sql_error(rc==SQLITE_DONE?SQLITE_CORRUPT:rc);}
Error write_practice(sqlite3* db,const Row& row,NativeContext& c) {Statement s(db,"INSERT INTO practices(id,player_id,source_fingerprint,source_session,creation_sequence,commit_sequence,revision,status,record,record_sha256) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10) ON CONFLICT(id) DO UPDATE SET commit_sequence=excluded.commit_sequence,revision=excluded.revision,status=excluded.status,record=excluded.record,record_sha256=excluded.record_sha256");auto hash=sha256_hex(row.bytes.view());if(!s.text(1,row.id.view())||!s.text(2,row.player.view())||!s.text(3,row.source_fp.view())||!s.text(4,row.session.view())||!s.text(5,row.creation.view())||!s.text(6,row.sequence.view())||!s.text(7,row.revision.view())||!s.text(8,row.status.view())||!s.blob(9,row.bytes.view())||!s.text(10,{hash.data(),64}))return Error::io_error;auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db,Phase::row_write,Scope::original,Edge::before,n));auto rc=s.step();c.event(observation(db,Phase::row_write,Scope::original,Edge::after,n,rc,true));return rc==SQLITE_DONE&&sqlite3_changes(db)==1?Error::none:sql_error(rc==SQLITE_DONE?SQLITE_CORRUPT:rc);}
Error write_preferences(sqlite3* db,std::string_view player,U64 revision,std::string_view bytes,NativeContext& c) {Statement s(db,"INSERT INTO preferences(player_id,revision,record,record_sha256) VALUES(?1,?2,?3,?4) ON CONFLICT(player_id) DO UPDATE SET revision=excluded.revision,record=excluded.record,record_sha256=excluded.record_sha256");auto hash=sha256_hex(bytes);if(!s.text(1,player)||!s.text(2,revision.view())||!s.blob(3,bytes)||!s.text(4,{hash.data(),64}))return Error::io_error;auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db,Phase::row_write,Scope::original,Edge::before,n));auto rc=s.step();c.event(observation(db,Phase::row_write,Scope::original,Edge::after,n,rc,true));return rc==SQLITE_DONE&&sqlite3_changes(db)==1?Error::none:sql_error(rc==SQLITE_DONE?SQLITE_CORRUPT:rc);}
// SQLite owns its column blob until the statement is advanced/finalized. Pure
// validation/transcoding occurs under the lease, with no SQLite calls inside it.
Error preferences(sqlite3* db,std::string_view player,U64 revision,Writer& out,WorkingMemory& m,bool envelope=false) {
 Statement s(db,"SELECT revision,record,record_sha256 FROM preferences WHERE player_id=?1");if(!s.text(1,player)||s.step()!=SQLITE_ROW)return Error::corrupt_store;if(sqlite3_column_type(s.p,0)!=SQLITE_TEXT||sqlite3_column_type(s.p,1)!=SQLITE_BLOB||sqlite3_column_type(s.p,2)!=SQLITE_TEXT)return Error::corrupt_store;auto rev=col(s.p,0),bytes=blob(s.p,1),digest=col(s.p,2);auto hash=sha256_hex(bytes);if(sqlite3_column_type(s.p,0)!=SQLITE_TEXT||sqlite3_column_type(s.p,1)!=SQLITE_BLOB||sqlite3_column_type(s.p,2)!=SQLITE_TEXT||rev!=revision.view()||digest!=std::string_view(hash.data(),64)||bytes.empty()||bytes.size()>max_preferences)return Error::corrupt_store;
 {Lease lease(m);auto p=decode_preferences(bytes,m.codec,out.storage());if(!p||!p.value.string_is(p.value.member(p.value.root,"player_id"),player)||!p.value.string_is(p.value.member(p.value.root,"revision"),revision.view()))return Error::corrupt_store;
  auto payload=p.value.bytes;if(envelope){Writer w(m.codec.text);w.raw("{\"format\":\"LocalPlayerPreferences\",\"payload_json\":");w.string(payload);w.raw(",\"payload_sha256\":");auto h=sha256_hex(payload);w.string({h.data(),64});w.raw(",\"version\":1}");if(!w.good()||w.bytes()!=bytes)return Error::corrupt_store;std::memmove(out.storage().data(),w.bytes().data(),w.bytes().size());out.reset();out.raw({out.storage().data(),w.bytes().size()});}
  else {Writer check(m.codec.text);if(!check.value(p.value,p.value.root)||check.bytes()!=payload)return Error::corrupt_store;out.reset();out.raw(payload);}
 }
 return s.step()==SQLITE_DONE?Error::none:Error::corrupt_store;
}
Error pair(sqlite3* db,const Row& player,Writer& out,WorkingMemory& m) {out.reset();auto e=preferences(db,player.id.view(),player.revision,out,m);if(e!=Error::none)return e;auto n=out.bytes().size();auto& prefix=frame(m).pair_prefix;Writer p(prefix);p.raw("{\"player\":");p.raw(player.bytes.view());p.raw(",\"preferences\":");if(!p.good()||n+p.bytes().size()+1>out.storage().size())return Error::payload_limit;std::memmove(out.storage().data()+p.bytes().size(),out.storage().data(),n);std::memcpy(out.storage().data(),prefix.data(),p.bytes().size());out.reset();out.raw({out.storage().data(),p.bytes().size()+n});out.character('}');return out.good()?Error::none:Error::payload_limit;}
} // namespace
Store::Store(StoreAccess& a,WorkingMemory m) noexcept:access_(a),memory_(m){if(memory_.row.size()>=sizeof(WorkerFrame)&&reinterpret_cast<std::uintptr_t>(memory_.row.data())%alignof(WorkerFrame)==0)new(memory_.row.data())WorkerFrame{};else memory_.row={};}
Store::~Store(){close();if(!memory_.row.empty())frame(memory_).~WorkerFrame();}
bool Store::close() noexcept {bool sql=true;if(db_){sql=sqlite3_next_stmt(db_,nullptr)==nullptr&&sqlite3_close(db_)==SQLITE_OK;if(sql)db_=nullptr;}return sql&&access_.filesystem_&&access_.filesystem_->close_worker_handles();}
Error Store::open(std::string_view root,Scope scope,NativeContext& c,bool fresh,const FileIdentity* fresh_identity) {
 if((fresh&&(!fresh_identity||scope!=Scope::original||root!=access_.filesystem_->root()))||(!fresh&&fresh_identity))return Error::io_error;
 auto& uri=renew(frame(memory_).uri);auto e=access_.filesystem_->sqlite_uri(root,uri);if(e!=Error::none)return e;
 if(fresh){e=access_.filesystem_->release_reserved_database_for_sqlite(*fresh_identity);if(e!=Error::none)return e;}
 // The existing before_open observation exposes the real released interval.
 auto n=c.next(Phase::before_open,scope);c.event(observation(nullptr,Phase::before_open,scope,Edge::before,n));auto rc=sqlite3_open_v2(uri.data.data(),&db_,SQLITE_OPEN_READWRITE|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nullptr);c.event(observation(db_,Phase::before_open,scope,Edge::after,n,rc,true));if(rc!=SQLITE_OK)return sql_error(rc);
 if(fresh){
  void* main_handle{};
  if(sqlite3_file_control(db_,"main",SQLITE_FCNTL_WIN32_GET_HANDLE,&main_handle)!=SQLITE_OK||!main_handle||main_handle==reinterpret_cast<void*>(static_cast<std::intptr_t>(-1))||sqlite3_db_readonly(db_,"main")!=0)return Error::io_error;
  e=access_.filesystem_->verify_reserved_database(*fresh_identity,main_handle);if(e!=Error::none)return e;
 }
 // Null in shipping. An armed test action can interrupt only an actually
 // executing selected statement, never a pre-statement no-op request.
 if(c.observer)sqlite3_progress_handler(db_,1,[](void* value)->int{return static_cast<QualificationObserver*>(value)->take_sqlite_interrupt_request()?1:0;},c.observer);
 return configure(fresh);
}
Error Store::configure(bool fresh) {
 if(std::string_view(sqlite3_libversion())!=sqlite_version||std::string_view(sqlite3_sourceid()).find(sqlite_source)==std::string_view::npos||!sqlite3_compileoption_used("THREADSAFE=1")||!sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")||sqlite3_compileoption_used("NO_SYNC"))return Error::unsupported_version;
 if(sqlite3_busy_timeout(db_,2000)!=SQLITE_OK)return Error::io_error;
 if(sqlite3_set_authorizer(db_,[](void*,int action,const char* a,const char* b,const char*,const char*)->int{
  if(action==SQLITE_ATTACH||action==SQLITE_DETACH)return SQLITE_DENY;
  if(action==SQLITE_FUNCTION&&((a&&std::string_view(a)=="load_extension")||(b&&std::string_view(b)=="load_extension")))return SQLITE_DENY;
  return SQLITE_OK;
 },nullptr)!=SQLITE_OK)return Error::io_error;
 sqlite3_limit(db_,SQLITE_LIMIT_LENGTH,33554432);sqlite3_limit(db_,SQLITE_LIMIT_SQL_LENGTH,65536);sqlite3_limit(db_,SQLITE_LIMIT_VARIABLE_NUMBER,64);sqlite3_limit(db_,SQLITE_LIMIT_ATTACHED,0);sqlite3_limit(db_,SQLITE_LIMIT_COMPOUND_SELECT,16);
 int actual{};if(sqlite3_db_config(db_,SQLITE_DBCONFIG_DEFENSIVE,1,&actual)!=SQLITE_OK||actual!=1||sqlite3_db_config(db_,SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION,0,&actual)!=SQLITE_OK||actual!=0)return Error::io_error;
 if(!text_scalar(db_,"PRAGMA locking_mode=EXCLUSIVE","exclusive"))return Error::io_error;
 for(auto command:{"PRAGMA trusted_schema=OFF","PRAGMA foreign_keys=ON","PRAGMA mmap_size=0","PRAGMA synchronous=FULL"})if(sql_error(exec(db_,command))!=Error::none)return Error::io_error;
 if(fresh)for(auto command:{"PRAGMA page_size=4096","PRAGMA application_id=1179865137","PRAGMA user_version=1"})if(sql_error(exec(db_,command))!=Error::none)return Error::io_error;
 if(!text_scalar(db_,"PRAGMA journal_mode=WAL","wal"))return Error::io_error;
 std::int64_t value{};for(auto item:{std::pair{"PRAGMA synchronous",2},std::pair{"PRAGMA foreign_keys",1},std::pair{"PRAGMA trusted_schema",0},std::pair{"PRAGMA page_size",4096}})if(scalar(db_,item.first,value)!=SQLITE_OK||value!=item.second)return Error::io_error;
 if(scalar(db_,"PRAGMA max_page_count=65536",value)!=SQLITE_OK||value!=65536)return Error::storage_full;
 return Error::none;
}

Error Store::qualify(Writer& scratch,NativeContext& c,Scope scope) {
 auto occurrence=c.next(Phase::postverify,scope);
 c.event(observation(db_,Phase::postverify,scope,Edge::before,occurrence));
 SqlTrace trace;std::uint16_t verified=0;
 auto inspect=[&]()->Error {
 std::int64_t v{};if(scalar(db_,"PRAGMA application_id",v)!=SQLITE_OK||v!=1179865137)return Error::foreign_store;if(scalar(db_,"PRAGMA user_version",v)!=SQLITE_OK||v!=1)return Error::unsupported_version;
 if(!text_scalar(db_,"PRAGMA integrity_check","ok"))return Error::corrupt_store;
 {Statement s(db_,"PRAGMA foreign_key_check");if(s.step()!=SQLITE_DONE)return Error::corrupt_store;}
 constexpr std::string_view tables[]={"meta","players","preferences","practices"};
 constexpr std::string_view indexes[]={"practices_one_active","practices_player_creation"};
 constexpr std::string_view autoindexes[]={"sqlite_autoindex_players_1","sqlite_autoindex_preferences_1","sqlite_autoindex_practices_1","sqlite_autoindex_practices_2","sqlite_autoindex_practices_3"};
 std::array<bool,11> seen{};
 {Statement s(db_,"SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY name COLLATE BINARY");int rc;while((rc=s.step())==SQLITE_ROW){auto type=col(s.p,0),name=col(s.p,1),table=col(s.p,2);int at=-1;for(int i=0;i<4;++i)if(name==tables[i]&&type=="table"&&table==name)at=i;for(int i=0;i<2;++i)if(name==indexes[i]&&type=="index"&&table=="practices")at=i+4;for(int i=0;i<5;++i)if(name==autoindexes[i]&&type=="index"&&table==(i==0?"players":i==1?"preferences":"practices"))at=i+6;if(at<0||seen[at])return Error::foreign_store;seen[at]=true;
   if(at>=6){if(sqlite3_column_type(s.p,3)!=SQLITE_NULL)return Error::foreign_store;continue;}
   auto expected=ddl;bool matched=false;while(!expected.empty()){auto end=expected.find(';');if(end==std::string_view::npos)break;auto statement=expected.substr(0,end);while(!statement.empty()&&(statement.front()=='\n'||statement.front()=='\r'||statement.front()==' '))statement.remove_prefix(1);if(col(s.p,3)==statement)matched=true;expected.remove_prefix(end+1);}if(!matched)return Error::foreign_store;
  }if(rc!=SQLITE_DONE)return sql_error(rc);}
 for(bool present:seen)if(!present)return Error::corrupt_store;
 // Stored SQL and the actual table/index metadata must both agree. No added
 // hidden/generated column, non-STRICT table or partial/unique index escapes.
 struct Column {std::string_view name,type;bool not_null;bool primary;};
 constexpr Column meta_columns[]={{"singleton","INTEGER",false,true},{"schema_version","INTEGER",true,false},{"schema_fingerprint","TEXT",true,false},{"codec_fingerprint","TEXT",true,false},{"store_id","TEXT",true,false},{"owner_run_id","TEXT",true,false},{"created_utc","TEXT",true,false},{"commit_sequence","TEXT",true,false}};
 constexpr Column player_columns[]={{"commit_sequence","TEXT",true,false},{"id","TEXT",true,true},{"revision","TEXT",true,false},{"record","BLOB",true,false},{"record_sha256","TEXT",true,false}};
 constexpr Column preference_columns[]={{"player_id","TEXT",true,true},{"revision","TEXT",true,false},{"record","BLOB",true,false},{"record_sha256","TEXT",true,false}};
 constexpr Column practice_columns[]={{"id","TEXT",true,true},{"player_id","TEXT",true,false},{"source_fingerprint","TEXT",true,false},{"source_session","TEXT",true,false},{"creation_sequence","TEXT",true,false},{"commit_sequence","TEXT",true,false},{"revision","TEXT",true,false},{"status","TEXT",true,false},{"record","BLOB",true,false},{"record_sha256","TEXT",true,false}};
 const std::span<const Column> columns[]={meta_columns,player_columns,preference_columns,practice_columns};
 for(unsigned i=0;i<4;++i){
  char command[96];Writer w(command);w.raw("PRAGMA table_xinfo('");w.raw(tables[i]);w.raw("')");Statement s(db_,w.bytes());unsigned count=0;int rc;
  while((rc=s.step())==SQLITE_ROW){
   if(count>=columns[i].size())return Error::corrupt_store;const auto& column=columns[i][count];
   if(sqlite3_column_type(s.p,0)!=SQLITE_INTEGER||sqlite3_column_int(s.p,0)!=static_cast<int>(count)||sqlite3_column_type(s.p,1)!=SQLITE_TEXT||col(s.p,1)!=column.name||sqlite3_column_type(s.p,2)!=SQLITE_TEXT||col(s.p,2)!=column.type||sqlite3_column_type(s.p,3)!=SQLITE_INTEGER||sqlite3_column_int(s.p,3)!=static_cast<int>(column.not_null)||sqlite3_column_type(s.p,4)!=SQLITE_NULL||sqlite3_column_type(s.p,5)!=SQLITE_INTEGER||sqlite3_column_int(s.p,5)!=static_cast<int>(column.primary)||sqlite3_column_type(s.p,6)!=SQLITE_INTEGER||sqlite3_column_int(s.p,6)!=0)return Error::corrupt_store;
   ++count;
  }if(rc!=SQLITE_DONE||count!=columns[i].size())return Error::corrupt_store;
  w.reset();w.raw("PRAGMA foreign_key_list('");w.raw(tables[i]);w.raw("')");Statement fk(db_,w.bytes());rc=fk.step();
  if(i<2){if(rc!=SQLITE_DONE)return Error::corrupt_store;}
  else if(rc!=SQLITE_ROW||sqlite3_column_int(fk.p,0)!=0||sqlite3_column_int(fk.p,1)!=0||col(fk.p,2)!="players"||col(fk.p,3)!="player_id"||col(fk.p,4)!="id"||col(fk.p,5)!="NO ACTION"||col(fk.p,6)!="CASCADE"||col(fk.p,7)!="NONE"||fk.step()!=SQLITE_DONE)return Error::corrupt_store;
 }
 {Statement s(db_,"PRAGMA table_list");unsigned count=0;int rc;std::array<bool,4> actual{};
  while((rc=s.step())==SQLITE_ROW){auto name=col(s.p,1);if(name=="sqlite_schema"||name=="sqlite_temp_schema")continue;unsigned at=4;for(unsigned i=0;i<4;++i)if(name==tables[i])at=i;if(at==4||actual[at]||col(s.p,0)!="main"||col(s.p,2)!="table"||sqlite3_column_int(s.p,3)!=static_cast<int>(columns[at].size())||sqlite3_column_int(s.p,5)!=1||sqlite3_column_int(s.p,4)!=0)return Error::corrupt_store;actual[at]=true;++count;
  }if(rc!=SQLITE_DONE||count!=4)return Error::corrupt_store;
 }
 struct Index {std::string_view name,table,origin;bool unique,partial;std::array<int,4> cid;std::array<std::string_view,4> names;std::array<int,4> descending;unsigned count;};
 constexpr Index index_definitions[]={
  {"sqlite_autoindex_players_1","players","pk",true,false,{1,-1},{"id",""},{0,0},2},
  {"sqlite_autoindex_preferences_1","preferences","pk",true,false,{0,-1},{"player_id",""},{0,0},2},
  {"sqlite_autoindex_practices_1","practices","pk",true,false,{0,-1},{"id",""},{0,0},2},
  {"sqlite_autoindex_practices_2","practices","u",true,false,{4,-1},{"creation_sequence",""},{0,0},2},
  {"sqlite_autoindex_practices_3","practices","u",true,false,{2,3,-1},{"source_fingerprint","source_session",""},{0,0,0},3},
  {"practices_one_active","practices","c",true,true,{7,-1},{"status",""},{0,0},2},
  {"practices_player_creation","practices","c",false,false,{1,-2,4,-1},{"player_id","","creation_sequence",""},{0,1,1,0},4}
 };
 for(auto table:tables){char command[128];Writer w(command);w.raw("PRAGMA index_list('");w.raw(table);w.raw("')");Statement s(db_,w.bytes());unsigned count=0;int rc;std::array<bool,7> actual{};
  while((rc=s.step())==SQLITE_ROW){unsigned at=7;for(unsigned i=0;i<7;++i)if(col(s.p,1)==index_definitions[i].name&&table==index_definitions[i].table)at=i;if(at==7||actual[at])return Error::corrupt_store;auto& index=index_definitions[at];if(sqlite3_column_int(s.p,2)!=static_cast<int>(index.unique)||col(s.p,3)!=index.origin||sqlite3_column_int(s.p,4)!=static_cast<int>(index.partial))return Error::corrupt_store;actual[at]=true;++count;
  }unsigned expected=0;for(auto& i:index_definitions)expected+=i.table==table;if(rc!=SQLITE_DONE||count!=expected)return Error::corrupt_store;
 }
 for(const auto& index:index_definitions){char command[128];Writer w(command);w.raw("PRAGMA index_xinfo('");w.raw(index.name);w.raw("')");Statement s(db_,w.bytes());unsigned count=0;int rc;
  while((rc=s.step())==SQLITE_ROW){if(count>=index.count||sqlite3_column_int(s.p,0)!=static_cast<int>(count)||sqlite3_column_int(s.p,1)!=index.cid[count]||sqlite3_column_int(s.p,3)!=index.descending[count]||col(s.p,4)!="BINARY"||sqlite3_column_int(s.p,5)!=(count+1<index.count))return Error::corrupt_store;
   if(index.cid[count]>=0){if(sqlite3_column_type(s.p,2)!=SQLITE_TEXT||col(s.p,2)!=index.names[count])return Error::corrupt_store;}else if(sqlite3_column_type(s.p,2)!=SQLITE_NULL)return Error::corrupt_store;++count;
  }if(rc!=SQLITE_DONE||count!=index.count)return Error::corrupt_store;
 }
 {Statement s(db_,"SELECT schema_version,schema_fingerprint,codec_fingerprint,store_id,owner_run_id,created_utc,commit_sequence FROM meta WHERE singleton=1");if(s.step()!=SQLITE_ROW||sqlite3_column_int64(s.p,0)!=1||col(s.p,1)!=schema_fingerprint||col(s.p,2)!=codec_fingerprint||!lower_hex(col(s.p,3),32)||!lower_hex(col(s.p,4),32)||!valid_utc(col(s.p,5))||!store_id_.assign(col(s.p,3))||!U64::parse(col(s.p,6),sequence_,true)||s.step()!=SQLITE_DONE)return Error::corrupt_store;}
 if(scalar(db_,"SELECT count(*) FROM meta",v)!=SQLITE_OK||v!=1||scalar(db_,"SELECT count(*) FROM players",v)!=SQLITE_OK||v>8||scalar(db_,"SELECT count(*) FROM practices",v)!=SQLITE_OK||v>2000||scalar(db_,"SELECT count(*) FROM practices WHERE status='active'",v)!=SQLITE_OK||v>1)return Error::corrupt_store;

 for(bool practice:{false,true}){Statement scan(db_,practice?"SELECT id FROM practices ORDER BY id COLLATE BINARY":"SELECT id FROM players ORDER BY id COLLATE BINARY");int rc;while((rc=scan.step())==SQLITE_ROW){FixedText<32> id;if(!id.assign(col(scan.p,0)))return Error::corrupt_store;auto& row=renew(frame(memory_).rows[2]);auto e=fetch(db_,practice,id.view(),row);if(e!=Error::none||validate_row(row,practice,memory_)!=Error::none||U64::compare(row.sequence,sequence_)>0||U64::compare(row.creation,row.sequence)>0)return Error::corrupt_store;if(!practice){scratch.reset();if(preferences(db_,id.view(),row.revision,scratch,memory_,true)!=Error::none)return Error::corrupt_store;}++verified;}if(rc!=SQLITE_DONE)return sql_error(rc);}
 if(scalar(db_,"SELECT count(*) FROM preferences",v)!=SQLITE_OK)return Error::corrupt_store;std::int64_t players{};if(scalar(db_,"SELECT count(*) FROM players",players)!=SQLITE_OK||players!=v)return Error::corrupt_store;
 scratch.reset();return Error::none;
 };
 auto result=inspect();auto o=observation(db_,Phase::postverify,scope,Edge::after,occurrence,trace.observed_result(),trace.actual);o.verified_rows=verified;c.event(o);return result;
}
Error Store::initialize(Writer& scratch,NativeContext& c) {
 auto rc=observed_exec(db_,"BEGIN IMMEDIATE",Phase::before_begin,c,&frame(memory_).effects);if(rc!=SQLITE_DONE)return sql_error(rc);
 auto fail=[&](Error error){return rollback(db_,c,&frame(memory_).effects)?error:Error::commit_unknown;};
 auto rest=ddl;while(!rest.empty()){auto end=rest.find(';');if(end==std::string_view::npos)break;auto statement=rest.substr(0,end+1);while(!statement.empty()&&(statement.front()=='\n'||statement.front()=='\r'||statement.front()==' '))statement.remove_prefix(1);if(!statement.empty()&&sql_error(exec(db_,statement))!=Error::none)return fail(Error::io_error);rest.remove_prefix(end+1);}
 FixedText<20> now;if(access_.filesystem_->random_id(store_id_)!=Error::none||access_.filesystem_->utc(now)!=Error::none)return fail(Error::io_error);
 {Statement s(db_,"INSERT INTO meta VALUES(1,1,?1,?2,?3,?4,?5,'1')");if(!s.text(1,schema_fingerprint)||!s.text(2,codec_fingerprint)||!s.text(3,store_id_.view())||!s.text(4,access_.filesystem_->owner_run_id())||!s.text(5,now.view())||row_step(db_,s,c)!=SQLITE_DONE)return fail(Error::io_error);}
 rc=observed_exec(db_,"COMMIT",Phase::before_commit,c,&frame(memory_).effects);auto n=c.next(Phase::after_commit,Scope::original);c.event(observation(db_,Phase::after_commit,Scope::original,Edge::after,n,rc,true));if(rc!=SQLITE_DONE)return rollback(db_,c,&frame(memory_).effects)?sql_error(rc):Error::commit_unknown;
 auto e=qualify(scratch,c);if(e!=Error::none)return Error::verification_failed;return Error::none;
}
RepositoryResult Store::start(bool management,Writer& terminal,NativeContext& c) {
 terminal.reset();terminal.raw("null");if(memory_.row.empty())return failure(Error::storage_full,false,true);if(!access_.valid()||db_)return failure(Error::io_error,false,true);frame(memory_).effects={};NativeOperationScope operation(c,memory_.hash_scratch,*access_.filesystem_);management_=management;
 auto e=access_.filesystem_->acquire_root(management,c);if(e!=Error::none)return failure(e,false,true);
 if(management){terminal.reset();terminal.raw("{\"management_only\":true}");return result(ResultState::read);}
 auto& summaries=renew(frame(memory_).summaries);std::size_t count{};
 e=access_.filesystem_->list_recovery(summaries,count,memory_.codec);
 if(e!=Error::none)return failure(e,false,true);
 auto& original=renew(frame(memory_).original);e=access_.filesystem_->inspect_sources(original);if(e!=Error::none)return failure(e,false,true);
 bool any=false;for(auto f:original.files)any|=f.present;
 if(!any){FileIdentity reserved;e=access_.filesystem_->reserve_new_database(reserved);if(e==Error::none)e=open(access_.filesystem_->root(),Scope::original,c,true,&reserved);if(e==Error::none)e=initialize(terminal,c);
  if(e!=Error::none){read_only_=e==Error::commit_unknown||e==Error::verification_failed;close();terminal.reset();terminal.raw("null");return read_only_?RepositoryResult{ResultState::uncertain,e,{},false,0,true,true,false}:failure(e,false,true);}
  qualified_=true;terminal.reset();terminal.raw("{\"created\":true,\"interrupted_rows\":0,\"store_version\":1}");auto r=result(ResultState::committed,sequence_);r.qualified=true;return r;
 }
 if(!original.files[0].present)return failure(Error::foreign_store,false,true);
 if(count==2)return failure(Error::recovery_limit,false,true);
 auto& recovery=renew(frame(memory_).recovery);e=access_.filesystem_->snapshot(original,recovery,memory_.io,memory_.codec,c);if(e!=Error::none)return failure(e,false,true);
 e=open(recovery.work_root.view(),Scope::qualification_copy,c,false);if(e==Error::none)e=qualify(terminal,c,Scope::qualification_copy);
 bool closed=!db_||sqlite3_close(db_)==SQLITE_OK;if(closed)db_=nullptr;else e=Error::io_error;
 if(e==Error::none)e=access_.filesystem_->remove_work(recovery);
 if(e==Error::none)e=access_.filesystem_->recheck_original(recovery,memory_.io);
 if(e==Error::none)e=open(access_.filesystem_->root(),Scope::original,c,false);
 if(e==Error::none)e=qualify(terminal,c);
 if(e!=Error::none){close();terminal.reset();terminal.raw("null");return failure(e,false,true);}
 qualified_=true;auto interrupted=interrupt_previous(terminal,c);if(interrupted.read_only)read_only_=true;interrupted.qualified=qualified_;return interrupted;
}
RepositoryResult Store::interrupt_previous(Writer& terminal,NativeContext& c) {
 terminal.reset();terminal.raw("null");
 FixedText<32> previous,id;{Statement s(db_,"SELECT owner_run_id FROM meta WHERE singleton=1");if(s.step()!=SQLITE_ROW||!previous.assign(col(s.p,0)))return failure(Error::corrupt_store,true);}
 {Statement s(db_,"SELECT id FROM practices WHERE status='active'");int rc=s.step();if(rc==SQLITE_DONE||previous.view()==access_.filesystem_->owner_run_id()){terminal.reset();terminal.raw("{\"created\":false,\"interrupted_rows\":0,\"store_version\":1}");return result(ResultState::read);}if(rc!=SQLITE_ROW||!id.assign(col(s.p,0))||s.step()!=SQLITE_DONE)return failure(Error::corrupt_store,true);}
 auto& row=renew(frame(memory_).rows[0]);auto e=fetch(db_,true,id.view(),row);U64 next,revision;if(e!=Error::none||validate_row(row,true,memory_)!=Error::none)return failure(Error::corrupt_store,true);if(!U64::increment(sequence_,next)||!U64::increment(row.revision,revision))return failure(Error::counter_exhausted,true);
 auto& changed=renew(frame(memory_).changed);{Lease lease(memory_);auto p=document(row.bytes.view(),memory_);if(!p)return failure(Error::corrupt_store,true);char rev[24],seq[24];Writer r(rev),s(seq);r.string(revision.view());s.string(next.view());Replacement updates[]={{"status","\"interrupted\""},{"end_reason","\"previous_process_incomplete\""},{"revision",r.bytes()},{"commit_sequence",s.bytes()}};Writer w({changed.data.data(),8192});if(!rewrite_object(w,p.value,p.value.root,updates))return failure(Error::payload_limit,true);changed.size=static_cast<std::uint32_t>(w.bytes().size());}
 int rc=observed_exec(db_,"BEGIN IMMEDIATE",Phase::before_begin,c,&frame(memory_).effects);if(rc!=SQLITE_DONE)return failure(sql_error(rc),true);row.bytes=changed;row.status.assign("interrupted");row.revision=revision;row.sequence=next;e=write_practice(db_,row,c);
 if(e==Error::none){Statement s(db_,"UPDATE meta SET owner_run_id=?1,commit_sequence=?2 WHERE singleton=1");if(!s.text(1,access_.filesystem_->owner_run_id())||!s.text(2,next.view())||row_step(db_,s,c)!=SQLITE_DONE)e=Error::io_error;}
 if(e!=Error::none)return rollback(db_,c,&frame(memory_).effects)?failure(e,true):RepositoryResult{ResultState::uncertain,Error::commit_unknown,{},false,0,true,false,true};
 rc=observed_exec(db_,"COMMIT",Phase::before_commit,c,&frame(memory_).effects);auto occurrence=c.next(Phase::after_commit,Scope::original);c.event(observation(db_,Phase::after_commit,Scope::original,Edge::after,occurrence,rc,true));if(rc!=SQLITE_DONE)return rollback(db_,c,&frame(memory_).effects)?failure(sql_error(rc),true):RepositoryResult{ResultState::uncertain,Error::commit_unknown,{},false,0,true,false,true};
 sequence_=next;auto& verified=renew(frame(memory_).rows[1]);if(fetch(db_,true,id.view(),verified)!=Error::none||verified.bytes.view()!=row.bytes.view()||qualify(terminal,c)!=Error::none){read_only_=true;terminal.reset();terminal.raw("null");return {ResultState::uncertain,Error::verification_failed,{},false,0,true,false,true};}
 terminal.reset();terminal.raw("{\"created\":false,\"interrupted_rows\":1,\"store_version\":1}");return result(ResultState::committed,next);
}
Error Store::checkpoint(NativeContext& c) {
 std::uint64_t bytes{};auto e=access_.filesystem_->wal_pressure(bytes);if(e!=Error::none)return e;if(bytes<33554432)return Error::none;
 auto n=c.next(Phase::checkpoint,Scope::original);c.event(observation(db_,Phase::checkpoint,Scope::original,Edge::before,n));int log{},done{};int rc=sqlite3_wal_checkpoint_v2(db_,"main",SQLITE_CHECKPOINT_TRUNCATE,&log,&done);auto o=observation(db_,Phase::checkpoint,Scope::original,Edge::after,n,rc,true);c.event(o);if(rc!=SQLITE_OK)return Error::storage_full;e=access_.filesystem_->wal_pressure(bytes);return e==Error::none&&bytes<33554432?Error::none:Error::storage_full;
}

namespace {
Error make_preferences(const Plan& p,Row& player,U64 revision,sqlite3* db,Writer& out,WorkingMemory& m,bool defaults) {
 out.reset();
 if(defaults){out.raw("{\"audio\":{\"airflow_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"enabled\":true,\"engine_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"show_panel_captions\":true},\"legacy_input\":null,\"piston_input\":null,\"player_id\":");out.string(player.id.view());out.raw(",\"revision\":\"1\",\"type\":\"LocalPlayerPreferences\",\"version\":1}");}
 else if(p.kind==JobKind::save_preferences){Lease lease(m);auto seed=document(p.preference_seed,m);if(!seed)return seed.error;auto d=seed.value;out.raw("{\"audio\":");out.raw(raw_node(d,d.member(d.root,"audio")));out.raw(",\"legacy_input\":");out.raw(raw_node(d,d.member(d.root,"legacy_input")));out.raw(",\"piston_input\":");out.raw(raw_node(d,d.member(d.root,"piston_input")));out.raw(",\"player_id\":");out.string(player.id.view());out.raw(",\"revision\":");out.string(revision.view());out.raw(",\"type\":\"LocalPlayerPreferences\",\"version\":1}");}
 else {auto e=preferences(db,player.id.view(),player.revision,out,m);if(e!=Error::none)return e;Lease lease(m);auto d=document(out.bytes(),m);if(!d)return d.error;char revision_text[24];Writer r(revision_text);r.string(revision.view());Replacement replacements[]={{"revision",r.bytes()}};Writer temp(m.codec.text);if(!rewrite_object(temp,d.value,d.value.root,replacements))return Error::payload_limit;auto n=temp.bytes().size();std::memmove(out.storage().data(),temp.bytes().data(),n);out.reset();out.raw({out.storage().data(),n});}
 if(!out.good())return Error::payload_limit;
 {Lease lease(m);auto parsed=document(out.bytes(),m);if(!parsed||validate_preferences(parsed.value,parsed.value.root,true,m.codec.cells)!=Error::none)return Error::invalid_record;
  // Payload already canonical from admitted normalized request/qualified row.
  // Retain the original tag bytes while checking reconstructed scalar types.
  auto payload=out.bytes();auto digest=sha256_hex(payload);Writer envelope(m.codec.text);envelope.raw("{\"format\":\"LocalPlayerPreferences\",\"payload_json\":");envelope.string(payload);envelope.raw(",\"payload_sha256\":");envelope.string({digest.data(),64});envelope.raw(",\"version\":1}");if(!envelope.good()||envelope.bytes().size()>max_preferences)return Error::payload_limit;auto n=envelope.bytes().size();std::memmove(out.storage().data(),envelope.bytes().data(),n);out.reset();out.raw({out.storage().data(),n});}
 return Error::none;
}
Error change_player(Row& row,const Plan& p,U64 revision,U64 sequence,WorkingMemory& m) {
 auto& changed=renew(frame(m).changed);{Lease lease(m);auto d=document(row.bytes.view(),m);if(!d)return Error::corrupt_store;char r[24],u[24];Writer rw(r),uw(u),nw(frame(m).name_json);rw.string(revision.view());uw.string(p.utc.view());nw.string(p.name.view());Replacement replacements[]={{"revision",rw.bytes()},{"updated_utc",uw.bytes()},{"name",nw.bytes()}};Writer w({changed.data.data(),8192});auto list=std::span(replacements,p.kind==JobKind::rename_player?3:2);if(!rewrite_object(w,d.value,d.value.root,list))return Error::payload_limit;changed.size=static_cast<std::uint32_t>(w.bytes().size());}
 row.bytes=changed;row.revision=revision;row.sequence=sequence;return Error::none;
}
Error build_practice(Row& row,const Plan& p,U64 sequence,WorkingMemory& m) {
 row.id=p.id;row.player=p.player;row.revision={};U64::parse("1",row.revision);row.creation=sequence;row.sequence=sequence;row.first=p.tick;row.tick=p.tick;row.status.assign("active");
 {Lease lease(m);auto source=document(p.source.view(),m);if(!source)return source.error;row.source_fp.from(source.value,source.value.member(source.value.root,"native_source_fingerprint"));row.session.from(source.value,source.value.member(source.value.root,"session_id"));}
 Writer w({row.bytes.data.data(),8192});w.raw("{\"archive\":null,\"commit_sequence\":");w.string(sequence.view());w.raw(",\"creation_sequence\":");w.string(sequence.view());w.raw(",\"end_reason\":null,\"first_tick\":");w.string(p.tick.view());w.raw(",\"id\":");w.string(p.id.view());w.raw(",\"last_observed_utc\":");w.string(p.utc.view());w.raw(",\"last_tick\":");w.string(p.tick.view());w.raw(",\"observed_ticks\":\"0\",\"player_id\":");w.string(p.player.view());w.raw(",\"revision\":\"1\",\"source\":");w.raw(p.source.view());w.raw(",\"started_utc\":");w.string(p.utc.view());w.raw(",\"status\":\"active\",\"tick_rate_hz\":120,\"type\":\"LocalPractice\",\"version\":1}");if(!w.good())return Error::payload_limit;row.bytes.size=static_cast<std::uint32_t>(w.bytes().size());return validate_row(row,true,m);
}
Error change_practice(Row& row,const Plan& p,U64 revision,U64 sequence,WorkingMemory& m) {
 auto& changed=renew(frame(m).changed);{Lease lease(m);auto d=document(row.bytes.view(),m);if(!d)return Error::corrupt_store;char rev[24],seq[24],tick[24],observed[24],utc[24],status[80],reason[80];Writer r(rev),s(seq),t(tick),o(observed),u(utc),st(status),er(reason);r.string(revision.view());s.string(sequence.view());t.string(p.tick.view());U64 delta;if(p.kind!=JobKind::link_archive&&!U64::subtract(p.tick,row.first,delta))return Error::tick_regression;o.string(delta.view());u.string(p.utc.view());st.string(p.status.view());er.string(p.end_reason.view());
  Replacement updates[7]={{"revision",r.bytes()},{"commit_sequence",s.bytes()}};unsigned count=2;
  if(p.kind==JobKind::link_archive)updates[count++]={"archive",p.archive.view()};else{updates[count++]={"last_tick",t.bytes()};updates[count++]={"observed_ticks",o.bytes()};updates[count++]={"last_observed_utc",u.bytes()};if(p.kind==JobKind::end_practice){updates[count++]={"status",st.bytes()};updates[count++]={"end_reason",er.bytes()};}}
  Writer w({changed.data.data(),8192});if(!rewrite_object(w,d.value,d.value.root,{updates,count}))return Error::payload_limit;changed.size=static_cast<std::uint32_t>(w.bytes().size());}
 row.bytes=changed;row.revision=revision;row.sequence=sequence;if(p.kind!=JobKind::link_archive)row.tick=p.tick;if(p.kind==JobKind::end_practice)row.status=p.status;return validate_row(row,true,m);
}
Error source_equal(const Row& row,const Plan& p,WorkingMemory& m,bool& same,std::string_view field="source") {
 Lease lease(m);auto d=document(row.bytes.view(),m);if(!d)return Error::corrupt_store;Writer w(m.codec.text);if(!w.value(d.value,d.value.member(d.value.root,field)))return Error::corrupt_store;same=w.bytes()==(field=="archive"?p.archive.view():p.source.view());return Error::none;
}
Error meta_sequence(sqlite3* db,U64 sequence,std::string_view run,NativeContext& c) {Statement s(db,"UPDATE meta SET commit_sequence=?1,owner_run_id=?2 WHERE singleton=1");if(!s.text(1,sequence.view())||!s.text(2,run))return Error::io_error;auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db,Phase::row_write,Scope::original,Edge::before,n));auto rc=s.step();c.event(observation(db,Phase::row_write,Scope::original,Edge::after,n,rc,true));return rc==SQLITE_DONE&&sqlite3_changes(db)==1?Error::none:sql_error(rc==SQLITE_DONE?SQLITE_CORRUPT:rc);}
}
RepositoryResult Store::transact(RequestView request,Writer& terminal,std::span<char>,NativeContext& c) {
 terminal.reset();terminal.raw("null");
 // RequestView here carries only its owned byte source. No indexed view crosses
 // the parse lease or survives owner admission reuse of the shared index.
 auto& p=renew(frame(memory_).plan);auto e=plan(request.document.bytes,memory_,p);if(e!=Error::none)return failure(e==Error::payload_limit||e==Error::out_of_memory?Error::storage_full:e==Error::invalid_record||e==Error::invalid_type||e==Error::invalid_request?Error::corrupt_store:e);
 e=checkpoint(c);if(e!=Error::none)return failure(e==Error::payload_limit||e==Error::out_of_memory?Error::storage_full:e==Error::invalid_record||e==Error::invalid_type||e==Error::invalid_request?Error::corrupt_store:e);
 int rc=observed_exec(db_,"BEGIN IMMEDIATE",Phase::before_begin,c,&frame(memory_).effects);
 if((rc==SQLITE_BUSY||rc==SQLITE_LOCKED)&&sqlite3_get_autocommit(db_)==1&&sqlite3_txn_state(db_,"main")==SQLITE_TXN_NONE)rc=observed_exec(db_,"BEGIN IMMEDIATE",Phase::before_begin,c,&frame(memory_).effects);
 if(rc!=SQLITE_DONE)return failure(sql_error(rc));
 auto abort=[&](Error error){if(error==Error::payload_limit||error==Error::out_of_memory)error=Error::storage_full;else if(error==Error::invalid_record||error==Error::invalid_type||error==Error::invalid_request)error=Error::corrupt_store;terminal.reset();terminal.raw("null");if(rollback(db_,c,&frame(memory_).effects))return failure(error);read_only_=true;return RepositoryResult{ResultState::uncertain,Error::commit_unknown,{},false,0,true,false,true};};
 auto unchanged=[&](U64 seq){if(!rollback(db_,c,&frame(memory_).effects)){terminal.reset();terminal.raw("null");read_only_=true;return RepositoryResult{ResultState::uncertain,Error::commit_unknown,{},false,0,true,false,true};}return result(ResultState::no_change,seq);};
 U64 next;auto next_sequence=[&]{return next.size!=0||U64::increment(sequence_,next);};
 bool player_operation=p.kind==JobKind::create_player||p.kind==JobKind::rename_player||p.kind==JobKind::save_preferences||p.kind==JobKind::delete_player;
 auto& row=renew(frame(memory_).rows[0]);bool exists=false,deleted=false;U64 revised;
 if(player_operation){if(p.kind==JobKind::create_player)p.player=p.id;e=fetch(db_,false,p.player.view(),row);exists=e==Error::none;if(e!=Error::none&&e!=Error::not_found)return abort(e);if(exists&&validate_row(row,false,memory_)!=Error::none)return abort(Error::corrupt_store);
  if(p.kind==JobKind::create_player){if(exists){bool same=false;{Lease lease(memory_);auto d=document(row.bytes.view(),memory_);same=d&&row.revision.view()=="1"&&d.value.string_is(d.value.member(d.value.root,"name"),p.name.view())&&d.value.string_is(d.value.member(d.value.root,"created_utc"),p.utc.view())&&d.value.string_is(d.value.member(d.value.root,"updated_utc"),p.utc.view());}
    if(!same)return abort(Error::identity_conflict);terminal.reset();e=preferences(db_,row.id.view(),row.revision,terminal,memory_);if(e!=Error::none)return abort(e);{Lease lease(memory_);auto d=document(terminal.bytes(),memory_);same=d&&d.value.at(d.value.member(d.value.root,"legacy_input"))->kind==ValueKind::null&&d.value.at(d.value.member(d.value.root,"piston_input"))->kind==ValueKind::null;auto audio=d?d.value.member(d.value.root,"audio"):no_cell;if(same){same=d.value.string_is(d.value.member(d.value.root,"revision"),"1");for(auto key:{"airflow_gain","engine_gain"}){double value{};same&=decode_binary64_tag(d.value,d.value.member(audio,key),value)&&std::bit_cast<std::uint64_t>(value)==0x3ff0000000000000ULL;}for(auto key:{"enabled","show_panel_captions"})same&=d.value.at(d.value.member(audio,key))->scalar==1;}}
    if(!same)return abort(Error::identity_conflict);e=pair(db_,row,terminal,memory_);if(e!=Error::none)return abort(e);return unchanged(row.sequence);
   }
   std::int64_t count{};if(scalar(db_,"SELECT count(*) FROM players",count)!=SQLITE_OK)return abort(Error::io_error);if(count>=8)return abort(Error::player_limit);if(!next_sequence())return abort(Error::counter_exhausted);
   row.id=p.id;row.player=p.id;U64::parse("1",row.revision);row.sequence=next;row.creation=next;Writer w({row.bytes.data.data(),8192});w.raw("{\"created_utc\":");w.string(p.utc.view());w.raw(",\"id\":");w.string(p.id.view());w.raw(",\"name\":");w.string(p.name.view());w.raw(",\"revision\":\"1\",\"type\":\"LocalPlayer\",\"updated_utc\":");w.string(p.utc.view());w.raw(",\"version\":1}");if(!w.good())return abort(Error::storage_full);row.bytes.size=static_cast<std::uint32_t>(w.bytes().size());e=make_preferences(p,row,row.revision,db_,terminal,memory_,true);if(e!=Error::none)return abort(e);e=write_player(db_,row,c);if(e==Error::none)e=write_preferences(db_,row.id.view(),row.revision,terminal.bytes(),c);if(e!=Error::none)return abort(e);
  }else{if(!exists)return abort(Error::not_found);if(U64::compare(row.revision,p.revision)!=0)return abort(Error::revision_conflict);
   if(p.kind==JobKind::delete_player){// Retire the read cursor before abort checks: rollback must observe no pending transaction.
    std::int64_t active_count{};
    const auto active_error=[&]{
     Statement active(db_,"SELECT count(*) FROM practices WHERE player_id=?1 AND status='active'");
     if(!active.text(1,p.player.view())||active.step()!=SQLITE_ROW)return Error::io_error;
     active_count=sqlite3_column_int64(active.p,0);
     if(active.step()!=SQLITE_DONE||active.close()!=SQLITE_OK)return Error::io_error;
     return Error::none;
    }();
    if(active_error!=Error::none)return abort(active_error);
    if(active_count!=0)return abort(Error::active_practice);if(!next_sequence())return abort(Error::counter_exhausted);Statement remove(db_,"DELETE FROM players WHERE id=?1");if(!remove.text(1,p.player.view()))return abort(Error::io_error);auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db_,Phase::row_write,Scope::original,Edge::before,n));rc=remove.step();c.event(observation(db_,Phase::row_write,Scope::original,Edge::after,n,rc,true));if(rc!=SQLITE_DONE||sqlite3_changes(db_)!=1)return abort(sql_error(rc==SQLITE_DONE?SQLITE_CORRUPT:rc));deleted=true;}
   else {bool same=false;if(p.kind==JobKind::rename_player){Lease lease(memory_);auto d=document(row.bytes.view(),memory_);same=d&&d.value.string_is(d.value.member(d.value.root,"name"),p.name.view());}else{terminal.reset();e=preferences(db_,row.id.view(),row.revision,terminal,memory_);if(e!=Error::none)return abort(e);{Lease lease(memory_);auto d=document(terminal.bytes(),memory_);e=d?Error::none:Error::corrupt_store;if(d){Writer seed(memory_.codec.text);seed.raw("{\"audio\":");seed.raw(raw_node(d.value,d.value.member(d.value.root,"audio")));seed.raw(",\"legacy_input\":");seed.raw(raw_node(d.value,d.value.member(d.value.root,"legacy_input")));seed.raw(",\"piston_input\":");seed.raw(raw_node(d.value,d.value.member(d.value.root,"piston_input")));seed.character('}');same=seed.good()&&seed.bytes()==p.preference_seed;}}if(e!=Error::none)return abort(e);}
    if(same){e=pair(db_,row,terminal,memory_);if(e!=Error::none)return abort(e);return unchanged(row.sequence);}
    if(!next_sequence()||!U64::increment(row.revision,revised))return abort(Error::counter_exhausted);e=make_preferences(p,row,revised,db_,terminal,memory_,false);if(e!=Error::none)return abort(e);e=write_preferences(db_,row.id.view(),revised,terminal.bytes(),c);if(e!=Error::none)return abort(e);e=change_player(row,p,revised,next,memory_);if(e==Error::none)e=write_player(db_,row,c);if(e!=Error::none)return abort(e);
   }
  }
 }else if(p.kind==JobKind::prune_practice){
  auto& player=renew(frame(memory_).rows[1]);e=fetch(db_,false,p.player.view(),player);if(e!=Error::none)return abort(e);if(validate_row(player,false,memory_)!=Error::none)return abort(Error::corrupt_store);for(unsigned i=0;i<p.count;++i){auto& selected=renew(frame(memory_).rows[2]);e=fetch(db_,true,p.ids[i].view(),selected);if(e!=Error::none)return abort(e);if(validate_row(selected,true,memory_)!=Error::none)return abort(Error::corrupt_store);if(selected.player.view()!=p.player.view())return abort(Error::not_found);if(selected.status.view()=="active")return abort(Error::active_practice);}
  if(!next_sequence())return abort(Error::counter_exhausted);
  for(unsigned i=0;i<p.count;++i){Statement remove(db_,"DELETE FROM practices WHERE id=?1 AND player_id=?2");if(!remove.text(1,p.ids[i].view())||!remove.text(2,p.player.view()))return abort(Error::io_error);auto n=c.next(Phase::row_write,Scope::original);c.event(observation(db_,Phase::row_write,Scope::original,Edge::before,n));rc=remove.step();c.event(observation(db_,Phase::row_write,Scope::original,Edge::after,n,rc,true));if(rc!=SQLITE_DONE||sqlite3_changes(db_)!=1)return abort(Error::io_error);}
 }else {
  e=fetch(db_,true,p.id.view(),row);exists=e==Error::none;if(e!=Error::none&&e!=Error::not_found)return abort(e);if(exists&&validate_row(row,true,memory_)!=Error::none)return abort(Error::corrupt_store);
  if(p.kind==JobKind::begin_practice){if(exists){bool same=false;e=source_equal(row,p,memory_,same);if(e!=Error::none)return abort(e);{Lease lease(memory_);auto d=document(row.bytes.view(),memory_);same&=d&&row.player.view()==p.player.view()&&U64::compare(row.first,p.tick)==0&&d.value.string_is(d.value.member(d.value.root,"started_utc"),p.utc.view());}if(!same)return abort(Error::identity_conflict);terminal.reset();terminal.raw("{\"practice\":");terminal.raw(row.bytes.view());terminal.character('}');return unchanged(row.sequence);}
   auto& player=renew(frame(memory_).rows[1]);e=fetch(db_,false,p.player.view(),player);if(e!=Error::none)return abort(e);if(validate_row(player,false,memory_)!=Error::none)return abort(Error::corrupt_store);std::int64_t count{};if(scalar(db_,"SELECT count(*) FROM practices",count)!=SQLITE_OK)return abort(Error::io_error);if(count>=2000)return abort(Error::history_limit);if(scalar(db_,"SELECT count(*) FROM practices WHERE status='active'",count)!=SQLITE_OK)return abort(Error::io_error);if(count)return abort(Error::active_practice);if(!next_sequence())return abort(Error::counter_exhausted);e=build_practice(row,p,next,memory_);if(e!=Error::none)return abort(e);
   // Resolve identity before abort so a duplicate-source reader cannot survive rollback.
   const auto identity_error=[&]{
    Statement identity(db_,"SELECT id FROM practices WHERE source_fingerprint=?1 AND source_session=?2");
    if(!identity.text(1,row.source_fp.view())||!identity.text(2,row.session.view()))return Error::io_error;
    const auto identity_rc=identity.step();
    if(identity_rc==SQLITE_ROW)return Error::identity_conflict;
    if(identity_rc!=SQLITE_DONE)return sql_error(identity_rc);
    return identity.close()==SQLITE_OK?Error::none:Error::io_error;
   }();
   if(identity_error!=Error::none)return abort(identity_error);e=write_practice(db_,row,c);if(e!=Error::none)return abort(e);
  }else {if(!exists||row.player.view()!=p.player.view())return abort(Error::not_found);if(U64::compare(row.revision,p.revision)!=0)return abort(Error::revision_conflict);bool same=false;e=source_equal(row,p,memory_,same);if(e!=Error::none)return abort(e);if(!same)return abort(Error::source_mismatch);
   if(p.kind==JobKind::link_archive){e=source_equal(row,p,memory_,same,"archive");if(e!=Error::none)return abort(e);if(!same){
    {Lease lease(memory_);auto d=document(row.bytes.view(),memory_);e=d?Error::none:Error::corrupt_store;auto& session=renew(frame(memory_).session);
     if(d){auto source=d.value.member(d.value.root,"source");if(!session.from(d.value,d.value.member(source,"session_id")))e=Error::corrupt_store;}
     if(e==Error::none){auto a=document(p.archive.view(),memory_);if(!a||!a.value.string_is(a.value.member(a.value.root,"recording_session_id"),session.view()))e=Error::source_mismatch;
      else{U64 first,last;if(!u64_at(a.value,a.value.member(a.value.root,"first_tick"),first)||!u64_at(a.value,a.value.member(a.value.root,"last_tick"),last)||U64::compare(first,row.first)<0||U64::compare(last,row.tick)>0)e=Error::invalid_transition;}}
    }
    if(e!=Error::none)return abort(e);
   }}
   else {if(U64::compare(p.tick,row.tick)<0)return abort(Error::tick_regression);if(row.status.view()!="active"){if(p.kind!=JobKind::end_practice)return abort(Error::invalid_transition);{Lease lease(memory_);auto d=document(row.bytes.view(),memory_);same=d&&row.status.view()==p.status.view()&&U64::compare(row.tick,p.tick)==0&&d.value.string_is(d.value.member(d.value.root,"end_reason"),p.end_reason.view());}if(!same)return abort(Error::invalid_transition);}else same=p.kind==JobKind::observe_practice&&U64::compare(p.tick,row.tick)==0;}
   if(same){terminal.reset();terminal.raw("{\"practice\":");terminal.raw(row.bytes.view());terminal.character('}');return unchanged(row.sequence);}
   if(!next_sequence()||!U64::increment(row.revision,revised))return abort(Error::counter_exhausted);e=change_practice(row,p,revised,next,memory_);if(e==Error::none)e=write_practice(db_,row,c);if(e!=Error::none)return abort(e);
  }
 }
 e=meta_sequence(db_,next,access_.filesystem_->owner_run_id(),c);if(e!=Error::none)return abort(e);
 rc=observed_exec(db_,"COMMIT",Phase::before_commit,c,&frame(memory_).effects);auto occurrence=c.next(Phase::after_commit,Scope::original);c.event(observation(db_,Phase::after_commit,Scope::original,Edge::after,occurrence,rc,true));if(rc!=SQLITE_DONE)return abort(sql_error(rc));
 sequence_=next;SqlTrace verification;auto verify_occurrence=c.next(Phase::postverify,Scope::original);c.event(observation(db_,Phase::postverify,Scope::original,Edge::before,verify_occurrence));
 bool verified=true;{Statement meta(db_,"SELECT commit_sequence FROM meta WHERE singleton=1");verified=meta.step()==SQLITE_ROW&&col(meta.p,0)==next.view()&&meta.step()==SQLITE_DONE;}
 terminal.reset();
 if(p.kind==JobKind::delete_player){auto& absent=renew(frame(memory_).rows[1]);verified&=fetch(db_,false,p.player.view(),absent)==Error::not_found;terminal.raw("{\"deleted_player_id\":");terminal.string(p.player.view());terminal.character('}');}
 else if(p.kind==JobKind::prune_practice){terminal.raw("{\"deleted_ids\":[");for(unsigned i=0;i<p.count;++i){auto& absent=renew(frame(memory_).rows[1]);verified&=fetch(db_,true,p.ids[i].view(),absent)==Error::not_found;if(i)terminal.character(',');terminal.string(p.ids[i].view());}terminal.raw("]}");}
 else {auto& actual=renew(frame(memory_).rows[1]);e=fetch(db_,!player_operation,row.id.view(),actual);verified&=e==Error::none&&actual.bytes.view()==row.bytes.view()&&validate_row(actual,!player_operation,memory_)==Error::none;if(player_operation){e=pair(db_,row,terminal,memory_);verified&=e==Error::none;}else{terminal.raw("{\"practice\":");terminal.raw(row.bytes.view());terminal.character('}');}}
 auto o=observation(db_,Phase::postverify,Scope::original,Edge::after,verify_occurrence,verification.observed_result(),verification.actual);o.verified_rows=verified?1:0;c.event(o);
 if(!verified||!terminal.good()){read_only_=true;terminal.reset();terminal.raw("null");return {ResultState::uncertain,Error::verification_failed,{},false,0,true,false,true};}
 return result(ResultState::committed,next);
}

RepositoryResult Store::read(RequestView request,Writer& terminal,std::span<char> spool,NativeContext& c) {
 auto& p=renew(frame(memory_).plan);auto e=plan(request.document.bytes,memory_,p);if(e!=Error::none)return failure(e==Error::payload_limit||e==Error::out_of_memory?Error::storage_full:e==Error::invalid_record||e==Error::invalid_type||e==Error::invalid_request?Error::corrupt_store:e);terminal.reset();
 bool is_export=p.kind==JobKind::export_player;auto& receipt=renew(frame(memory_).export_receipt);
 if(is_export){receipt.operation_id.assign(c.request_id);receipt.target=p.target;}
 auto error_value=[&]{terminal.reset();if(is_export)write_export_receipt(terminal,receipt);else terminal.raw("null");};
 if(p.kind==JobKind::list_recovery){auto& rows=renew(frame(memory_).summaries);std::size_t count{};e=access_.filesystem_->list_recovery(rows,count,memory_.codec);if(e!=Error::none){terminal.raw("null");return failure(e);}terminal.raw("{\"snapshots\":[");for(std::size_t i=0;i<count;++i){auto& r=rows[i];if(i)terminal.character(',');terminal.raw("{\"bytes\":");terminal.integer(static_cast<std::int64_t>(r.bytes));terminal.raw(",\"created_utc\":");if(r.has_utc)terminal.string(r.created_utc.view());else terminal.raw("null");terminal.raw(",\"id\":");terminal.string(r.id.view());terminal.raw(",\"manifest_sha256\":");if(r.has_manifest_hash)terminal.string({r.manifest_hash.data(),64});else terminal.raw("null");terminal.raw(",\"state\":");terminal.string(r.complete?"complete":"partial");terminal.character('}');}terminal.raw("]}");return result(ResultState::read);}
 if(p.kind==JobKind::delete_recovery){if(!management_||db_){terminal.raw("null");return failure(Error::io_error);}e=access_.filesystem_->delete_recovery({p.ids.data(),p.count},terminal,memory_.codec,memory_.io,c);if(e!=Error::none){if(terminal.bytes().empty())terminal.raw("null");return failure(e);}return result(ResultState::read);}
 if(!qualified_||!db_){error_value();return failure(Error::io_error,read_only_);}
 int rc=observed_exec(db_,"BEGIN",Phase::before_begin,c);if(rc!=SQLITE_DONE){error_value();return failure(sql_error(rc));}
 auto fail=[&](Error error){if(error==Error::payload_limit||error==Error::out_of_memory)error=Error::storage_full;else if(error==Error::invalid_record||error==Error::invalid_type||error==Error::invalid_request)error=Error::corrupt_store;bool rolled=rollback(db_,c,&frame(memory_).effects);error_value();if(!rolled){read_only_=true;return failure(Error::io_error,true);}return failure(error);};
 auto& player=renew(frame(memory_).rows[0]);bool needs_player=p.kind!=JobKind::list_players;
 if(needs_player){e=fetch(db_,false,p.player.view(),player);if(e!=Error::none)return fail(e);e=validate_row(player,false,memory_);if(e!=Error::none)return fail(e);}
 if(p.kind==JobKind::list_players){terminal.raw("{\"players\":[");Statement rows(db_,"SELECT id FROM players ORDER BY id COLLATE BINARY");unsigned count=0;while((rc=rows.step())==SQLITE_ROW){FixedText<32> id;if(!id.assign(col(rows.p,0)))return fail(Error::corrupt_store);auto& row=renew(frame(memory_).rows[1]);e=fetch(db_,false,id.view(),row);if(e!=Error::none||validate_row(row,false,memory_)!=Error::none)return fail(Error::corrupt_store);if(++count>8)return fail(Error::corrupt_store);auto& name=renew(frame(memory_).name);{Lease lease(memory_);auto d=document(row.bytes.view(),memory_);if(!d||!name.from(d.value,d.value.member(d.value.root,"name")))e=Error::corrupt_store;}if(e!=Error::none)return fail(e);if(count>1)terminal.character(',');terminal.raw("{\"id\":");terminal.string(id.view());terminal.raw(",\"name\":");terminal.string(name.view());terminal.raw(",\"revision\":");terminal.string(row.revision.view());terminal.character('}');}if(rc!=SQLITE_DONE)return fail(sql_error(rc));terminal.raw("]}");}
 else if(p.kind==JobKind::load_player){e=pair(db_,player,terminal,memory_);if(e!=Error::none)return fail(e);}
 else if(p.kind==JobKind::load_practice){auto& row=renew(frame(memory_).rows[1]);e=fetch(db_,true,p.id.view(),row);if(e!=Error::none)return fail(e);if(row.player.view()!=p.player.view())return fail(Error::not_found);if(validate_row(row,true,memory_)!=Error::none)return fail(Error::corrupt_store);terminal.raw("{\"practice\":");terminal.raw(row.bytes.view());terminal.character('}');}
 else if(p.kind==JobKind::list_practice||p.kind==JobKind::export_player){
  bool exporting=is_export;
  Writer export_payload(spool);Writer* rows_out=&terminal;
  if(exporting){if(U64::compare(player.revision,p.revision)!=0)return fail(Error::revision_conflict);if(spool.size()!=18874368)return fail(Error::storage_full);e=preferences(db_,p.player.view(),player.revision,terminal,memory_);if(e!=Error::none)return fail(e);export_payload.raw("{\"player\":");export_payload.raw(player.bytes.view());export_payload.raw(",\"practice\":[");rows_out=&export_payload;}
  else terminal.raw("{\"next_before_creation_sequence\":");
  // The cursor is full-range canonical U64 numeric order, not text/rowid/time.
  Statement scan(db_,"SELECT id FROM practices WHERE player_id=?1 AND (?2=0 OR length(creation_sequence)<length(?3) OR (length(creation_sequence)=length(?3) AND creation_sequence COLLATE BINARY<?3)) ORDER BY length(creation_sequence) DESC,creation_sequence COLLATE BINARY DESC LIMIT ?4");if(!scan.text(1,p.player.view())||sqlite3_bind_int(scan.p,2,!exporting&&p.has_cursor)!=SQLITE_OK||!scan.text(3,p.cursor.view())||sqlite3_bind_int(scan.p,4,exporting?2001:p.limit+1)!=SQLITE_OK)return fail(Error::io_error);
  // List prefix reserves at most24 bytes for the next cursor. Rows are emitted
  // after it, then the prefix is filled once an actual extra row is witnessed.
  std::size_t prefix=0;if(!exporting){prefix=terminal.bytes().size();terminal.raw("                        ,\"practice\":[");}
  unsigned count=0;bool more=false;U64 last{};
  while((rc=scan.step())==SQLITE_ROW){if(!exporting&&count==static_cast<unsigned>(p.limit)){more=true;break;}if(count==2000)return fail(Error::corrupt_store);FixedText<32> id;if(!id.assign(col(scan.p,0)))return fail(Error::corrupt_store);auto& row=renew(frame(memory_).rows[1]);e=fetch(db_,true,id.view(),row);if(e!=Error::none||row.player.view()!=p.player.view()||validate_row(row,true,memory_)!=Error::none)return fail(Error::corrupt_store);
   if(count)rows_out->character(',');bool good=false;{Lease lease(memory_);auto d=document(row.bytes.view(),memory_);if(d){auto archive=d.value.member(d.value.root,"archive");bool linked=d.value.at(archive)->kind!=ValueKind::null;Replacement replacement[]={{"archive",linked?"{\"linked\":true}":"{\"linked\":false}"}};good=rewrite_object(*rows_out,d.value,d.value.root,replacement);}}if(!good)return fail(Error::storage_full);last=row.creation;++count;
  }
  if(rc!=SQLITE_DONE&&!(more&&rc==SQLITE_ROW))return fail(sql_error(rc));
  // A partially read page cursor is finalized before ending its transaction.
  if(scan.close()!=SQLITE_OK)return fail(Error::io_error);rows_out->character(']');
  if(exporting){export_payload.raw(",\"preferences\":");export_payload.raw(terminal.bytes());export_payload.character('}');if(!export_payload.good()||export_payload.bytes().size()>18874368)return fail(Error::storage_full);
   // Coherent snapshot ends before any target filesystem operation or barrier.
   rc=observed_exec(db_,"COMMIT",Phase::before_commit,c);{auto n=c.next(Phase::after_commit,Scope::original);c.event(observation(db_,Phase::after_commit,Scope::original,Edge::after,n,rc,true));}if(rc!=SQLITE_DONE||sqlite3_get_autocommit(db_)!=1||sqlite3_txn_state(db_,"main")!=SQLITE_TXN_NONE)return fail(Error::io_error);
   receipt.has_snapshot=true;receipt.player_id=p.player;receipt.preferences_revision=player.revision;receipt.practice_count=static_cast<std::uint16_t>(count);
   e=access_.filesystem_->export_new(p.target.view(),export_payload.bytes(),receipt,memory_.io,c);terminal.reset();if(!write_export_receipt(terminal,receipt))return failure(Error::storage_full);if(receipt.outcome==ExportReceipt::Outcome::saved)return result(ResultState::read);if(receipt.outcome==ExportReceipt::Outcome::recovery_required)return {ResultState::recovery_required,Error::file_recovery_required};return failure(e==Error::none?Error::file_verify_failed:e);
  }
  terminal.character('}');char cursor[24];Writer w(cursor);if(more)w.string(last.view());else w.raw("null");auto tail=prefix+24;auto length=terminal.bytes().size();std::memmove(terminal.storage().data()+prefix+w.bytes().size(),terminal.storage().data()+tail,length-tail);std::memcpy(terminal.storage().data()+prefix,w.bytes().data(),w.bytes().size());terminal.reset();terminal.raw({terminal.storage().data(),length-24+w.bytes().size()});if(terminal.bytes().size()>409600)return fail(Error::storage_full);
 }else return fail(Error::io_error);
 if(!terminal.good())return fail(Error::storage_full);rc=observed_exec(db_,"COMMIT",Phase::before_commit,c);{auto n=c.next(Phase::after_commit,Scope::original);c.event(observation(db_,Phase::after_commit,Scope::original,Edge::after,n,rc,true));}if(rc!=SQLITE_DONE||sqlite3_get_autocommit(db_)!=1||sqlite3_txn_state(db_,"main")!=SQLITE_TXN_NONE)return fail(Error::io_error);return result(ResultState::read);
}
RepositoryResult Store::recover_unexpected(JobKind kind,Writer& terminal,NativeContext& c) noexcept {
 // This boundary never guesses that every thrown callback means COMMIT. The
 // scalar effect marker is set immediately before each actual mutating SQL call.
 // Recovery management has its own closed error matrix, not worker_lost.
 // delete_recovery catches effectful failures in its platform implementation
 // and retains the actual deleted/retained ledger. Never erase that value.
 if(kind==JobKind::list_recovery||kind==JobKind::delete_recovery){
  if(kind==JobKind::list_recovery||!terminal.good()||terminal.bytes().empty()){
   terminal.reset();terminal.raw("null");
  }
  return failure(Error::snapshot_failed,read_only_);
 }
 terminal.reset();
 if(kind==JobKind::export_player){
  auto& r=frame(memory_).export_receipt;
  bool after_move=r.phase==ExportReceipt::Step::move||r.phase==ExportReceipt::Step::verify_target||r.phase==ExportReceipt::Step::done;
  r.outcome=after_move?ExportReceipt::Outcome::recovery_required:ExportReceipt::Outcome::not_saved;
  write_export_receipt(terminal,r);
  return {after_move?ResultState::recovery_required:ResultState::failed,after_move?Error::file_recovery_required:Error::worker_lost,{},false,0,read_only_,false,qualified_};
 }
 terminal.raw("null");auto& effect=frame(memory_).effects;
 bool unknown=effect.commit_attempted||effect.committed;
 if(effect.mutation_possible&&!unknown){
  bool rolled=false;try{rolled=db_&&rollback(db_,c,&effect);}catch(...){rolled=false;}
  unknown=!rolled;
 }
 if(unknown){read_only_=true;return {ResultState::uncertain,Error::commit_unknown,{},false,0,true,false,qualified_};}
 // Read-only operations cannot become an uncertain DB mutation. Prove their
 // transaction ended where possible; failure disables further writes only.
 if(db_&&sqlite3_get_autocommit(db_)==0){bool rolled=false;try{rolled=rollback(db_,c,&effect);}catch(...){rolled=false;}if(!rolled)read_only_=true;}
 bool starting=kind==JobKind::start||kind==JobKind::start_management;
 if(starting)close();return failure(Error::worker_lost,read_only_,starting);
}
RepositoryResult Store::fail_unstarted(JobKind kind,std::string_view owned,Writer& terminal,NativeContext& c) noexcept {
 terminal.reset();terminal.raw("null");
 if(kind==JobKind::list_recovery||kind==JobKind::delete_recovery)return failure(Error::snapshot_failed,read_only_);
 if(kind==JobKind::export_player){
  // Request bytes were validated and copied before admission. Seed only the
  // requested target/operation identity; no snapshot or file action occurred.
  auto& p=renew(frame(memory_).plan);auto& receipt=renew(frame(memory_).export_receipt);
  auto e=plan(owned,memory_,p);receipt.operation_id.assign(c.request_id);receipt.target=p.target;
  terminal.reset();write_export_receipt(terminal,receipt);
  return failure(e==Error::none?Error::worker_lost:Error::io_error,read_only_);
 }
 return failure(Error::worker_lost,read_only_,kind==JobKind::start||kind==JobKind::start_management);
}
RepositoryResult Store::execute(std::string_view owned,Writer& terminal,std::span<char> spool,NativeContext& c) {
 terminal.reset();terminal.raw("null");
 frame(memory_).effects={};NativeOperationScope operation(c,memory_.hash_scratch,*access_.filesystem_);RequestView request;{Lease lease(memory_);auto parsed=document(owned,memory_);auto e=parsed?validate_request(parsed.value,request,true,memory_.codec.cells):parsed.error;if(e!=Error::none){terminal.reset();terminal.raw("null");return failure(e==Error::payload_limit||e==Error::out_of_memory?Error::storage_full:Error::corrupt_store);}}request.document={owned,{},no_cell};
 bool mutation=request.kind==JobKind::create_player||request.kind==JobKind::rename_player||request.kind==JobKind::save_preferences||request.kind==JobKind::begin_practice||request.kind==JobKind::observe_practice||request.kind==JobKind::end_practice||request.kind==JobKind::link_archive||request.kind==JobKind::prune_practice||request.kind==JobKind::delete_player;
 // A write admitted before a preceding uncertainty drains without beginning.
 // Admission-only invalid_state is not a closed terminal code. The service
 // retains its earlier stronger commit_unknown/verification_failed diagnostic.
 if(mutation&&(!qualified_||read_only_||management_)){terminal.raw("null");return failure(Error::io_error,read_only_);}
 auto r=mutation?transact(request,terminal,spool,c):read(request,terminal,spool,c);if(r.read_only)read_only_=true;r.qualified=qualified_;r.read_only|=read_only_;return r;
}
} // namespace flight::local_players
